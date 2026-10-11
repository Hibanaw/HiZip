import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/app_localizations.dart';
import 'package:hizip/ui/desktop_widgets.dart';

class _Service extends ArchiveService {
  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'writableFormats': ['zip'],
  };
}

class _Desktop extends DesktopIntegration {
  @override
  bool get supportsQuickLook => false;
  @override
  bool get supportsMenuBar => false;
}

void main() {
  Future<AppSettings> mount(WidgetTester tester, {double nameWidth = 0}) async {
    tester.view.physicalSize = const Size(1500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = AppSettings(writeBrowsing: (_) async {});
    await settings.setBrowsing(
      BrowsingPreferences(listNameWidth: nameWidth, inspector: false),
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
            const [ArchiveEntry(path: 'note.txt', size: 123, directory: false)],
            'ZIP',
            true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  Rect header(WidgetTester tester, String column) =>
      tester.getRect(find.byKey(ValueKey('list-header-$column')));
  void aligned(WidgetTester tester) {
    for (final column in ['name', 'size', 'modified', 'kind']) {
      final label = header(tester, column);
      final cell = tester.getRect(
        find.byKey(ValueKey('list-cell-note.txt-$column')),
      );
      expect(cell.left, closeTo(label.left, .01), reason: column);
      expect(cell.width, closeTo(label.width, .01), reason: column);
      if (column != 'name') {
        final text = find.descendant(
          of: find.byKey(ValueKey('list-cell-note.txt-$column')),
          matching: find.byType(AppText),
        );
        expect(tester.widget<AppText>(text).textAlign, TextAlign.right);
        final textBounds = tester.getRect(text);
        expect(textBounds.left - cell.left, closeTo(8, .01));
        expect(cell.right - textBounds.right, closeTo(8, .01));
      }
    }
    final row = tester.getRect(find.byKey(const ValueKey('file-note.txt')));
    expect(header(tester, 'kind').right, closeTo(row.right - 5.5, .01));
  }

  Future<(TestGesture, Offset)> start(
    WidgetTester tester,
    String column,
  ) async {
    final point = tester.getCenter(
      find.byKey(ValueKey('list-column-resizer-$column')),
    );
    final gesture = await tester.startGesture(
      point,
      kind: PointerDeviceKind.mouse,
    );
    return (gesture, point);
  }

  testWidgets(
    'Type right edge has no handle but its left divider is adjustable',
    (tester) async {
      await mount(tester, nameWidth: 300);
      aligned(tester);
      expect(header(tester, 'kind').width, 85);
      expect(
        find.byKey(const ValueKey('list-column-resizer-kind')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('list-column-resizer-modified')),
        findsOneWidget,
      );
      expect(header(tester, 'name').width, greaterThan(300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Name divider shrinks Type first, then Modified and Size, within the window',
    (tester) async {
      final settings = await mount(tester);
      final name = header(tester, 'name');
      final kind = header(tester, 'kind');
      final (gesture, origin) = await start(tester, 'name');
      for (final (delta, size, modified, type, growth) in [
        (15.0, 85.0, 115.0, 70.0, 15.0),
        (35.0, 85.0, 100.0, 65.0, 35.0),
        (55.0, 75.0, 90.0, 65.0, 55.0),
        (2000.0, 65.0, 90.0, 65.0, 65.0),
        (1000.0, 65.0, 90.0, 65.0, 65.0),
        (10.0, 85.0, 115.0, 75.0, 10.0),
      ]) {
        await gesture.moveTo(origin + Offset(delta, 0));
        await tester.pump();
        expect(header(tester, 'name').width, closeTo(name.width + growth, .01));
        expect(header(tester, 'size').width, closeTo(size, .01));
        expect(header(tester, 'modified').width, closeTo(modified, .01));
        expect(header(tester, 'kind').right, kind.right);
        expect(header(tester, 'kind').width, type);
        aligned(tester);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(settings.browsing.listNameWidth, 0);
      expect(settings.browsing.listSizeWidth, 85);
      expect(settings.browsing.listModifiedWidth, 115);
      expect(settings.browsing.listKindWidth, 75);
      expect(settings.browsing.listSortColumn, 'name');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'dragging Name left expands only Type and preserves Size and Modified',
    (tester) async {
      await mount(tester);
      final name = header(tester, 'name');
      final size = header(tester, 'size');
      final modified = header(tester, 'modified');
      final kind = header(tester, 'kind');
      final (gesture, origin) = await start(tester, 'name');
      for (final (delta, growth) in [
        (-30.0, 30.0),
        (-600.0, 600.0),
        (-2000.0, name.width - 80),
        (-100.0, 100.0),
      ]) {
        await gesture.moveTo(origin + Offset(delta, 0));
        await tester.pump();
        expect(header(tester, 'name').width, closeTo(name.width - growth, .01));
        expect(header(tester, 'size').width, size.width);
        expect(header(tester, 'modified').width, modified.width);
        expect(header(tester, 'kind').right, kind.right);
        expect(header(tester, 'kind').width, kind.width + growth);
        aligned(tester);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'metadata remain visible when Name is between 80 and 160 pixels',
    (tester) async {
      await mount(tester);
      // A compact window leaves 120 pixels for Name while metadata still fit.
      tester.view.physicalSize = const Size(428, 800);
      await tester.pumpAndSettle();
      expect(header(tester, 'name').width, inInclusiveRange(80, 160));
      expect(find.byKey(const ValueKey('list-header-kind')), findsOneWidget);
      aligned(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Size divider compresses Type before Modified and expands only Type',
    (tester) async {
      final settings = await mount(tester);
      final name = header(tester, 'name');
      final kind = header(tester, 'kind');
      final (gesture, origin) = await start(tester, 'size');
      for (final (delta, size, modified, type) in [
        (15.0, 100.0, 115.0, 70.0),
        (50.0, 130.0, 90.0, 65.0),
        (2000.0, 130.0, 90.0, 65.0),
        (-100.0, 65.0, 115.0, 105.0),
        (10.0, 95.0, 115.0, 75.0),
      ]) {
        await gesture.moveTo(origin + Offset(delta, 0));
        await tester.pump();
        expect(header(tester, 'name'), name);
        expect(header(tester, 'kind').right, kind.right);
        expect(header(tester, 'kind').width, type);
        expect(header(tester, 'size').width, closeTo(size, .01));
        expect(header(tester, 'modified').width, closeTo(modified, .01));
        aligned(tester);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(settings.browsing.listSizeWidth, 95);
      expect(settings.browsing.listModifiedWidth, 115);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Modified divider resizes Type while its right edge stays pinned',
    (tester) async {
      final settings = await mount(tester);
      final name = header(tester, 'name');
      final size = header(tester, 'size');
      final kind = header(tester, 'kind');
      final (gesture, origin) = await start(tester, 'modified');
      for (final (delta, modified, type) in [
        (10.0, 125.0, 75.0),
        (50.0, 135.0, 65.0),
        (-100.0, 90.0, 110.0),
        (-10.0, 105.0, 95.0),
      ]) {
        await gesture.moveTo(origin + Offset(delta, 0));
        await tester.pump();
        expect(header(tester, 'name'), name);
        expect(header(tester, 'size'), size);
        expect(header(tester, 'modified').width, modified);
        expect(header(tester, 'kind').width, type);
        expect(header(tester, 'kind').right, kind.right);
        aligned(tester);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(settings.browsing.listKindWidth, 95);
      expect(settings.browsing.listModifiedWidth, 105);
      expect(
        BrowsingPreferences.fromJson(settings.browsing.toJson()).listKindWidth,
        95,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'window resizing changes only Name, including after column dragging',
    (tester) async {
      await mount(tester, nameWidth: 300);
      final (gesture, origin) = await start(tester, 'size');
      await gesture.moveTo(origin + const Offset(20, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      final original = {
        for (final column in ['name', 'size', 'modified', 'kind'])
          column: header(tester, column),
      };
      for (final width in [1200.0, 1800.0, 1500.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        for (final column in ['size', 'modified', 'kind']) {
          expect(header(tester, column).width, original[column]!.width);
        }
        expect(
          header(tester, 'name').width,
          closeTo(original['name']!.width + width - 1500, .01),
        );
        aligned(tester);
        expect(header(tester, 'kind').right, lessThan(width));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Name minimum stops dragging and metadata hide until the window fits again',
    (tester) async {
      final settings = await mount(tester);
      tester.view.physicalSize = const Size(900, 800);
      await tester.pumpAndSettle();
      final kind = header(tester, 'kind');
      final (gesture, origin) = await start(tester, 'name');
      await gesture.moveTo(origin + const Offset(-2000, 0));
      await tester.pump();
      expect(header(tester, 'name').width, closeTo(80, .01));
      expect(header(tester, 'kind').right, kind.right);
      aligned(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      final widths = (
        settings.browsing.listSizeWidth,
        settings.browsing.listModifiedWidth,
        settings.browsing.listKindWidth,
      );
      tester.view.physicalSize = const Size(880, 800);
      await tester.pumpAndSettle();
      for (final column in ['size', 'modified', 'kind']) {
        expect(find.byKey(ValueKey('list-header-$column')), findsNothing);
        expect(
          find.byKey(ValueKey('list-cell-note.txt-$column')),
          findsNothing,
        );
      }
      expect(
        find.byKey(const ValueKey('list-column-resizer-name')),
        findsNothing,
      );
      final row = tester.getRect(find.byKey(const ValueKey('file-note.txt')));
      expect(header(tester, 'name').right, closeTo(row.right - 5.5, .01));
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();
      expect(header(tester, 'size').width, widths.$1);
      expect(header(tester, 'modified').width, widths.$2);
      expect(header(tester, 'kind').width, widths.$3);
      aligned(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('narrow windows show Name without horizontal overflow', (
    tester,
  ) async {
    await mount(tester, nameWidth: 2000);
    for (final width in [360.0, 500.0, 1500.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      final name = header(tester, 'name');
      expect(name.left, greaterThanOrEqualTo(0));
      expect(name.right, lessThanOrEqualTo(width));
      if (find
          .byKey(const ValueKey('list-header-kind'))
          .evaluate()
          .isNotEmpty) {
        aligned(tester);
        expect(header(tester, 'kind').right, lessThan(width));
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
