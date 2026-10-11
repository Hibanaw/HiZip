import 'package:hizip/ui/desktop_widgets.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/main.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/models/theme_accent.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/file_item_surface.dart';

class TestService extends ArchiveService {
  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async =>
      Uint8List.fromList('test'.codeUnits);
}

class QuickLookService extends TestService {
  @override
  Future<OpenedArchiveFile> prepareExternal(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) async => OpenedArchiveFile(
    doc.path,
    entry.path,
    '/tmp/${entry.name}',
    '',
    '',
    FileStat.statSync('/tmp'),
  );
}

class MacDesktop extends DesktopIntegration {
  @override
  bool get supportsQuickLook => true;
  @override
  bool get supportsFileIntegration => true;
}

class TestDesktop extends DesktopIntegration {
  @override
  bool get supportsQuickLook => false;
  @override
  Future<DefaultApplication?> defaultApplication(String name) async =>
      const DefaultApplication('TextEdit', null);
}

class NoMenuBarDesktop extends TestDesktop {
  @override
  bool get supportsMenuBar => false;
}

final sample = ArchiveDocument(
  '/sample.zip',
  const [
    ArchiveEntry(path: 'docs/nested/a.txt', size: 4, directory: false),
    ArchiveEntry(path: 'docs/b.txt', size: 4, directory: false),
    ArchiveEntry(path: 'empty/', size: 0, directory: true),
    ArchiveEntry(path: 'one.txt', size: 4, directory: false),
    ArchiveEntry(path: 'two.txt', size: 4, directory: false),
  ],
  'ZIP',
  true,
);
void size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> workspace(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    builder: foruiBuilder,
    home: ArchiveWorkspace(
      enableNativeTransfers: false,
      initialDocument: sample,
      service: TestService(),
      desktop: TestDesktop(),
    ),
  ),
);

