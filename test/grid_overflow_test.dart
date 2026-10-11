import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/app_language.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/browsing_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';

class _GridService extends ArchiveService {
  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'writableFormats': ['zip'],
  };
  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async =>
      Uint8List(0);
}

class _GridDesktop extends DesktopIntegration {
  @override
  bool get supportsQuickLook => false;
  @override
  bool get supportsFileIntegration => false;
  @override
  bool get supportsMenuBar => false;
  @override
  Future<DefaultApplication?> defaultApplication(String name) async => null;
}

void main() {
  for (final scale in [.75, 1.0, 1.5, 3.0]) {
    testWidgets('grid labels and rename fit at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(3400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = AppSettings(
        writeBrowsing: (_) async {},
        writeLanguage: (_) async {},
      );
      await settings.setLanguage(AppLanguage.french);
      await settings.setBrowsing(
        const BrowsingPreferences(
          view: 'grid',
          gridIconSize: 32,
          inspector: false,
        ),
      );
      addTearDown(settings.dispose);
      final entries = [
        const ArchiveEntry(
          path: '一个很长的中文文件名以及English日本語한글.txt',
          size: 999999999,
          directory: false,
        ),
        const ArchiveEntry(
          path: 'very-long-filename-with-multiple-words-and-characters.txt',
          size: 2048,
          directory: false,
        ),
        const ArchiveEntry(path: '文件夹/', size: 0, directory: true),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(brightness: Brightness.dark),
          builder: (context, child) => foruiBuilder(
            context,
            MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
          home: ArchiveWorkspace(
            service: _GridService(),
            desktop: _GridDesktop(),
            settings: settings,
            initialDocument: ArchiveDocument('/test.zip', entries, 'ZIP', true),
            enableNativeTransfers: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ArchiveWorkspace));
      var gestureTime = 0;
      for (final iconSize in [32.0, 35.5, 36.0, 64.0, 128.0, 144.0]) {
        state.setState(() => state.iconSize = iconSize);
        await settings.setBrowsing(
          BrowsingPreferences(
            view: 'grid',
            gridIconSize: iconSize,
            inspector: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'icon $iconSize, scale $scale',
        );
        final tile = find.byKey(ValueKey('file-${entries.first.path}'));
        await tester.ensureVisible(tile);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        final timestamp = Duration(seconds: ++gestureTime);
        await gesture.down(
          tester.getCenter(
            find.byKey(ValueKey('grid-icon-background-${entries.first.path}')),
          ),
          timeStamp: timestamp,
        );
        await gesture.up(
          timeStamp: timestamp + const Duration(milliseconds: 10),
        );
        await tester.pumpAndSettle();
        final iconBackground =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(
                        ValueKey('grid-icon-background-${entries.first.path}'),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final nameBackground =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(
                        ValueKey('grid-name-background-${entries.first.path}'),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final scheme = Theme.of(tester.element(tile)).colorScheme;
        expect(iconBackground.color!.a, inExclusiveRange(0, 1));
        expect(iconBackground.color!.r, iconBackground.color!.g);
        expect(iconBackground.color!.g, iconBackground.color!.b);
        expect(nameBackground.color, scheme.primary);
        final name = tester.widget<Text>(
          find.descendant(of: tile, matching: find.text(entries.first.name)),
        );
        expect(name.maxLines, 2);
        expect(name.style!.color, scheme.onPrimaryContainer);
        expect(
          tester.widgetList<Text>(
            find.descendant(of: tile, matching: find.byType(Text)),
          ),
          hasLength(1),
        );
        await state.renameSelection();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('rename-entry-name')), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'rename, icon $iconSize, scale $scale',
        );
        state.cancelRename();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
