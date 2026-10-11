import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/models/application_menu.dart';
import 'package:hizip/models/app_language.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/services/task_windows.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';

class MenuService extends ArchiveService {
  List<ArchiveEntry>? transferred;
  String? destination;
  bool? moved;
  String? opened;
  int verifications = 0;
  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'writableFormats': ['zip', '7z', 'tar'],
  };
  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async =>
      Uint8List.fromList('sample'.codeUnits);
  @override
  Future<ArchiveDocument> transferEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
    String folder, {
    bool move = false,
  }) async {
    transferred = entries;
    destination = folder;
    moved = move;
    return doc;
  }

  @override
  Future<OpenedArchiveFile> prepareExternal(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) async {
    opened = entry.path;
    return OpenedArchiveFile(
      doc.path,
      entry.path,
      '/tmp/menu-sample.txt',
      '',
      '',
      FileStat.statSync('/tmp'),
    );
  }

  @override
  Future<Map<String, dynamic>> verify(ArchiveDocument doc) async {
    verifications++;
    return {'files': 3, 'bytes': 18};
  }
}

class MenuDesktop extends DesktopIntegration {
  MenuDesktop({this.native = false});
  final bool native;
  String? openedApp;
  @override
  bool get supportsMenuBar => native;
  @override
  bool get supportsQuickLook => true;
  @override
  bool get supportsFileIntegration => true;
  @override
  Future<List<FileApplication>> applicationsForFile(String name) async =>
      const [
        FileApplication(
          'TextEdit',
          null,
          '/Applications/TextEdit.app',
          isDefault: true,
        ),
        FileApplication('Other Editor', null, '/Applications/Other.app'),
      ];
  @override
  Future<void> openWith(String path, FileApplication app) async =>
      openedApp = app.path;
}

class MenuProperties extends PropertiesWindowTransport {
  final snapshots = <Map<String, dynamic>>[];
  @override
  Future<bool> show(
    Map<String, dynamic> data,
    PropertiesWindowAction action,
  ) async {
    snapshots.add(data);
    return true;
  }

  @override
  void dispose() {}
}

ArchiveDocument fixture({bool writable = true}) => ArchiveDocument(
  '/menu.zip',
  const [
    ArchiveEntry(path: 'one.txt', size: 6, directory: false),
    ArchiveEntry(path: 'two.txt', size: 6, directory: false),
    ArchiveEntry(path: 'docs/nested/three.txt', size: 6, directory: false),
    ArchiveEntry(
      path: 'locked.txt',
      size: 6,
      directory: false,
      encrypted: true,
    ),
  ],
  'ZIP',
  writable,
  comment: 'Archive comment',
);

