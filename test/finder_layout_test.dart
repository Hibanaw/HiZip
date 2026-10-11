import 'package:hizip/ui/desktop_widgets.dart';

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/app_language.dart';
import 'package:hizip/models/extraction_progress.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/models/selection_highlight.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/file_item_surface.dart';
import 'package:hizip/services/task_windows.dart';

class FinderPropertiesWindow extends PropertiesWindowTransport {
  Map<String, dynamic>? data;
  PropertiesWindowAction? action;
  @override
  Future<bool> show(
    Map<String, dynamic> data,
    PropertiesWindowAction action,
  ) async {
    this.data = data;
    this.action = action;
    return true;
  }

  @override
  void dispose() {}
}

class FinderService extends ArchiveService {
  String? prepared;
  ArchiveDocument? extractionDocument;
  ArchiveEntry? extractionEntry;
  List<ArchiveEntry>? extractionRoots;
  @override
  Future<String> extract(
    ArchiveDocument doc,
    String destination, {
    ArchiveEntry? entry,
    List<ArchiveEntry>? roots,
    void Function(int, int)? progress,
    void Function(ExtractionProgress)? detailedProgress,
    LinkPolicy linkPolicy = LinkPolicy.keepAll,
    CaseConflictPolicy caseConflictPolicy = CaseConflictPolicy.rename,
    void Function(String)? notice,
    ExtractionConflictPolicy conflictPolicy = ExtractionConflictPolicy.rename,
    ExtractionConflictResolver? resolveConflict,
  }) async {
    extractionDocument = doc;
    extractionEntry = entry;
    extractionRoots = roots;
    return '/tmp/extracted';
  }

  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async =>
      Uint8List.fromList('hello'.codeUnits);
  @override
  Future<OpenedArchiveFile> prepareExternal(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) async {
    prepared = entry.path;
    return OpenedArchiveFile(
      doc.path,
      entry.path,
      '/tmp/edit.txt',
      '',
      '',
      FileStat.statSync('/tmp'),
    );
  }
}

class FinderDesktop extends DesktopIntegration {
  String? openedPath, application;
  @override
  bool get supportsQuickLook => true;
  @override
  Future<List<FileApplication>> applicationsForFile(String name) async => [
    const FileApplication(
      'TextEdit',
      null,
      '/Applications/TextEdit.app',
      isDefault: true,
    ),
    const FileApplication('Test Editor', null, '/Applications/TestEditor.app'),
  ];
  @override
  Future<void> openWith(String path, FileApplication app) async {
    openedPath = path;
    application = app.path;
  }
}

class NonMacDesktop extends DesktopIntegration {
  @override
  bool get supportsQuickLook => false;
}

class OpenMenuDesktop extends FinderDesktop {
  @override
  bool get supportsFileIntegration => true;
}

final document = ArchiveDocument(
  '/sample.zip',
  const [
    ArchiveEntry(path: 'docs/nested/a.txt', size: 5, directory: false),
    ArchiveEntry(path: 'docs/readme.txt', size: 5, directory: false),
    ArchiveEntry(path: 'empty/', size: 0, directory: true),
    ArchiveEntry(path: 'root.txt', size: 5, directory: false),
  ],
  'ZIP',
  true,
);

