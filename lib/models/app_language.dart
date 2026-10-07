import 'package:flutter/material.dart';

enum AppLanguage { system, simplifiedChinese, english }

extension AppLanguageLocale on AppLanguage {
  Locale resolve(Locale system) => switch (this) {
    AppLanguage.system => Locale(system.languageCode == 'zh' ? 'zh' : 'en'),
    AppLanguage.simplifiedChinese => const Locale('zh'),
    AppLanguage.english => const Locale('en'),
  };
}
