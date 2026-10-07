import 'package:hizip/ui/desktop_widgets.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/main.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/models/browsing_preferences.dart';
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

        await tester.tap(cell(0));
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
    await tester.tap(find.byType(FTextField));
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
    expect(find.text('HiZip'), findsOneWidget);
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
    await tester.tap(find.byIcon(Icons.menu));
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
    await tester.tap(find.byTooltip('应用菜单'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('application-menu')), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('显示'), findsOneWidget);
    expect(find.text('设置…'), findsOneWidget);
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('打开…'), findsOneWidget);
    expect(find.text('创建压缩包'), findsOneWidget);
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
