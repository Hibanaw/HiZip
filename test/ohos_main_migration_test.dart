import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/file_item_surface.dart';

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

void main() {
  final platforms = TargetPlatform.values.where(
    (platform) => platform.name == 'ohos',
  );

  group(
    'Main UI migration to HarmonyOS',
    () {
      setUp(() => debugDefaultTargetPlatformOverride = platforms.single);
      tearDown(() => debugDefaultTargetPlatformOverride = null);

      Future<void> mount(
        WidgetTester tester, {
        double width = 1200,
        String view = 'list',
      }) async {
        tester.view.physicalSize = Size(width, 800);
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
            theme: desktopTheme(),
            builder: foruiBuilder,
            home: ArchiveWorkspace(
              settings: settings,
              service: _Service(),
              enableNativeTransfers: false,
              initialDocument: ArchiveDocument(
                '/test.zip',
                const [
                  ArchiveEntry(path: 'one.txt', size: 1, directory: false),
                  ArchiveEntry(path: 'two.txt', size: 1, directory: false),
                ],
                'ZIP',
                true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      for (final width in [1200.0, 440.0]) {
        testWidgets('search toggles and dismisses outside at width $width', (
          tester,
        ) async {
          await mount(tester, width: width);
          final file = find.byKey(const ValueKey('file-one.txt'));
          final topBar = find.byKey(const ValueKey('workspace-top-bar'));
          final topRect = tester.getRect(topBar);
          final fileRect = tester.getRect(file);
          await tester.tap(find.byTooltip('搜索'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('archive-search')), findsOneWidget);
          if (width == 1200) {
            final panel = tester.getRect(
              find.byKey(const ValueKey('workspace-search-bar')),
            );
            expect(panel.width, lessThanOrEqualTo(360));
            expect(panel.top, closeTo(topRect.bottom, .01));
            expect(tester.getRect(file), fileRect);
            await tester.tap(find.byTooltip('搜索'));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('archive-search')), findsNothing);
            await tester.tap(find.byTooltip('搜索'));
            await tester.pumpAndSettle();
          }
          await tester.tap(file);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('archive-search')), findsNothing);
          expect(tester.widget<FileItemSurface>(file).selected, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          debugDefaultTargetPlatformOverride = null;
        });
      }

      testWidgets('file menu wins and the next blank click deselects', (
        tester,
      ) async {
        await mount(tester, view: 'grid');
        final file = find.byKey(const ValueKey('file-one.txt'));
        final tile = tester.getRect(file);
        await tester.tap(
          find.byKey(const ValueKey('grid-name-background-one.txt')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('重命名…'), findsOneWidget);
        expect(find.text('解压全部…'), findsNothing);
        expect(tester.widget<FileItemSurface>(file).selected, isTrue);
        await tester.tapAt(tile.topLeft + const Offset(1, 1));
        await tester.pumpAndSettle();
        expect(find.text('重命名…'), findsNothing);
        expect(tester.widget<FileItemSurface>(file).selected, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      });
    },
    skip: platforms.isEmpty ? 'Requires the HarmonyOS Flutter SDK.' : false,
  );
}
