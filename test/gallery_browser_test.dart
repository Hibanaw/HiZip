import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/file_item_surface.dart';
import 'package:hizip/ui/gallery_browser.dart';

class GalleryService extends ArchiveService {
  final readPreviews = <String>[];
  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async {
    readPreviews.add(entry.path);
    if (entry.isText) return Uint8List.fromList('gallery text'.codeUnits);
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAFAAAAAoCAIAAADmAupWAAAASklEQVR4nO3PAQkAIBDAQKMY1eYaQ9gfLMBu3bNHtb4fAAMDAwMDA48JuB5wPeB6wPWA6wHXA64HXA+4HnA94HrA9YDrAdcDrvcATABErSC52PEAAAAASUVORK5CYII=',
    );
  }
}

void main() {
  testWidgets(
    'gallery restores preferences, previews without inspector and scrolls with keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? stored;
      final settings = AppSettings(
        readBrowsing: () async => stored,
        writeBrowsing: (value) async {
          stored = value;
        },
      );
      await settings.setBrowsing(
        const BrowsingPreferences(
          view: 'gallery',
          galleryIconSize: 112,
          inspector: false,
        ),
      );
      final service = GalleryService();
      final doc = ArchiveDocument(
        '/sample.zip',
        [
          const ArchiveEntry(path: '00.png', size: 70, directory: false),
          for (var i = 1; i < 30; i++)
            ArchiveEntry(
              path: '${i.toString().padLeft(2, '0')}.txt',
              size: 12,
              directory: false,
            ),
        ],
        'ZIP',
        true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(brightness: Brightness.dark),
          builder: foruiBuilder,
          home: ArchiveWorkspace(
            settings: settings,
            service: service,
            initialDocument: doc,
            enableNativeTransfers: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GalleryBrowser), findsOneWidget);
      expect(find.byKey(const ValueKey('inspector-panel')), findsNothing);
      expect(
        tester.widget<DesktopSlider>(find.byType(DesktopSlider)).value,
        112,
      );
      expect(service.readPreviews, contains('00.png'));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('gallery-preview')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      // Lazy strip construction must not read every entry in a large directory.
      expect(service.readPreviews.length, lessThan(10));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('gallery text'), findsOneWidget);
      for (var i = 0; i < 19; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final strip = tester.widget<ListView>(
        find.byKey(const ValueKey('gallery-filmstrip')),
      );
      expect(strip.controller!.offset, greaterThan(0));
      expect(
        tester
            .widget<FileItemSurface>(find.byKey(const ValueKey('file-20.txt')))
            .selected,
        true,
      );
      await tester.tap(find.byTooltip('图标视图'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('画廊视图'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DesktopSlider>(find.byType(DesktopSlider)).value,
        112,
      );
      expect(
        BrowsingPreferences.fromJson(
          jsonDecode(stored!) as Map<String, dynamic>,
        ).view,
        'gallery',
      );
      tester.view.physicalSize = const Size(390, 400);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'gallery inspector pins file and folder information to top in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = AppSettings(writeBrowsing: (_) async {});
        await settings.setBrowsing(
          const BrowsingPreferences(view: 'gallery', inspector: true),
        );
        final doc = ArchiveDocument(
          '/sample.zip',
          const [
            ArchiveEntry(path: '00.png', size: 70, directory: false),
            ArchiveEntry(path: 'folder/child.txt', size: 12, directory: false),
          ],
          'ZIP',
          true,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: desktopTheme(brightness: brightness),
            builder: foruiBuilder,
            home: ArchiveWorkspace(
              settings: settings,
              service: GalleryService(),
              initialDocument: doc,
              enableNativeTransfers: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        void checkTop() {
          final panel = find.byKey(const ValueKey('inspector-panel'));
          final information = find.byKey(
            const ValueKey('inspector-information'),
          );
          final summary = find.byKey(const ValueKey('inspector-summary'));
          expect(
            tester.getTopLeft(information).dy - tester.getTopLeft(panel).dy,
            16,
          );
          expect(
            tester.getTopLeft(summary).dy,
            tester.getTopLeft(information).dy,
          );
          expect(find.byKey(const ValueKey('inspector-preview')), findsNothing);
          expect(tester.getSize(summary).height, lessThanOrEqualTo(80));
          expect(tester.takeException(), isNull);
        }

        await tester.tap(find.byKey(const ValueKey('file-00.png')));
        await tester.pumpAndSettle();
        checkTop();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('inspector-summary')),
            matching: find.text('00.png'),
          ),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        checkTop();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('inspector-summary')),
            matching: find.text('folder'),
          ),
          findsOneWidget,
        );
        tester.view.physicalSize = const Size(1100, 440);
        await tester.pumpAndSettle();
        checkTop();
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      },
    );
  }

  testWidgets(
    'folders and unreadable images have fallbacks and directory navigation keeps gallery',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = AppSettings(writeBrowsing: (_) async {});
      await settings.setBrowsing(
        const BrowsingPreferences(view: 'gallery', inspector: false),
      );
      final doc = ArchiveDocument(
        '/sample.zip',
        const [
          ArchiveEntry(path: 'folder/child.txt', size: 12, directory: false),
        ],
        'ZIP',
        true,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          home: ArchiveWorkspace(
            settings: settings,
            service: GalleryService(),
            initialDocument: doc,
            enableNativeTransfers: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FileItemSurface>(find.byKey(const ValueKey('file-folder')))
            .selected,
        true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(GalleryBrowser), findsOneWidget);
      expect(
        tester
            .widget<FileItemSurface>(
              find.byKey(const ValueKey('file-folder/child.txt')),
            )
            .selected,
        true,
      );
      expect(find.text('gallery text'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
