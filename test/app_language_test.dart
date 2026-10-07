import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/app_language.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/app_localizations.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/settings_page.dart';

void main() {
  test(
    'language persists, follows system and handles storage failures',
    () async {
      String? stored;
      AppSettings create() => AppSettings(
        readLanguage: () async => stored,
        writeLanguage: (value) async {
          stored = value;
        },
        read: () async => null,
        readTheme: () async => null,
        readHighlight: () async => null,
        readBrowsing: () async => null,
        readArchive: () async => null,
      );
      final first = create();
      await first.setLanguage(AppLanguage.english);
      final second = create();
      await second.load();
      expect(second.language, AppLanguage.english);
      expect(
        AppLanguage.system.resolve(const Locale('zh', 'SG')),
        const Locale('zh'),
      );
      expect(
        AppLanguage.system.resolve(const Locale('fr')),
        const Locale('en'),
      );
      stored = 'invalid';
      await second.load();
      expect(second.language, AppLanguage.simplifiedChinese);
      final broken = AppSettings(
        writeLanguage: (_) async => throw StateError('disk'),
      );
      await broken.setLanguage(AppLanguage.english);
      expect(broken.language, AppLanguage.simplifiedChinese);
      expect(broken.error, isNotNull);
      expect(translateAppText('已复制 3 个项目', 'en'), 'Copied 3 items');
      first.dispose();
      second.dispose();
      broken.dispose();
    },
  );

  testWidgets(
    'language choices appear under Appearance and apply immediately',
    (tester) async {
      tester.view.physicalSize = const Size(440, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = AppSettings(writeLanguage: (_) async {});
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(),
          builder: foruiBuilder,
          home: SettingsPage(settings: settings),
        ),
      );
      expect(find.text('语言'), findsOneWidget);
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsNWidgets(2));
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Follow System'), findsNWidgets(2));
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(find.text('Extraction threads'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文'));
      await tester.pumpAndSettle();
      expect(find.text('语言'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets(
    'workspace toolbar and search localize while filenames stay literal',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = AppSettings(writeLanguage: (_) async {});
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          home: ArchiveWorkspace(
            settings: settings,
            enableNativeTransfers: false,
            initialDocument: ArchiveDocument(
              '/test.zip',
              const [ArchiveEntry(path: '设置', size: 2, directory: false)],
              'ZIP',
              true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await settings.setLanguage(AppLanguage.english);
      await tester.pumpAndSettle();
      expect(find.text('Queue (0)'), findsOneWidget);
      expect(find.byTooltip('Gallery View'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
