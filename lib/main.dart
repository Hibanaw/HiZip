import 'package:flutter_localizations/flutter_localizations.dart';

import 'models/app_language.dart';
import 'ui/app_localizations.dart';

import 'package:flutter/material.dart';

import 'ui/archive_app.dart';
import 'ui/dpi_scale.dart';
import 'ui/window_chrome.dart';
import 'ui/desktop_widgets.dart';
import 'services/task_windows.dart';
import 'services/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final auxiliary = await initializeTaskWindows();
  if (auxiliary != null) {
    runApp(auxiliary);
    return;
  }
  await initializeWindowChrome();
  await AppSettings.instance.load();
  runApp(const HiZipApp());
}

class HiZipApp extends StatelessWidget {
  const HiZipApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppSettings.instance,
    builder: (_, _) => MaterialApp(
      title: 'HiZip',
      debugShowCheckedModeBanner: false,
      theme: desktopTheme(accent: AppSettings.instance.accent),
      darkTheme: desktopTheme(
        brightness: Brightness.dark,
        accent: AppSettings.instance.accent,
      ),
      themeMode: AppSettings.instance.themeMode,

      locale: AppSettings.instance.language == AppLanguage.system
          ? null
          : AppSettings.instance.locale,

      supportedLocales: supportedAppLocales,
      localeResolutionCallback: (locale, _) => resolveAppLocale(locale),

      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => AppLanguageScope(
        languageCode: Localizations.localeOf(context).languageCode,
        child: DpiScale(
          scale: AppSettings.instance.dpiScale,
          child: foruiBuilder(context, child),
        ),
      ),
      scrollBehavior: const DesktopScrollBehavior(),
      home: windowResizeArea(const ArchiveWorkspace()),
    ),
  );
}
