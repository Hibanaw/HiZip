import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/app_localizations.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/file_item_surface.dart';

class LargeDirectoryService extends ArchiveService {
  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async =>
      Uint8List(0);
}

void main() {
  final document = ArchiveDocument(
    '/large.zip',
    [
      for (var index = 0; index < 2505; index++)
        ArchiveEntry(
          path: 'big/${index.toString().padLeft(5, '0')}.txt',
          size: 0,
          directory: false,
        ),
      const ArchiveEntry(path: 'other/last.txt', size: 0, directory: false),
    ],
    'ZIP',
    true,
  );

  Future<void> doubleClick(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester, String view) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(
      read: () async => null,
      write: (_) async {},
      writeBrowsing: (_) async {},
    );
    await settings.setBrowsing(
      BrowsingPreferences(view: view, inspector: false),
    );
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          settings: settings,
          initialDocument: document,
          service: LargeDirectoryService(),
          enableNativeTransfers: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await doubleClick(tester, find.byKey(const ValueKey('file-big')));
  }

  Finder listingWithCount(int count) => find.byWidgetPredicate(
    (widget) =>
        widget is BoxScrollView &&
        ((widget is ListView
                    ? widget.childrenDelegate
                    : (widget as GridView).childrenDelegate)
                .estimatedChildCount ==
            count),
  );

  for (final view in ['list', 'grid', 'columns', 'gallery']) {
    testWidgets('$view folds large folders and only builds viewport items', (
      tester,
    ) async {
      await mount(tester, view);
      final collapsed = listingWithCount(1001);
      expect(collapsed, findsOneWidget);
      final scrollView = tester.widget<BoxScrollView>(collapsed);
      expect(scrollView.cacheExtent, 0);
      expect(find.byType(FileItemSurface).evaluate().length, lessThan(80));
      expect(find.byKey(const ValueKey('file-big/01000.txt')), findsNothing);
      scrollView.controller!.jumpTo(
        scrollView.controller!.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      final expansion = find.byKey(const ValueKey('expand-remaining-big'));
      expect(expansion, findsOneWidget);
      expect(find.text('双击展开剩余 1505 项'), findsOneWidget);
      await tester.tap(expansion);
      await tester.pump(const Duration(milliseconds: 50));
      expect(listingWithCount(1001), findsOneWidget);
      await tester.tap(expansion);
      await tester.pumpAndSettle();
      expect(expansion, findsNothing);
      final expanded = listingWithCount(2505);
      expect(expanded, findsOneWidget);
      expect(find.byType(FileItemSurface).evaluate().length, lessThan(80));
      final expandedScroll = tester.widget<BoxScrollView>(expanded).controller!;
      expandedScroll.jumpTo(expandedScroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('file-big/02504.txt')), findsOneWidget);
      expect(find.byKey(const ValueKey('file-big/00000.txt')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('select all includes folded files', (tester) async {
    await mount(tester, 'list');
    await tester.tap(find.byKey(const ValueKey('file-big/00000.txt')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('2505 个项目'), findsOneWidget);
    expect(listingWithCount(1001), findsOneWidget);
  });

  testWidgets('expansion is retained when leaving and returning to a folder', (
    tester,
  ) async {
    await mount(tester, 'list');
    final controller = tester
        .widget<BoxScrollView>(listingWithCount(1001))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await doubleClick(
      tester,
      find.byKey(const ValueKey('expand-remaining-big')),
    );
    expect(listingWithCount(2505), findsOneWidget);
    await tester.tap(find.text('other').first);
    await tester.pumpAndSettle();
    expect(listingWithCount(2505), findsNothing);
    await tester.tap(find.text('big').first);
    await tester.pumpAndSettle();
    expect(listingWithCount(2505), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('expansion instruction is localized', () {
    expect(
      translateAppText('双击展开剩余 1505 项', 'en'),
      'Double-click to show 1505 remaining items',
    );
  });
}
