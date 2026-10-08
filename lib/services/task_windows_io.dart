import 'package:flutter_localizations/flutter_localizations.dart';

import '../models/app_language.dart';
import '../ui/app_localizations.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/task_feedback.dart';
import 'app_settings.dart';
import '../ui/settings_page.dart';
import '../ui/dpi_scale.dart';
import '../ui/desktop_widgets.dart';
import '../ui/task_feedback_panel.dart';
import '../ui/window_chrome.dart';

WindowController? _main;
WindowController? _settingsWindow;
Future<bool>? _settingsOpening;
ValueChanged<String>? _taskAction;
Future<void> Function()? _settingsChanged;
const _host = MethodChannel('dev.hizip/task-window-host');
Map<String, dynamic> _taskPayload(TaskFeedback data) => {
  ...data.toJson(),
  'themeMode': AppSettings.instance.themeMode.name,
  'accent': AppSettings.instance.accent.name,
  'language': AppSettings.instance.language.name,
};

Future<Widget?> initializeTaskWindows() async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return null;
  }
  final current = await WindowController.fromCurrentEngine();
  final args = current.arguments.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(current.arguments) as Map<String, dynamic>;
  if (args['type'] != 'task' && args['type'] != 'settings') {
    _main = current;
    await current.setWindowMethodHandler((call) async {
      if (call.method == 'taskAction') {
        _taskAction?.call(call.arguments as String);
        return true;
      }
      if (call.method == 'settingsChanged') {
        final values = call.arguments;
        String? accent;
        String? themeMode;
        String? language;
        if (values is Map) {
          accent = values['accent'] as String?;
          themeMode = values['themeMode'] as String?;
          language = values['language'] as String?;
          if (accent != null) AppSettings.instance.synchronizeAccent(accent);
          if (themeMode != null) {
            AppSettings.instance.synchronizeTheme(themeMode);
          }
          if (language != null) {
            AppSettings.instance.synchronizeLanguage(language);
          }
        }
        await _settingsChanged?.call();
        if (accent != null) AppSettings.instance.synchronizeAccent(accent);
        if (themeMode != null) {
          AppSettings.instance.synchronizeTheme(themeMode);
        }
        if (language != null) {
          AppSettings.instance.synchronizeLanguage(language);
        }
        return true;
      }
      throw MissingPluginException(call.method);
    });
    return null;
  }
  final pointer = await _host.invokeMethod<int>('nativePointer');
  if (pointer == null) throw StateError('Auxiliary window has no native host');
  await initializeWindowChrome(nativePointer: pointer);
  await AppSettings.instance.load();
  if (args['type'] == 'settings') {
    final settings = AppSettings.instance;
    final parent = WindowController.fromWindowId(args['parent'] as String);
    settings.addListener(() {
      if (!settings.saving) {
        unawaited(
          parent.invokeMethod('settingsChanged', {
            'accent': settings.accent.name,
            'themeMode': settings.themeMode.name,
            'language': settings.language.name,
            'dpiScale': settings.dpiScale,
          }),
        );
      }
    });
    setTaskWindowCloseAction(() => unawaited(current.hide()));
    configureSettingsWindow();
    await current.setWindowMethodHandler((call) async {
      if (call.method == 'ready') {
        await settings.load();
        return true;
      }
      throw MissingPluginException(call.method);
    });
    return ListenableBuilder(
      listenable: settings,
      builder: (_, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: desktopTheme(accent: settings.accent),
        darkTheme: desktopTheme(
          brightness: Brightness.dark,
          accent: settings.accent,
        ),
        themeMode: settings.themeMode,

        locale: settings.language == AppLanguage.system
            ? null
            : settings.locale,

        supportedLocales: supportedAppLocales,
        localeResolutionCallback: (locale, _) => resolveAppLocale(locale),

        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => AppLanguageScope(
          languageCode: Localizations.localeOf(context).languageCode,
          child: DpiScale(
            scale: settings.dpiScale,
            child: foruiBuilder(context, child),
          ),
        ),
        home: windowResizeArea(
          SettingsPage(
            settings: settings,
            systemFrame: true,
            onClose: () => unawaited(current.hide()),
          ),
        ),
      ),
    );
  }
  final state = ValueNotifier(
    TaskFeedback.fromJson(Map<String, dynamic>.from(args['data'] as Map)),
  );
  // Bind nativeapi to this engine's NSWindow/HWND, never the active parent.
  setTaskWindowCloseAction(() {
    unawaited(
      WindowController.fromWindowId(args['parent'] as String)
          .invokeMethod('taskAction', 'dismiss'),
    );
    unawaited(current.hide());
  });
  configureTaskWindow(
    Map<String, dynamic>.from(args['bounds'] as Map? ?? const {}),
  );
  setAuxiliaryWindowTitle(
    'HiZip · ${translateAppText('操作信息', AppSettings.instance.locale.languageCode)}',
  );
  await current.setWindowMethodHandler((call) async {
    if (call.method == 'update') {
      final payload = Map<String, dynamic>.from(call.arguments as Map);
      AppSettings.instance.synchronizeAccent(
        payload['accent'] as String? ?? 'blue',
      );
      AppSettings.instance.synchronizeTheme(
        payload['themeMode'] as String? ?? 'system',
      );
      AppSettings.instance.synchronizeLanguage(
        payload['language'] as String? ?? 'simplifiedChinese',
      );
      setAuxiliaryWindowTitle(
        'HiZip · ${translateAppText('操作信息', AppSettings.instance.locale.languageCode)}',
      );
      state.value = TaskFeedback.fromJson(payload);
      return true;
    }
    throw MissingPluginException(call.method);
  });
  return _TaskWindowApp(
    state: state,
    controller: current,
    parent: WindowController.fromWindowId(args['parent'] as String),
  );
}

