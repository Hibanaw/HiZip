import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/file_item_surface.dart';
import 'package:hizip/ui/file_selection_area.dart';

class _Service extends ArchiveService {
  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'writableFormats': ['zip'],
  };
  @override
  Future<Uint8List> preview(
    ArchiveDocument document,
    ArchiveEntry entry,
  ) async => Uint8List(0);
}

class _Desktop extends DesktopIntegration {
  @override
  bool get supportsQuickLook => false;
  @override
  bool get supportsMenuBar => false;
}

void main() {
  Future<void> mount(WidgetTester tester, String view, {int count = 3}) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(writeBrowsing: (_) async {});
    await settings.setBrowsing(
      BrowsingPreferences(view: view, inspector: false),
    );
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          settings: settings,
          service: _Service(),
          desktop: _Desktop(),
          enableNativeTransfers: false,
          initialDocument: ArchiveDocument(
            '/test.zip',
            [
              for (var i = 0; i < count; i++)
                ArchiveEntry(
                  path: '${i.toString().padLeft(3, '0')}.bin',
                  size: 123,
                  directory: false,
                ),
            ],
            'ZIP',
            true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder file(int index) =>
      find.byKey(ValueKey('file-${index.toString().padLeft(3, '0')}.bin'));
  Set<String> selected(WidgetTester tester) => {
    for (final element in find.byType(FileItemSurface).evaluate())
      if ((element.widget as FileItemSurface).selected)
        (element.widget as FileItemSurface).name,
  };
  final marquee = find.byKey(const ValueKey('file-selection-marquee'));

  Finder gridIcon(int index) => find.byKey(
    ValueKey('grid-icon-background-${index.toString().padLeft(3, '0')}.bin'),
  );
  Finder gridName(int index) => find.byKey(
    ValueKey('grid-name-background-${index.toString().padLeft(3, '0')}.bin'),
  );

  testWidgets(
    'grid clicks use only the icon and filename without moving them',
    (tester) async {
      await mount(tester, 'grid');
      final tile = tester.getRect(file(0));
      final icon = tester.getRect(gridIcon(0));
      final name = tester.getRect(gridName(0));
      final blankPoints = [
        tile.topLeft + const Offset(1, 1),
        Offset(tile.left + 1, icon.center.dy),
        Offset(icon.center.dx, icon.bottom + 2),
        Offset(name.center.dx, name.bottom + 1),
      ];
      var clickTime = 0;
      Future<void> click(Offset point) async {
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        final timestamp = Duration(seconds: ++clickTime);
        await gesture.down(point, timeStamp: timestamp);
        await gesture.up(
          timeStamp: timestamp + const Duration(milliseconds: 10),
        );
      }

      for (final point in blankPoints) {
        expect(tile.contains(point), isTrue);
        expect(icon.contains(point) || name.contains(point), isFalse);
        // The gray background's padding is part of the icon's hit region.
        await click(icon.topLeft + const Offset(1, 1));
        await tester.pumpAndSettle();
        expect(selected(tester), {'000.bin'});
        expect(tester.getRect(file(0)), tile);
        expect(tester.getRect(gridIcon(0)), icon);
        expect(tester.getRect(gridName(0)), name);
        await click(point);
        await tester.pumpAndSettle();
        expect(selected(tester), isEmpty);
      }
      await click(name.topLeft + const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(selected(tester), {'000.bin'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('grid right-clicks on cell padding open the blank-space menu', (
    tester,
  ) async {
    await mount(tester, 'grid');
    final tile = tester.getRect(file(0));
    await tester.tapAt(
      tile.topLeft + const Offset(1, 1),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('解压全部…'), findsOneWidget);
    expect(find.text('重命名…'), findsNothing);
    expect(selected(tester), isEmpty);
    await tester.tapAt(tile.topLeft + const Offset(1, 1));
    await tester.pumpAndSettle();
    await tester.tap(gridName(0), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('解压全部…'), findsNothing);
    expect(find.text('重命名…'), findsOneWidget);
    expect(selected(tester), {'000.bin'});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'grid cell padding starts a marquee and only visible regions intersect',
    (tester) async {
      await mount(tester, 'grid');
      final tile = tester.getRect(file(0));
      final icon = tester.getRect(gridIcon(0));
      final name = tester.getRect(gridName(0));
      final second = tester.getRect(gridIcon(1));
      final gesture = await tester.startGesture(
        Offset(tile.left + 1, icon.top + 1),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(Offset(icon.left - 1, icon.bottom - 1));
      await tester.pump();
      expect(marquee, findsOneWidget);
      expect(
        selected(tester),
        isEmpty,
        reason: 'tile=$tile icon=$icon name=$name',
      );
      await gesture.moveTo(second.bottomRight - const Offset(1, 1));
      await tester.pump();
      expect(selected(tester), {'000.bin', '001.bin'});
      await gesture.up();
      await tester.pumpAndSettle();
      expect(marquee, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final view in ['list', 'grid', 'columns', 'gallery']) {
    testWidgets('$view selects intersecting files from empty space', (
      tester,
    ) async {
      await mount(tester, view);
      final area = tester.getRect(find.byType(FileSelectionArea).first);
      final first = tester.getRect(file(0));
      final second = tester.getRect(file(1));
      final third = tester.getRect(file(2));
      final origin = view == 'grid'
          ? first.topLeft + const Offset(30, -2)
          : view == 'gallery'
          ? Offset(third.right + 30, area.bottom - 2)
          : Offset(area.left + 30, third.bottom + 40);
      final end = view == 'grid'
          ? second.bottomRight - const Offset(1, 1)
          : Offset(second.left + 90, second.top + 2);
      final gesture = await tester.startGesture(
        origin,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(end);
      await tester.pump();
      expect(marquee, findsOneWidget);
      expect(
        selected(tester),
        view == 'grid' ? {'000.bin', '001.bin'} : {'001.bin', '002.bin'},
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(marquee, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final modifier in [
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.shiftLeft,
  ]) {
    testWidgets('$modifier adds to the selection and shrinks the box live', (
      tester,
    ) async {
      await mount(tester, 'list');
      await tester.tap(file(0));
      await tester.pumpAndSettle();
      final second = tester.getRect(file(1));
      final third = tester.getRect(file(2));
      await tester.sendKeyDownEvent(modifier);
      final gesture = await tester.startGesture(
        third.bottomLeft + const Offset(30, 40),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(second.topLeft + const Offset(120, 2));
      await tester.pump();
      expect(selected(tester), {'000.bin', '001.bin', '002.bin'});
      await gesture.moveTo(third.topLeft + const Offset(120, 2));
      await tester.pump();
      expect(selected(tester), {'000.bin', '002.bin'});
      await gesture.up();
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      // A subsequent empty-space click still clears the selection.
      await tester.tapAt(third.bottomLeft + const Offset(30, 50));
      await tester.pumpAndSettle();
      expect(selected(tester), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('file drags and header resizing never start a marquee', (
    tester,
  ) async {
    await mount(tester, 'list');
    await tester.drag(
      file(0),
      const Offset(100, 80),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(marquee, findsNothing);
    expect(selected(tester), {'000.bin'});
    await tester.drag(
      find.byKey(const ValueKey('list-column-resizer-name')),
      const Offset(40, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(marquee, findsNothing);
    expect(selected(tester), {'000.bin'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Escape cancels the box and restores the original selection', (
    tester,
  ) async {
    await mount(tester, 'list');
    await tester.tap(file(0));
    await tester.pumpAndSettle();
    final second = tester.getRect(file(1));
    final third = tester.getRect(file(2));
    final gesture = await tester.startGesture(
      third.bottomLeft + const Offset(30, 40),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(second.topLeft + const Offset(120, 2));
    await tester.pump();
    expect(selected(tester), {'001.bin', '002.bin'});
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(marquee, findsNothing);
    expect(selected(tester), {'000.bin'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'edge dragging scrolls and retains files that leave the viewport',
    (tester) async {
      await mount(tester, 'list', count: 100);
      final areaFinder = find.byType(FileSelectionArea);
      final area = tester.getRect(areaFinder);
      final widget = tester.widget<FileSelectionArea>(areaFinder);
      final gesture = await tester.startGesture(
        area.topLeft + const Offset(30, 2),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(area.bottomRight - const Offset(30, 2));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(widget.scrollController.offset, greaterThan(100));
      final state = tester.state(find.byType(ArchiveWorkspace)) as dynamic;
      expect(state.selectedPaths, contains('000.bin'));
      expect((state.selectedPaths as Set<String>).length, greaterThan(25));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(marquee, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('scrollbar thumb dragging does not start a marquee', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var starts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: FileSelectionArea(
                scrollController: scroll,
                selectedPaths: const {},
                onStart: () => starts++,
                onChanged: (_) {},
                onEnd: () {},
                child: Scrollbar(
                  controller: scroll,
                  thumbVisibility: true,
                  interactive: true,
                  thickness: 12,
                  child: ListView.builder(
                    controller: scroll,
                    itemExtent: 30,
                    itemCount: 100,
                    itemBuilder: (_, i) => Text('File $i'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final area = tester.getRect(find.byType(FileSelectionArea));
    final gesture = await tester.startGesture(
      Offset(area.right - 6, area.top + 15),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(starts, 0);
    expect(marquee, findsNothing);
    expect(scroll.offset, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