void main() {
  Future<void> mount(
    WidgetTester tester,
    FinderService service,
    DesktopIntegration desktop, [
    AppSettings? preferences,
    FinderPropertiesWindow? propertiesWindow,
  ]) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          DesktopIntegration.channel,
          (_) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DesktopIntegration.channel, null),
    );
    final settings =
        preferences ?? AppSettings(read: () async => null, write: (_) async {});
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          settings: settings,
          initialDocument: document,
          service: service,
          desktop: desktop,
          enableNativeTransfers: false,
          propertiesWindowFactory: propertiesWindow == null
              ? null
              : () => propertiesWindow,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('open-with split button uses Forui controls and opens its menu', (
    tester,
  ) async {
    final service = FinderService();
    final desktop = OpenMenuDesktop();
    await mount(tester, service, desktop);
    await tester.tap(find.byKey(const ValueKey('file-root.txt')));
    await tester.pumpAndSettle();
    final split = find.byKey(const ValueKey('selection-open-split'));
    final menuButton = find.byKey(const ValueKey('selection-open-menu'));
    expect(
      find.descendant(of: split, matching: find.byType(DesktopButton)),
      findsNWidgets(2),
    );
    expect(
      tester.getSize(split).height,
      tester.getSize(find.byKey(const ValueKey('selection-extract'))).height,
    );
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    expect(find.text('TextEdit（默认）'), findsOneWidget);
    expect(find.text('Test Editor'), findsOneWidget);
    await tester.tap(find.text('Test Editor'));
    await tester.pumpAndSettle();
    expect(desktop.application, '/Applications/TestEditor.app');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('extract actions include selected folders and multiple items', (
    tester,
  ) async {
    const picker = MethodChannel('plugins.flutter.io/file_selector');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      picker,
      (_) async => '/tmp',
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        null,
      ),
    );
    final service = FinderService();
    await mount(tester, service, FinderDesktop());
    await tester.tap(find.byKey(const ValueKey('file-docs')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.byKey(const ValueKey('file-root.txt')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('selection-extract')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解压').last);
    await tester.pumpAndSettle();
    expect(service.extractionRoots!.map((e) => e.path), ['docs', 'root.txt']);
    expect(service.extractionEntry, isNull);
    await tester.tap(find.byTooltip('预览栏'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('selection-strip')),
        matching: find.text('2 个项目'),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('file-docs')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-open')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('selection-extract')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解压').last);
    await tester.pumpAndSettle();
    expect(service.extractionRoots!.single.normalized, 'docs');
    await tester.pumpWidget(const SizedBox());
  });

  for (final compact in [false, true]) {
    testWidgets(
      'folder extraction actions respect the current path, compact=$compact',
      (tester) async {
        const picker = MethodChannel('plugins.flutter.io/file_selector');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          (_) async => '/tmp',
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            picker,
            null,
          ),
        );
        final service = FinderService();
        await mount(tester, service, NonMacDesktop());
        if (compact) {
          tester.view.physicalSize = const Size(700, 900);
          await tester.pumpAndSettle();
        }
        final extract = find.byKey(const ValueKey('selection-extract'));
        final named = find.byKey(const ValueKey('selection-extract-named'));
        expect(named, findsOneWidget);
        expect(
          find.descendant(of: extract, matching: find.text('解压全部')),
          findsOneWidget,
        );
        await tester.tap(extract);
        await tester.pumpAndSettle();
        await tester.tap(find.text('解压').last);
        await tester.pumpAndSettle();
        expect(
          service.extractionRoots!.map((e) => e.path),
          document.entries.map((e) => e.path),
        );
        await tester.ensureVisible(named);
        await tester.tap(named);
        await tester.pumpAndSettle();
        await tester.tap(find.text('解压').last);
        await tester.pumpAndSettle();
        expect(service.extractionRoots, isNull);

        final dynamic state = tester.state(find.byType(ArchiveWorkspace));
        for (final path in ['docs', 'docs/nested', 'empty']) {
          state.navigate(path);
          await tester.pumpAndSettle();
          expect(named, findsNothing);
          expect(
            find.descendant(of: extract, matching: find.text('解压')),
            findsOneWidget,
          );
          await tester.tap(extract);
          await tester.pumpAndSettle();
          await tester.tap(find.text('解压').last);
          await tester.pumpAndSettle();
          expect(service.extractionDocument, same(document));
          expect(service.extractionRoots!.single.normalized, path);
          expect(service.extractionRoots!.single.directory, isTrue);
        }

        state.navigate('docs');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('file-docs/readme.txt')));
        await tester.pumpAndSettle();
        expect(named, findsNothing);
        await tester.tap(extract);
        await tester.pumpAndSettle();
        await tester.tap(find.text('解压').last);
        await tester.pumpAndSettle();
        expect(service.extractionRoots!.single.path, 'docs/readme.txt');

        state.navigate('');
        await tester.pumpAndSettle();
        expect(named, findsOneWidget);
        expect(
          find.descendant(of: extract, matching: find.text('解压全部')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('compact sidebar and scrim stay below the toolbar', (
    tester,
  ) async {
    await mount(tester, FinderService(), FinderDesktop());
    tester.view.physicalSize = const Size(700, 900);
    await tester.pumpAndSettle();
    final toolbar = find.byKey(const ValueKey('workspace-top-bar'));
    final toolbarBounds = tester.getRect(toolbar);
    final directoryButton = find.descendant(
      of: find.byKey(const ValueKey('workspace-status-bar')),
      matching: find.byTooltip('目录'),
    );
    expect(
      find.descendant(of: toolbar, matching: find.byTooltip('目录')),
      findsNothing,
    );
    expect(
      tester.getRect(directoryButton).top,
      greaterThan(toolbarBounds.bottom),
    );
    await tester.tap(directoryButton);
    await tester.pumpAndSettle();
    final drawer = find.byType(Drawer);
    expect(tester.getRect(drawer).top, toolbarBounds.bottom);
    final scaffold = tester.state<ScaffoldState>(
      find.ancestor(of: drawer, matching: find.byType(Scaffold)).first,
    );
    expect(scaffold.isDrawerOpen, isTrue);
    await tester.tap(directoryButton);
    await tester.pumpAndSettle();
    expect(scaffold.isDrawerOpen, isFalse);
    await tester.tap(directoryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tree-docs')));
    await tester.pumpAndSettle();
    expect(scaffold.isDrawerOpen, isFalse);
    expect(find.byKey(const ValueKey('file-docs/readme.txt')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'inspector information stays above actions or can scroll fully into view',
    (tester) async {
      await mount(tester, FinderService(), FinderDesktop());
      var pointerTime = Duration.zero;
      Future<void> selectFile(String path) async {
        pointerTime += const Duration(seconds: 1);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.down(
          tester.getCenter(find.byKey(ValueKey('file-$path'))),
          timeStamp: pointerTime,
        );
        await gesture.up(
          timeStamp: pointerTime + const Duration(milliseconds: 10),
        );
      }

      Future<void> checkInformation() async {
        final scroll = find.byKey(const ValueKey('inspector-scroll'));
        final scrollable = find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first;
        final state = tester.state<ScrollableState>(scrollable);
        final viewport = tester.getRect(scroll);
        final actions = tester.getRect(
          find.byKey(const ValueKey('inspector-actions')),
        );
        expect(viewport.bottom, closeTo(actions.top, .1));
        final panel = tester.getRect(
          find.byKey(const ValueKey('inspector-panel')),
        );
        expect(actions.bottom, closeTo(panel.bottom, .1));
        if (tester.view.physicalSize.height >= 900) {
          expect(state.position.maxScrollExtent, closeTo(0, .1));
        }
        if (state.position.maxScrollExtent > 0) {
          await tester.dragFrom(
            Offset(viewport.right - 4, viewport.center.dy),
            const Offset(0, -2000),
          );
          await tester.pumpAndSettle();
        }
        final information = tester.getRect(
          find.byKey(const ValueKey('inspector-information')),
        );
        expect(information.bottom, lessThanOrEqualTo(actions.top - 15.9));
        expect(information.top, greaterThanOrEqualTo(viewport.top));
        expect(tester.takeException(), isNull);
      }

      for (final height in [500.0, 900.0, 1400.0]) {
        tester.view.physicalSize = Size(1440, height);
        await tester.pumpAndSettle();
        await checkInformation();
        await selectFile('root.txt');
        await tester.pumpAndSettle();
        await checkInformation();
        await selectFile('docs');
        await tester.pumpAndSettle();
        await checkInformation();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await selectFile('root.txt');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        await checkInformation();
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('equal row heights, inspector anchors and draggable sidebars', (
    tester,
  ) async {
    await mount(tester, FinderService(), FinderDesktop());
    final rowHeight = tester
        .getSize(find.byKey(const ValueKey('file-docs')))
        .height;
    expect(rowHeight, inInclusiveRange(28, 42));
    for (final path in ['docs', 'empty/', 'root.txt']) {
      expect(
        tester.getSize(find.byKey(ValueKey('file-$path'))).height,
        rowHeight,
      );
    }
    await tester.tap(find.byKey(const ValueKey('file-root.txt')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-strip')), findsNothing);
    final panel = tester.getRect(find.byKey(const ValueKey('inspector-panel')));
    final preview = tester.getRect(
      find.byKey(const ValueKey('inspector-preview')),
    );
    final information = tester.getRect(
      find.byKey(const ValueKey('inspector-information')),
    );
    expect(preview.top, panel.top + 16);
    expect(
      preview.height,
      closeTo((panel.height * .5).clamp(120, 360) * .75, .01),
    );
    final actions = tester.getRect(
      find.byKey(const ValueKey('inspector-actions')),
    );
    expect(information.bottom, actions.top - 16);
    final left = find.byKey(const ValueKey('sidebar-resizer'));
    final oldLeft = tester.getCenter(left).dx;
    await tester.drag(left, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(left).dx, greaterThan(oldLeft + 30));
    final right = find.byKey(const ValueKey('inspector-resizer'));
    final oldRight = tester.getCenter(right).dx;
    await tester.drag(right, const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(right).dx, lessThan(oldRight - 30));
    await tester.tap(find.byTooltip('预览栏'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-strip')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('sidebar resize hit areas extend beyond the unchanged divider', (
    tester,
  ) async {
    await mount(tester, FinderService(), FinderDesktop());
    for (final key in ['sidebar-resizer', 'inspector-resizer']) {
      final handle = find.byKey(ValueKey(key));
      final divider = find.byKey(ValueKey('$key-line'));
      final direction = key == 'sidebar-resizer' ? 1.0 : -1.0;
      expect(tester.getSize(handle).width, 13);
      expect(tester.getSize(divider).width, 1);
      expect(tester.getCenter(handle), tester.getCenter(divider));
      for (final offset in [-5.0, 5.0]) {
        final oldCenter = tester.getCenter(handle);
        await tester.dragFrom(
          oldCenter + Offset(offset, 0),
          Offset(direction * 40, 0),
        );
        await tester.pumpAndSettle();
        expect(
          (tester.getCenter(handle).dx - oldCenter.dx) * direction,
          greaterThan(10),
        );
        expect(tester.getSize(divider).width, 1);
        expect(tester.getCenter(handle), tester.getCenter(divider));
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('multiple selections show a combined Finder-style summary', (
    tester,
  ) async {
    await mount(tester, FinderService(), FinderDesktop());
    await tester.tap(find.byKey(const ValueKey('file-root.txt')));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.byKey(const ValueKey('file-empty/')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('2 个项目'), findsOneWidget);
    expect(find.text('1 个文件、1 个文件夹'), findsOneWidget);
    expect(find.text('在默认应用中打开'), findsNothing);
    BoxDecoration selectionBox(String path) =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byKey(ValueKey('file-$path')),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    final first = selectionBox('empty/').borderRadius! as BorderRadius;
    final last = selectionBox('root.txt').borderRadius! as BorderRadius;
    expect(first.topLeft, const Radius.circular(5));
    expect(first.bottomLeft, Radius.zero);
    expect(last.topLeft, Radius.zero);
    expect(last.bottomLeft, const Radius.circular(5));
    expect(
      find.byKey(const ValueKey('selection-divider-empty')),
      findsOneWidget,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    final deselect = await tester.createGesture();
    await deselect.down(
      tester.getCenter(find.byKey(const ValueKey('file-empty/'))),
      timeStamp: const Duration(seconds: 1),
    );
    await deselect.up(timeStamp: const Duration(seconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(selectionBox('root.txt').borderRadius, BorderRadius.circular(5));
    expect(find.byKey(const ValueKey('selection-divider-empty')), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.byKey(const ValueKey('file-docs')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(selectionBox('docs').borderRadius, BorderRadius.circular(5));
    expect(selectionBox('root.txt').borderRadius, BorderRadius.circular(5));

    expect(find.byKey(const ValueKey('selection-extract')), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-open')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    final singleClick = await tester.createGesture();
    await singleClick.down(
      tester.getCenter(find.byKey(const ValueKey('file-root.txt'))),
      timeStamp: const Duration(seconds: 2),
    );
    await singleClick.up(timeStamp: const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('2 个项目'), findsNothing);
    expect(
      tester
          .widget<FileItemSurface>(find.byKey(const ValueKey('file-docs')))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<FileItemSurface>(find.byKey(const ValueKey('file-root.txt')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byTooltip('预览栏'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-strip')), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-extract')), findsOneWidget);
    expect(find.byTooltip('系统预览（空格）'), findsNothing);
    expect(find.byTooltip('复制'), findsNothing);
    expect(find.byTooltip('粘贴'), findsNothing);
    expect(find.byTooltip('文件名编码'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('columns retain ancestors and single clicks reveal children', (
    tester,
  ) async {
    final settings = AppSettings(
      read: () async => null,
      write: (_) async {},
      writeHighlight: (_) async {},
    );
    await mount(tester, FinderService(), FinderDesktop(), settings);
    await tester.tap(find.byTooltip('多栏视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('file-docs')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('column-')), findsOneWidget);
    expect(find.byKey(const ValueKey('column-docs')), findsOneWidget);
    expect(
      tester
          .widget<FileItemSurface>(find.byKey(const ValueKey('file-docs')))
          .activeSelection,
      true,
    );
    await tester.tap(find.byKey(const ValueKey('file-docs/nested')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('column-docs/nested')), findsOneWidget);
    expect(
      tester
          .widget<FileItemSurface>(
            find.byKey(const ValueKey('file-docs/nested')),
          )
          .activeSelection,
      true,
    );
    expect(
      tester
          .widget<FileItemSurface>(find.byKey(const ValueKey('file-docs')))
          .activeSelection,
      false,
    );
    await tester.tap(find.byKey(const ValueKey('file-docs/nested/a.txt')));
    await tester.pumpAndSettle();
    final file = find.byKey(const ValueKey('file-docs/nested/a.txt'));
    expect(tester.widget<FileItemSurface>(file).activeSelection, true);
    expect(
      tester.widget<FileItemSurface>(file).selectionHighlight,
      SelectionHighlight.blue,
    );
    expect(
      tester
          .widget<FileItemSurface>(
            find.byKey(const ValueKey('file-docs/nested')),
          )
          .activeSelection,
      false,
    );
    await settings.setSelectionHighlight(SelectionHighlight.neutral);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FileItemSurface>(file).selectionHighlight,
      SelectionHighlight.neutral,
    );
    final box =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(of: file, matching: find.byType(DecoratedBox))
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(box.color, desktopSelectionBackground(tester.element(file)));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    final selected = tester.widget<FileItemSurface>(
      find.byKey(const ValueKey('file-docs/nested')),
    );
    expect(selected.selected, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'context menu opens with chosen app through monitored temporary file',
    (tester) async {
      final service = FinderService(), desktop = OpenMenuDesktop();
      await mount(tester, service, desktop);
      await tester.tap(
        find.byKey(const ValueKey('file-root.txt')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('快速查看'), findsOneWidget);
      await tester.tap(find.text('打开方式'));
      await tester.pumpAndSettle();
      expect(find.text('TextEdit（默认）'), findsOneWidget);
      await tester.tap(find.text('Test Editor'));
      await tester.pumpAndSettle();
      expect(service.prepared, 'root.txt');
      expect(desktop.openedPath, '/tmp/edit.txt');
      expect(desktop.application, '/Applications/TestEditor.app');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('context menu omits Quick Look outside macOS', (tester) async {
    await mount(tester, FinderService(), NonMacDesktop());
    await tester.tap(
      find.byKey(const ValueKey('file-root.txt')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('快速查看'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'desktop search expands below the toolbar without moving its controls',
    (tester) async {
      await mount(tester, FinderService(), FinderDesktop());
      final top = find.byKey(const ValueKey('workspace-top-bar'));
      final views = find.byKey(const ValueKey('view-mode-selector'));
      final path = find.byKey(const ValueKey('path-navigation'));
      final topRect = tester.getRect(top);
      final viewsRect = tester.getRect(views);
      final pathRect = tester.getRect(path);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      final searchBar = find.byKey(const ValueKey('workspace-search-bar'));
      expect(tester.getRect(top), topRect);
      expect(tester.getRect(views), viewsRect);
      expect(tester.getRect(path), pathRect);
      expect(tester.getRect(searchBar).top, closeTo(topRect.bottom, .01));
      expect(
        find.descendant(
          of: top,
          matching: find.byKey(const ValueKey('archive-search')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: searchBar,
          matching: find.byKey(const ValueKey('archive-search')),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('关闭搜索'));
      await tester.pumpAndSettle();
      expect(searchBar, findsNothing);
      expect(tester.getRect(views), viewsRect);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'all inspector modes use the gallery background including actions',
    (tester) async {
      await mount(tester, FinderService(), FinderDesktop());
      final dynamic state = tester.state(find.byType(ArchiveWorkspace));
      Color panelColor() =>
          (tester
                      .widget<Container>(
                        find.byKey(const ValueKey('inspector-panel')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      state.changeView('gallery');
      await tester.pumpAndSettle();
      final galleryColor = panelColor();
      for (final view in ['list', 'grid', 'columns']) {
        state.changeView(view);
        await tester.pumpAndSettle();
        expect(panelColor(), galleryColor);
        final actions = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('inspector-actions')),
        );
        expect((actions.decoration as BoxDecoration).color, galleryColor);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [1440.0, 360.0]) {
    testWidgets(
      'right-click properties follow the window layout at width $width',
      (tester) async {
        final window = FinderPropertiesWindow();
        await mount(tester, FinderService(), FinderDesktop(), null, window);
        tester.view.physicalSize = Size(width, 640);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('file-root.txt')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('属性'));
        await tester.tap(find.text('属性'));
        await tester.pumpAndSettle();
        final Map<String, dynamic> data;
        if (width < 800) {
          expect(window.data, isNull);
          final dialog = find.byKey(const ValueKey('inline-properties-dialog'));
          expect(dialog, findsOneWidget);
          expect(
            tester.getSize(
              find.byKey(const ValueKey('auxiliary-fullscreen-dialog')),
            ),
            Size(width, 640),
          );
          data = tester
              .widget<ArchiveWorkspace>(
                find.descendant(
                  of: dialog,
                  matching: find.byType(ArchiveWorkspace),
                ),
              )
              .propertiesData!;
        } else {
          data = window.data!;
          expect(
            find.byKey(const ValueKey('inline-properties-dialog')),
            findsNothing,
          );
        }
        expect(data['selectionCount'], 1);
        expect((data['selection'] as List).single['path'], 'root.txt');
        expect(find.byType(Dialog), findsNothing);
        expect(find.byKey(const ValueKey('properties-dialog')), findsNothing);
        if (width < 800) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('file-docs')));
        await tester.pumpAndSettle();
        final dynamic workspace = tester.state(find.byType(ArchiveWorkspace));
        expect(workspace.selected.name, 'docs');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'archive root properties send archive metadata to the independent window',
    (tester) async {
      final window = FinderPropertiesWindow();
      await mount(tester, FinderService(), FinderDesktop(), null, window);
      await tester.tap(
        find.byKey(const ValueKey('tree-')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('属性'));
      await tester.pumpAndSettle();
      expect(window.data!['selectionCount'], 0);
      expect(window.data!['path'], '/sample.zip');
      expect(window.data!['comment'], '');
      expect(window.data!['itemCount'], document.entries.length);
      expect(window.data!['size'], document.index.totalSize);
      expect(find.byType(Dialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('path and search stay in top bar across window sizes', (
    tester,
  ) async {
    await mount(tester, FinderService(), FinderDesktop());
    final top = find.byKey(const ValueKey('workspace-top-bar'));
    final path = find.byKey(const ValueKey('path-navigation'));
    final search = find.byKey(const ValueKey('archive-search'));
    void checkBar() {
      expect(find.descendant(of: top, matching: path), findsOneWidget);
      expect(tester.getSize(top).height, 49);
      expect(search, findsNothing);
      expect(
        find.descendant(of: top, matching: find.byTooltip('搜索')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }

    checkBar();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('tree-docs')),
        matching: find.text('docs'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: path, matching: find.text('docs')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: path, matching: find.text('sample.zip')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: path, matching: find.text('docs')),
      findsNothing,
    );
    for (final width in [800.0, 360.0]) {
      tester.view.physicalSize = Size(width, 640);
      await tester.pumpAndSettle();
      checkBar();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'path navigation reveals the right end after folder and tab jumps',
    (tester) async {
      await mount(tester, FinderService(), FinderDesktop());
      tester.view.physicalSize = const Size(800, 640);
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ArchiveWorkspace));
      final path = find.byKey(const ValueKey('path-navigation'));
      ScrollController controller() => tester
          .widget<SingleChildScrollView>(
            find.descendant(
              of: path,
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .controller!;
      void expectCurrentEnd() {
        final scroll = controller();
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, .01));
      }

      const deep =
          'first-long-folder-name/second-long-folder-name/third-long-folder-name/current-folder';
      state.navigate(deep);
      await tester.pumpAndSettle();
      expectCurrentEnd();
      final visible = tester.getRect(path);
      final current = tester.getRect(
        find.descendant(of: path, matching: find.text('current-folder')),
      );
      expect(current.right, lessThanOrEqualTo(visible.right + .01));
      expect(current.left, greaterThanOrEqualTo(visible.left));
      controller().jumpTo(0);
      await tester.pumpAndSettle();
      expect(controller().offset, 0);
      state.navigate('$deep/next-folder');
      await tester.pumpAndSettle();
      expectCurrentEnd();
      state.goBack();
      await tester.pumpAndSettle();
      expectCurrentEnd();
      controller().jumpTo(0);
      final tab = state.tabs.first;
      state.activateTab(tab);
      await tester.pumpAndSettle();
      expectCurrentEnd();
      state.navigate('');
      await tester.pumpAndSettle();
      expect(controller().offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('compact search button expands and retains the query on close', (
    tester,
  ) async {
    await mount(tester, FinderService(), FinderDesktop());
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('archive-search')), findsNothing);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    // Search runs in an isolate; its busy indicator can keep animating.
    await tester.enterText(find.byType(EditableText), 'root');
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('archive-search')), findsNothing);
    expect(find.byTooltip('搜索'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'root',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('archive-search')), findsNothing);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('archive-search')), findsNothing);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('archive-search')), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'root',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow windows retain compact actions without overflow', (
    tester,
  ) async {
    await mount(tester, FinderService(), FinderDesktop());
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('file-root.txt')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inspector-panel')), findsNothing);
    expect(find.byKey(const ValueKey('selection-strip')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('English compact actions scroll and remain clickable', (
    tester,
  ) async {
    var destinationRequests = 0;
    const picker = MethodChannel('plugins.flutter.io/file_selector');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
      _,
    ) async {
      destinationRequests++;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        null,
      ),
    );
    final settings = AppSettings(read: () async => null, write: (_) async {});
    settings.synchronizeLanguage(AppLanguage.english.name);
    await mount(tester, FinderService(), OpenMenuDesktop(), settings);
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final statusBar = find.byKey(const ValueKey('workspace-status-bar'));
    final statusBounds = tester.getRect(statusBar);
    final strip = find.byKey(const ValueKey('selection-strip'));
    expect(tester.getSize(strip).height, 40);
    final actions = find.byKey(const ValueKey('selection-actions-scroll'));
    final namedExtract = find.byKey(const ValueKey('selection-extract-named'));
    await tester.drag(actions, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(namedExtract.hitTestable(), findsOneWidget);
    await tester.tap(namedExtract);
    await tester.pumpAndSettle();
    expect(destinationRequests, 1);
    expect(tester.getRect(statusBar), statusBounds);

    await tester.tap(find.byKey(const ValueKey('file-root.txt')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(actions, const Offset(600, 0));
    await tester.pumpAndSettle();
    final openMenu = find.byKey(const ValueKey('selection-open-menu'));
    await tester.ensureVisible(openMenu);
    await tester.pumpAndSettle();
    expect(openMenu.hitTestable(), findsOneWidget);
    await tester.tap(openMenu);
    await tester.pumpAndSettle();
    expect(find.text('Test Editor'), findsOneWidget);
    expect(tester.getSize(strip).height, 40);
    expect(tester.getRect(statusBar), statusBounds);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