Future<bool> showSettingsWindow(AppSettings settings) =>
    _settingsOpening ??= _showSettingsWindow(settings)
        .whenComplete(() => _settingsOpening = null);

Future<bool> _showSettingsWindow(AppSettings settings) async {
  if (_main == null) return false;
  _settingsChanged = settings.load;
  final all = await WindowController.getAll();
  if (_settingsWindow != null &&
      !all.any((w) => w.windowId == _settingsWindow!.windowId)) {
    _settingsWindow = null;
  }
  _settingsWindow ??= await WindowController.create(
    WindowConfiguration(
      hiddenAtLaunch: true,
      arguments: jsonEncode({'type': 'settings', 'parent': _main!.windowId}),
    ),
  );
  for (var attempt = 0; attempt < 80; attempt++) {
    try {
      await _settingsWindow!.invokeMethod('ready');
      await _settingsWindow!.show();
      return true;
    } on WindowChannelException {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  throw StateError('设置窗口未能启动，请重试。');
}

class TaskWindowTransport {
  WindowController? controller;
  ValueChanged<String>? onAction;
  StreamSubscription<void>? changes;
  bool disposed = false, shown = false;
  bool get supported => _main != null;
  Future<bool> show(TaskFeedback data, ValueChanged<String> action) async {
    if (!supported || disposed) return false;
    onAction = action;
    _taskAction = (value) => onAction?.call(value);
    changes ??= onWindowsChanged.listen((_) async {
      final target = controller;
      if (target == null || disposed) return;
      final all = await WindowController.getAll();
      if (!all.any((w) => w.windowId == target.windowId) &&
          controller == target) {
        controller = null;
        shown = false;
        onAction?.call('dismiss');
      }
    });
    final all = await WindowController.getAll();
    if (controller != null &&
        !all.any((w) => w.windowId == controller!.windowId)) {
      controller = null;
    }
    if (controller == null) shown = false;
    controller ??= await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({
          'type': 'task',
          'parent': _main!.windowId,
          'data': _taskPayload(data),
          'bounds': windowFrame(),
        }),
      ),
    );
    // The new engine registers its method handler asynchronously.
    for (var attempt = 0; attempt < 80; attempt++) {
      if (disposed) return false;
      try {
        await controller!.invokeMethod('update', _taskPayload(data));
        if (!shown) {
          await controller!.show();
          shown = true;
        }
        return true;
      } on WindowChannelException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    await controller?.hide();
    return false;
  }

  Future<void> hide() async {
    shown = false;
    try {
      await controller?.hide();
    } catch (_) {
      controller = null;
    }
  }

  void dispose() {
    disposed = true;
    onAction = null;
    unawaited(changes?.cancel());
    unawaited(hide());
  }
}

class _TaskWindowApp extends StatelessWidget {
  const _TaskWindowApp({
    required this.state,
    required this.controller,
    required this.parent,
  });
  final ValueNotifier<TaskFeedback> state;
  final WindowController controller, parent;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppSettings.instance,
    builder: (_, _) => MaterialApp(
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
        child: foruiBuilder(context, child),
      ),
      home: windowResizeArea(
        Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: ValueListenableBuilder<TaskFeedback>(
                    valueListenable: state,
                    builder: (_, data, _) => TaskFeedbackPanel(
                      inWindow: true,
                      data: data,
                      onAction: (value) async {
                        await parent.invokeMethod('taskAction', value);
                        await controller.hide();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