void main() {
  testWidgets('light selected file name and lock icon follow accent contrast', (
    tester,
  ) async {
    size(tester, const Size(1200, 700));
    final settings = AppSettings(writeBrowsing: (_) async {});
    addTearDown(settings.dispose);
    await settings.setBrowsing(
      const BrowsingPreferences(view: 'list', inspector: false),
    );
    final doc = ArchiveDocument(
      '/locked.zip',
      const [
        ArchiveEntry(
          path: 'locked.txt',
          size: 4,
          directory: false,
          encrypted: true,
        ),
      ],
      'ZIP',
      false,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          initialDocument: doc,
          settings: settings,
          service: TestService(),
          desktop: TestDesktop(),
          enableNativeTransfers: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('file-locked.txt'));
    final lock = find.descendant(
      of: cell,
      matching: find.byIcon(CupertinoIcons.lock),
    );
    final onAccent = Theme.of(tester.element(cell)).colorScheme.onPrimary;
    expect(tester.widget<Icon>(lock).color, isNot(onAccent));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(lock).color, onAccent);
    final name = find.descendant(of: cell, matching: find.text('locked.txt'));
    expect(tester.widget<Text>(name).style!.color, onAccent);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final brightness in Brightness.values) {
    testWidgets('background Hi follows theme accent in $brightness', (
      tester,
    ) async {
      for (final accent in [ThemeAccent.blue, ThemeAccent.rose]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: desktopTheme(brightness: brightness, accent: accent),
            builder: foruiBuilder,
            home: ArchiveWorkspace(
              initialDocument: sample,
              service: TestService(),
              desktop: TestDesktop(),
              enableNativeTransfers: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final watermark = tester.widget<Text>(
          find.byKey(const ValueKey('workspace-watermark')),
        );
        final spans = (watermark.textSpan! as TextSpan).children!;
        expect(watermark.textSpan!.toPlainText(), 'HiZip');
        expect((spans.first as TextSpan).text, 'Hi');
        expect(
          spans.first.style!.color,
          accent
              .colorFor(brightness)
              .withValues(alpha: brightness == Brightness.light ? .8 : .5),
        );
        expect((spans.last as TextSpan).text, 'Zip');
        expect(spans.last.style, isNull);
        expect(
          watermark.style!.color,
          brightness == Brightness.dark
              ? const Color(0x0dffffff)
              : const Color(0xffb0b0b0),
        );
        if (brightness == Brightness.light) {
          final gray = watermark.style!.color!;
          expect(gray.r, gray.g);
          expect(gray.g, gray.b);
          expect(gray.computeLuminance(), inExclusiveRange(.4, .6));
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final width in [900.0, 1440.0]) {
    testWidgets(
      'grid arrows follow cells and reveal selection at width $width',
      (tester) async {
        size(tester, Size(width, 350));
        final settings = AppSettings(writeBrowsing: (_) async {});
        await settings.setBrowsing(
          const BrowsingPreferences(view: 'grid', inspector: false),
        );
        final doc = ArchiveDocument(
          '/grid.zip',
          List.generate(
            31,
            (i) => ArchiveEntry(
              path: '${i.toString().padLeft(2, '0')}.bin',
              size: 1,
              directory: false,
            ),
          ),
          'ZIP',
          true,
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: foruiBuilder,
            home: ArchiveWorkspace(
              settings: settings,
              initialDocument: doc,
              service: TestService(),
              desktop: TestDesktop(),
              enableNativeTransfers: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final grid = tester.widget<GridView>(find.byType(GridView));
        final columns =
            (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
                .crossAxisCount;
        expect(columns, greaterThan(1));
        Finder cell(int i) =>
            find.byKey(ValueKey('file-${i.toString().padLeft(2, '0')}.bin'));
        void selected(int i) =>
            expect(tester.widget<FileItemSurface>(cell(i)).selected, isTrue);
        Future<void> arrow(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        await tester.tap(
          find.byKey(const ValueKey('grid-icon-background-00.bin')),
        );
        await arrow(LogicalKeyboardKey.arrowRight);
        selected(1);
        await arrow(LogicalKeyboardKey.arrowDown);
        selected(columns + 1);
        await arrow(LogicalKeyboardKey.arrowLeft);
        selected(columns);
        await arrow(LogicalKeyboardKey.arrowUp);
        selected(0);
        await arrow(LogicalKeyboardKey.arrowUp);
        await arrow(LogicalKeyboardKey.arrowLeft);
        selected(0);
        await arrow(LogicalKeyboardKey.arrowRight);
        for (var i = 0; i < 31; i++) {
          await arrow(LogicalKeyboardKey.arrowDown);
        }
        final lastInColumn = 1 + ((30 - 1) ~/ columns) * columns;
        selected(lastInColumn);
        final bounds = tester.getRect(find.byType(GridView));
        final item = tester.getRect(cell(lastInColumn));
        expect(item.top, greaterThanOrEqualTo(bounds.top));
        expect(item.bottom, lessThanOrEqualTo(bounds.bottom + .1));
        expect(grid.controller!.offset, greaterThan(0));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      },
    );
  }
  testWidgets('search keeps space and editing shortcuts for text input', (
    tester,
  ) async {
    size(tester, const Size(1440, 900));
    await workspace(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.space), false);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.enterText(find.byType(EditableText), 'one two');
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'one two',
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [1440.0, 440.0]) {
    testWidgets('search collapses outside and on focus loss at width $width', (
      tester,
    ) async {
      size(tester, Size(width, 900));
      await workspace(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('archive-search')), findsNothing);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('archive-search')), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'one');
      await tester.pump(const Duration(milliseconds: 200));
      // Wait for the real search isolate before settling fake-time animations.
      final dynamic workspaceState = tester.state(
        find.byType(ArchiveWorkspace),
      );
      await tester.runAsync(() async {
        for (
          var attempt = 0;
          attempt < 200 && workspaceState.taskQueue.tasks.isNotEmpty;
          attempt++
        ) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(workspaceState.taskQueue.tasks, isEmpty);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file-one.txt')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('archive-search')), findsNothing);
      expect(find.byKey(const ValueKey('file-two.txt')), findsNothing);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      final input = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('archive-search')),
          matching: find.byType(EditableText),
        ),
      );
      expect(input.controller.text, 'one');
      expect(input.focusNode.hasFocus, true);
      input.focusNode.unfocus();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('archive-search')), findsNothing);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('archive-search')), findsNothing);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear-archive-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('archive-search')), findsOneWidget);
      expect(input.controller.text, isEmpty);
      expect(find.byKey(const ValueKey('file-two.txt')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('file icon cache separates resolutions and reuses nearby sizes', (
    tester,
  ) async {
    final requests = <Map<dynamic, dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DesktopIntegration.channel,
      (call) async {
        if (call.method == 'fileIcon') {
          requests.add(call.arguments as Map);
          return Uint8List.fromList([requests.length]);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopIntegration.channel,
        null,
      ),
    );
    final desktop = MacDesktop();
    final small = await desktop.fileIcon('first.zip', pixelSize: 44);
    final large = await desktop.fileIcon('first.zip', pixelSize: 360);
    expect(await desktop.fileIcon('second.zip', pixelSize: 400), same(large));
    expect(await desktop.fileIcon('second.zip', pixelSize: 48), same(small));
    await desktop.fileIcon('folder', directory: true, pixelSize: 360);
    await desktop.fileIcon('first.zip', pixelSize: 4096);
    expect(requests.map((request) => request['pixelSize']), [
      64,
      512,
      512,
      1024,
    ]);
    expect(requests[2]['directory'], true);
  });
  testWidgets('inspector requests more icon pixels on a Retina display', (
    tester,
  ) async {
    size(tester, const Size(1440, 900));
    final requests = <Map<dynamic, dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DesktopIntegration.channel,
      (call) async {
        if (call.method == 'fileIcon') requests.add(call.arguments as Map);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopIntegration.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          enableNativeTransfers: false,
          initialDocument: sample,
          service: TestService(),
          desktop: MacDesktop(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final regular = requests.singleWhere(
      (request) => request['path'] == 'sample.zip',
    );
    expect(regular['pixelSize'], 256);
    requests.clear();
    tester.view.physicalSize = const Size(2880, 1800);
    tester.view.devicePixelRatio = 2;
    await tester.pumpAndSettle();
    final retina = requests.singleWhere(
      (request) => request['path'] == 'sample.zip',
    );
    expect(retina['pixelSize'], 512);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty desktop contains file actions without promotional copy', (
    tester,
  ) async {
    size(tester, const Size(1440, 900));
    await tester.pumpWidget(const HiZipApp());
    expect(find.text('HiZip'), findsWidgets);
    expect(find.text('未打开压缩包'), findsWidgets);
    expect(find.textContaining('整理得更轻'), findsNothing);
    expect(find.text('LESS SIZE. MORE SPACE.'), findsNothing);
    expect(find.byTooltip('创建压缩包'), findsNothing);
    expect(find.byTooltip('打开压缩包'), findsNothing);
    expect(find.byTooltip('设置'), findsNothing);
    expect(find.text('打开压缩包'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('phone directory drawer works without overflow', (tester) async {
    size(tester, const Size(390, 844));
    await tester.pumpWidget(const HiZipApp());
    await tester.tap(find.byKey(const ValueKey('directory-drawer-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('application menu is shown without a native menubar', (
    tester,
  ) async {
    size(tester, const Size(1440, 900));
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          enableNativeTransfers: false,
          initialDocument: sample,
          service: TestService(),
          desktop: NoMenuBarDesktop(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final menuButton = find.byTooltip('应用菜单');
    final backButton = find.byTooltip('返回');
    for (final width in [390.0, 700.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(menuButton).right,
        lessThanOrEqualTo(tester.getRect(backButton).left),
      );
      if (width < 800) {
        final directoryButton = find.byKey(
          const ValueKey('directory-drawer-toggle'),
        );
        expect(
          find.descendant(
            of: directoryButton,
            matching: find.byIcon(FIcons.folderTree),
          ),
          findsOneWidget,
        );
      } else {
        expect(
          find.byKey(const ValueKey('directory-drawer-toggle')),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    }
    expect(
      find.descendant(of: menuButton, matching: find.byIcon(Icons.menu)),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('应用菜单'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('application-menu')), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('显示'), findsOneWidget);
    expect(find.text('设置…'), findsOneWidget);
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('打开压缩包…'), findsOneWidget);
    expect(find.text('创建压缩包…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'directory tree expands and navigates implicit and empty folders',
    (tester) async {
      size(tester, const Size(1440, 900));
      await workspace(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tree-docs')), findsOneWidget);
      expect(find.byKey(const ValueKey('tree-empty')), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('tree-docs')),
          matching: find.text('docs'),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('tree-docs/nested')), findsOneWidget);
      expect(find.byKey(const ValueKey('file-docs/b.txt')), findsOneWidget);
      expect(find.byKey(const ValueKey('file-one.txt')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'up and down move selection and show the associated application',
    (tester) async {
      size(tester, const Size(1440, 900));
      await workspace(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file-one.txt')));
      await tester.pump();
      expect(
        tester
            .widget<FileItemSurface>(find.byKey(const ValueKey('file-one.txt')))
            .selected,
        true,
      );
      expect(find.text('用 TextEdit 打开'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        tester
            .widget<FileItemSurface>(find.byKey(const ValueKey('file-two.txt')))
            .selected,
        true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        tester
            .widget<FileItemSurface>(find.byKey(const ValueKey('file-one.txt')))
            .selected,
        true,
      );
      // Typing spaces and cursor movement in search must not navigate the list.
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'one');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        tester
            .widget<FileItemSurface>(find.byKey(const ValueKey('file-one.txt')))
            .selected,
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('pointer selection and double click activate immediately', (
    tester,
  ) async {
    var selected = 0, opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: FileItemSurface(
          name: 'folder',
          selected: false,
          onSelect: () => selected++,
          onActivate: () => opened++,
          child: const SizedBox(width: 200, height: 40),
        ),
      ),
    );
    final point = tester.getCenter(find.byType(FileItemSurface));
    final first = await tester.createGesture();
    await first.down(point, timeStamp: const Duration(milliseconds: 10));
    expect(selected, 1); // No pump or 300 ms double-tap delay.
    await first.up(timeStamp: const Duration(milliseconds: 30));
    final second = await tester.createGesture();
    await second.down(point, timeStamp: const Duration(milliseconds: 90));
    await second.up(timeStamp: const Duration(milliseconds: 110));
    expect(opened, 1); // Activation is immediate on the second pointer up.
    expect(find.byType(InkWell), findsNothing);
  });
  testWidgets(
    'space toggles native Quick Look and native arrows synchronize selection',
    (tester) async {
      size(tester, const Size(1440, 900));
      var visible = false;
      String? shown;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopIntegration.channel,
        (call) async {
          switch (call.method) {
            case 'fileIcon':
              return null;
            case 'defaultApplication':
              return {'name': 'TextEdit'};
            case 'quickLookVisible':
              return visible;
            case 'quickLook':
              visible = true;
              shown = (call.arguments as Map)['path'] as String;
              return null;
            case 'closeQuickLook':
              visible = false;
              return null;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          DesktopIntegration.channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          home: ArchiveWorkspace(
            enableNativeTransfers: false,
            initialDocument: sample,
            service: QuickLookService(),
            desktop: MacDesktop(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file-one.txt')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(visible, true);
      expect(shown, '/tmp/one.txt');
      expect(find.byType(Dialog), findsNothing);
      final reply = Completer<void>();
      tester.binding.channelBuffers.push(
        DesktopIntegration.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('quickLookNavigate', 1),
        ),
        (_) => reply.complete(),
      );
      await reply.future;
      await tester.pumpAndSettle();
      expect(shown, '/tmp/two.txt');
      expect(
        tester
            .widget<FileItemSurface>(find.byKey(const ValueKey('file-two.txt')))
            .selected,
        true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(visible, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
