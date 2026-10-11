import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/file_item_surface.dart';

class RenameService extends ArchiveService {
  int opens = 0, renames = 0;
  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'writableFormats': ['zip'],
    'zipAES256': false,
  };
  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async =>
      Uint8List.fromList('content'.codeUnits);
  @override
  Future<OpenedArchiveFile> open(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) async {
    opens++;
    return OpenedArchiveFile(
      doc.path,
      entry.path,
      '/tmp/${entry.name}',
      '',
      '',
      FileStat.statSync('/tmp'),
    );
  }

  @override
  Future<ArchiveDocument> renameEntry(
    ArchiveDocument doc,
    ArchiveEntry entry,
    String name,
  ) async {
    renames++;
    if (name == 'taken.txt') throw StateError('目标名称已存在。');
    return ArchiveDocument(
      doc.path,
      [
        for (final item in doc.entries)
          ArchiveEntry(
            path: item.path == entry.path ? name : item.path,
            size: item.size,
            directory: item.directory,
          ),
      ],
      doc.format,
      doc.writable,
    );
  }
}

class RenameDesktop extends DesktopIntegration {
  @override
  bool get supportsQuickLook => false;
  @override
  bool get supportsMenuBar => false;
  @override
  Future<DefaultApplication?> defaultApplication(String name) async => null;
}

void main() {
  Future<RenameService> mount(
    WidgetTester tester, {
    String view = 'list',
    double width = 1200,
    bool writable = true,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(writeBrowsing: (_) async {});
    await settings.setBrowsing(
      BrowsingPreferences(view: view, inspector: false),
    );
    addTearDown(settings.dispose);
    final service = RenameService();
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          settings: settings,
          desktop: RenameDesktop(),
          service: service,
          enableNativeTransfers: false,
          initialDocument: ArchiveDocument(
            '/sample.zip',
            const [
              ArchiveEntry(path: 'note.txt', size: 7, directory: false),
              ArchiveEntry(path: 'taken.txt', size: 7, directory: false),
              ArchiveEntry(path: 'folder.name', size: 0, directory: true),
            ],
            'ZIP',
            writable,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('file-note.txt')));
    await tester.pumpAndSettle();
    return service;
  }

  for (final view in ['list', 'grid', 'columns', 'gallery']) {
    testWidgets(
      'mac Return renames in place in $view and preserves failed input',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final service = await mount(tester, view: view);
        final item = tester.getRect(
          find.byKey(const ValueKey('file-note.txt')),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('rename-entry-name'));
        expect(field, findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(FDialog), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('file-note.txt')),
            matching: field,
          ),
          findsOneWidget,
        );
        expect(item.contains(tester.getCenter(field)), true);
        final input = tester.widget<TextField>(
          find.descendant(of: field, matching: find.byType(TextField)),
        );
        expect(
          input.controller!.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4),
        );
        expect(service.opens, 0);
        await tester.enterText(field, 'taken.txt');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(field, findsOneWidget);
        expect(input.controller!.text, 'taken.txt');
        expect(service.renames, 1);
        await tester.enterText(field, 'changed.txt');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(field, findsNothing);
        expect(find.byKey(const ValueKey('file-changed.txt')), findsOneWidget);
        expect(service.opens, 0);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  testWidgets(
    'mac Command Down and Command O open selection; Escape cancels rename',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final service = await mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('rename-entry-name')),
        'discard.txt',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(service.renames, 0);
      expect(find.byKey(const ValueKey('rename-entry-name')), findsNothing);
      for (final key in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.keyO,
      ]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
      }
      expect(service.opens, 2);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets(
    'non-mac Enter opens and F2 renames; compact mode uses a fullscreen dialog',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final service = await mount(tester, width: 440);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(service.opens, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('auxiliary-fullscreen-dialog')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('rename-entry-name')),
        'compact.txt',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('auxiliary-fullscreen-dialog')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('file-compact.txt')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  for (final view in ['list', 'grid', 'columns', 'gallery']) {
    testWidgets('clicking another file cancels inline rename in $view', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final service = await mount(tester, view: view);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('rename-entry-name')),
        'outside.txt',
      );
      await tester.tap(find.byKey(const ValueKey('file-taken.txt')));
      await tester.pumpAndSettle();
      expect(service.renames, 0);
      expect(service.opens, 0);
      expect(find.byKey(const ValueKey('rename-entry-name')), findsNothing);
      expect(find.byKey(const ValueKey('file-note.txt')), findsOneWidget);
      expect(find.byKey(const ValueKey('file-outside.txt')), findsNothing);
      expect(
        tester
            .widget<FileItemSurface>(
              find.byKey(const ValueKey('file-taken.txt')),
            )
            .selected,
        true,
      );
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets('clicking empty space cancels rename without saving', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rename-entry-name')),
      'discard.txt',
    );
    final file = tester.getRect(find.byKey(const ValueKey('file-taken.txt')));
    await tester.tapAt(file.bottomLeft + const Offset(30, 80));
    await tester.pumpAndSettle();
    expect(service.renames, 0);
    expect(find.byKey(const ValueKey('rename-entry-name')), findsNothing);
    expect(find.byKey(const ValueKey('file-note.txt')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('toolbar click cancels rename and focuses the search field', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('rename-entry-name')),
      'discard.txt',
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(service.renames, 0);
    expect(find.byKey(const ValueKey('rename-entry-name')), findsNothing);
    expect(find.byKey(const ValueKey('archive-search')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byType(TextField))
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
    'right-click Rename edits the existing filename without a dialog',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await mount(tester);
      await tester.tap(
        find.byKey(const ValueKey('file-note.txt')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名…'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rename-entry-name')), findsOneWidget);
      expect(find.byType(FDialog), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('folder rename selects its complete name including dots', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('file-folder.name')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('rename-entry-name'));
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: field, matching: find.byType(TextField)),
          )
          .controller!
          .selection,
      const TextSelection(baseOffset: 0, extentOffset: 11),
    );
    await tester.enterText(field, 'new-folder');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('file-new-folder')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('read-only archives do not enter rename mode on mac Return', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final service = await mount(tester, writable: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rename-entry-name')), findsNothing);
    expect(service.opens, 0);
    expect(service.renames, 0);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
