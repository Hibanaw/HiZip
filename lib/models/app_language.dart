import 'package:flutter/material.dart';

enum AppLanguage {
  system,
  simplifiedChinese,
  english,
  japanese,
  korean,
  french,
  german,
  spanish,
}

const supportedAppLocales = [
  Locale('zh'),
  Locale('en'),
  Locale('ja'),
  Locale('ko'),
  Locale('fr'),
  Locale('de'),
  Locale('es'),
];

Locale resolveAppLocale(Locale? locale) => supportedAppLocales.firstWhere(
  (supported) => supported.languageCode == locale?.languageCode,
  orElse: () => const Locale('en'),
);

extension AppLanguageLocale on AppLanguage {
  Locale resolve(Locale system) => switch (this) {
    AppLanguage.system => resolveAppLocale(system),
    AppLanguage.simplifiedChinese => const Locale('zh'),
    AppLanguage.english => const Locale('en'),
    AppLanguage.japanese => const Locale('ja'),
    AppLanguage.korean => const Locale('ko'),
    AppLanguage.french => const Locale('fr'),
    AppLanguage.german => const Locale('de'),
    AppLanguage.spanish => const Locale('es'),
  };

  String get label => switch (this) {
    AppLanguage.system => '跟随系统',
    AppLanguage.simplifiedChinese => '简体中文',
    AppLanguage.english => 'English',
    AppLanguage.japanese => '日本語',
    AppLanguage.korean => '한국어',
    AppLanguage.french => 'Français',
    AppLanguage.german => 'Deutsch',
    AppLanguage.spanish => 'Español',
  };
}
