import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/app_language.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/app_localizations.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/settings_page.dart';
import 'package:hizip/ui/translations.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:flutter/services.dart';

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
        const Locale('fr'),
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
      expect(find.text('English'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('language-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsNWidgets(2));
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Follow System'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Performance'));
      await tester.pumpAndSettle();
      expect(find.text('Extraction threads'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文'));
      await tester.pumpAndSettle();
      expect(find.text('语言'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  test('every supported language has complete messages and templates', () {
    final messages = {...appEnglishMessages.values, ...appMessageTemplates};
    for (final message in messages) {
      if (message == '简体中文') continue;
      expect(
        interfaceTranslations.containsKey(message),
        isTrue,
        reason: message,
      );
      final translations = interfaceTranslations[message]!;
      expect(translations.length, translationLanguages.length, reason: message);
      final placeholders = RegExp(r'\{\d+\}')
          .allMatches(message)
          .map((match) => match[0])
          .toSet();
      for (final translation in translations) {
        expect(translation, isNotEmpty);
        expect(
          RegExp(r'\{\d+\}')
              .allMatches(translation)
              .map((match) => match[0])
              .toSet(),
          placeholders,
          reason: message,
        );
      }
    }
  });

  test('status text translates and preserves literal names and paths', () {
    expect(
      translateAppText('10 个项目 · 已选择 2 个项目', 'en'),
      '10 items · 2 selected',
    );
    expect(translateAppText('1 个项目', 'en'), '1 item');
    expect(translateAppText('已复制 1 个项目', 'en'), 'Copied 1 item');
    expect(translateAppText('1 个文件、1 个文件夹', 'en'), '1 file, 1 folder');
    expect(translateAppText('已打开压缩包：不压缩', 'fr'), 'Archive ouverte : 不压缩');
    expect(translateAppText('种类', 'en'), 'Type');
    expect(translateAppText('全部进度', 'zh'), '总体进度');
    expect(translateAppText('已打开压缩包：设置.zip', 'fr'), 'Archive ouverte : 设置.zip');
    expect(translateAppText('设置.zip', 'de'), '设置.zip');
    expect(translateAppText('解压完成：/tmp/文件', 'es'), 'Extraído en: /tmp/文件');
    expect(translateAppText('创建 ZIP 的压缩等级：不压缩', 'ja'), 'ZIP 圧縮レベル：無圧縮');
  });

  for (final language in AppLanguage.values.where(
    (value) => value != AppLanguage.system,
  )) {
    test('${language.name} persists and resolves system locale', () async {
      String? stored;
      final settings = AppSettings(
        writeLanguage: (value) async => stored = value,
      );
      final restored = AppSettings(
        readLanguage: () async => stored,
        read: () async => null,
        readTheme: () async => null,
        readAccent: () async => null,
        readHighlight: () async => null,
        readBrowsing: () async => null,
        readArchive: () async => null,
      );
      await settings.setLanguage(language);
      await restored.load();
      expect(restored.language, language);
      expect(
        AppLanguage.system.resolve(
          Locale(language.resolve(const Locale('en')).languageCode, 'XX'),
        ),
        restored.locale,
      );
      expect(
        AppLanguage.system.resolve(const Locale('xx')),
        const Locale('en'),
      );
      settings.dispose();
      restored.dispose();
    });

    testWidgets(
      '${language.name} settings fit narrow windows and workspace translates',
      (tester) async {
        tester.view.physicalSize = const Size(440, 500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = AppSettings(writeLanguage: (_) async {});
        await settings.setLanguage(language);
        final code = settings.locale.languageCode;
        await tester.pumpWidget(
          MaterialApp(
            theme: desktopTheme(),
            builder: foruiBuilder,
            home: SettingsPage(settings: settings),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('language-select')), findsOneWidget);
        expect(find.text(language.label), findsOneWidget);
        expect(find.text(translateAppText('语言', code)), findsOneWidget);
        for (final section in ['性能', '压缩包', '通用', '外观']) {
          await tester.tap(find.text(translateAppText(section, code)).first);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${language.name} $section',
          );
        }
        tester.view.physicalSize = const Size(1200, 740);
        await tester.pumpWidget(
          MaterialApp(
            theme: desktopTheme(),
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
        expect(find.text(translateAppText('队列 (0)', code)), findsOneWidget);
        expect(find.text(translateAppText('种类', code)), findsWidgets);
        expect(find.text('设置'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      },
    );
  }

  testWidgets('native menus receive the same translations as Flutter', (
    tester,
  ) async {
    final desktop = DesktopIntegration();
    MethodCall? languageCall;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DesktopIntegration.channel,
      (call) async {
        languageCall = call;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopIntegration.channel,
        null,
      ),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await desktop.setLanguage(
      'fr',
      translations: {'文件': translateAppText('文件', 'fr')},
      english: appEnglishMessages,
    );
    expect((languageCall!.arguments as Map)['translations']['文件'], 'Fichier');
    expect((languageCall!.arguments as Map)['language'], 'fr');
    debugDefaultTargetPlatformOverride = null;
  });

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