void main() {
  late List<MethodCall> nativeCalls;
  setUp(() {
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopIntegration.channel, (call) async {
          nativeCalls.add(call);
          if (call.method == 'configureMenus') return <String>[];
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DesktopIntegration.channel, null);
  });

  Future<void> mount(
    WidgetTester tester, {
    bool native = false,
    bool writable = true,
    MenuService? service,
    MenuDesktop? desktop,
    MenuProperties? properties,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(
      read: () async => null,
      write: (_) async {},
      writeBrowsing: (_) async {},
    );
    await settings.setLanguage(AppLanguage.simplifiedChinese);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          initialDocument: fixture(writable: writable),
          settings: settings,
          service: service ?? MenuService(),
          desktop: desktop ?? MenuDesktop(native: native),
          enableNativeTransfers: false,
          propertiesWindowFactory: properties == null ? null : () => properties,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  dynamic state(WidgetTester tester) =>
      tester.state(find.byType(ArchiveWorkspace));
  ApplicationMenuItem command(WidgetTester tester, String id) =>
      state(tester).menuCommandItem(id) as ApplicationMenuItem;

  Future<void> select(WidgetTester tester, String path) async {
    await tester.tap(find.byKey(ValueKey('file-$path')));
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String group, String title) async {
    await tester.tap(find.byTooltip('应用菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(group).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(title).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'native menu covers context actions and excludes template features',
    (tester) async {
      await mount(tester, native: true);
      await select(tester, 'one.txt');
      final data =
          nativeCalls.lastWhere((call) => call.method == 'menuState').arguments
              as Map;
      final ids = <String>{};
      void collect(List<dynamic> items) {
        for (final item in items.cast<Map>()) {
          if (item['command'] != null) ids.add(item['command'] as String);
          if (item['children'] != null) collect(item['children'] as List);
        }
      }

      collect(data['menus'] as List);
      expect(ids, isNot(contains('editText')));
      expect(
        ids,
        containsAll([
          'openArchive',
          'openSelection',
          'openWith:/Applications/TextEdit.app',
          'chooseApplication',
          'quickLook',
          'copy',
          'paste',
          'extractSelection',
          'extract',
          'extractNamed',
          'newFolder',
          'newDocument',
          'rename',
          'delete',
          'properties',
          'archiveProperties',
          'search',
          'moveTo',
          'copyTo',
          'create',
          'quickZip',
          'sort:size',
          'ascending',
          'tasks',
        ]),
      );
      expect(ids, isNot(contains('comment')));
      expect(ids.any((id) => id.startsWith('create:')), isFalse);
      expect(ids.any((id) => id.startsWith('createEmpty')), isFalse);
      final xib = File('macos/Runner/Base.lproj/MainMenu.xib')
          .readAsStringSync();
      for (final title in [
        'Spelling and Grammar',
        'Substitutions',
        'Speech',
        'Transformations',
        'Paste and Match Style',
        'Help',
      ]) {
        expect(xib, isNot(contains('title="$title"')));
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'left-click menu opens selected and archive properties independently',
    (tester) async {
      final properties = MenuProperties();
      await mount(tester, properties: properties);
      await select(tester, 'one.txt');
      await menu(tester, '文件', '属性');
      expect(properties.snapshots.single['selectionCount'], 1);
      await menu(tester, '文件', '压缩包属性');
      expect(properties.snapshots.last['selectionCount'], 0);
      expect(properties.snapshots.last['folder'], '');
      expect(properties.snapshots.last['comment'], 'Archive comment');
      expect(state(tester).selected.path, 'one.txt');
      expect(find.byType(Dialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('menu opens a discovered application and verifies the archive', (
    tester,
  ) async {
    final service = MenuService(), desktop = MenuDesktop();
    await mount(tester, service: service, desktop: desktop);
    await select(tester, 'one.txt');
    await tester.tap(find.byTooltip('应用菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('打开方式').last);
    await tester.tap(find.text('打开方式').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other Editor'));
    await tester.pumpAndSettle();
    expect(service.opened, 'one.txt');
    expect(desktop.openedApp, '/Applications/Other.app');
    await menu(tester, '文件', '校验压缩包');
    expect(service.verifications, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('search, view and sort menu commands update the workspace', (
    tester,
  ) async {
    await mount(tester);
    await menu(tester, '编辑', '搜索');
    expect(find.byKey(const ValueKey('workspace-search-bar')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await menu(tester, '显示', '图标视图');
    expect(command(tester, 'grid').checked, isTrue);
    expect(command(tester, 'list').checked, isFalse);
    await tester.tap(find.byTooltip('应用菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('排序方式'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(FItem), matching: find.text('大小')).last,
    );
    await tester.pumpAndSettle();
    expect(command(tester, 'sort:size').checked, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  for (final move in [true, false]) {
    testWidgets(
      'menu ${move ? 'moves' : 'copies'} files to an archive folder',
      (tester) async {
        final service = MenuService();
        await mount(tester, service: service);
        await select(tester, 'one.txt');
        await menu(tester, '编辑', move ? '移动到…' : '复制到…');
        await tester.tap(find.byKey(const ValueKey('transfer-folder-docs')));
        await tester.pumpAndSettle();
        expect(service.transferred!.single.path, 'one.txt');
        expect(service.destination, 'docs');
        expect(service.moved, move);
        expect(state(tester).folder, 'docs');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('selection and archive state gate native and in-app commands', (
    tester,
  ) async {
    await mount(tester);
    expect(command(tester, 'rename').enabled, isFalse);
    expect(command(tester, 'extractSelection').enabled, isFalse);
    await select(tester, 'one.txt');
    expect(command(tester, 'rename').enabled, isTrue);
    state(tester).selectAllFiles();
    await tester.pumpAndSettle();
    expect(command(tester, 'rename').enabled, isFalse);
    expect(command(tester, 'openSelection').enabled, isTrue);
    await select(tester, 'locked.txt');
    expect(command(tester, 'openSelection').enabled, isFalse);
    expect(command(tester, 'quickLook').enabled, isFalse);
    state(tester).setState(() => state(tester).busy = true);
    await tester.pumpAndSettle();
    expect(command(tester, 'properties').enabled, isFalse);
    expect(command(tester, 'create').enabled, isFalse);
    expect(command(tester, 'quickZip').enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, writable: false);
    await select(tester, 'one.txt');
    for (final id in [
      'rename',
      'delete',
      'paste',
      'newFolder',
      'newDocument',
      'addFiles',
      'moveTo',
    ]) {
      expect(command(tester, id).enabled, isFalse, reason: id);
    }
    expect(command(tester, 'properties').enabled, isTrue);
    expect(command(tester, 'extractSelection').enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('menu select all edits text without changing archive selection', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 'one.txt');
    await menu(tester, '编辑', '搜索');
    final input = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('archive-search')),
        matching: find.byType(EditableText),
      ),
    );
    input.controller.text = 'one';
    input.controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    state(tester).handleMenuCommand('selectAll');
    await tester.pump();
    expect(input.controller.selection.baseOffset, 0);
    expect(
      input.controller.selection.extentOffset,
      input.controller.text.length,
    );
    expect(state(tester).selectedPaths, {'one.txt'});
    await tester.pumpWidget(const SizedBox());
  });
}
