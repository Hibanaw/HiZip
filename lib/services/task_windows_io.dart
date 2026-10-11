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
import '../ui/archive_app.dart';
import '../ui/dpi_scale.dart';
import '../ui/desktop_widgets.dart';
import '../ui/auxiliary_dialogs.dart';
import '../ui/window_chrome.dart';

WindowController? _main;
WindowController? _settingsWindow;
Future<bool>? _settingsOpening;
ValueChanged<String>? _taskAction;
Future<void> Function()? _settingsChanged;
const _host = MethodChannel('dev.hizip/task-window-host');
final _propertiesActions = <String, PropertiesWindowAction>{};
int _propertiesSequence = 0;
final auxiliaryModalDepth = ValueNotifier(0);
final _dialogReplies = <String, Completer<Map<String, dynamic>?>>{};
final _dialogActions = <String, AuxiliaryDialogAction>{};
WindowController? _dialogWindow;
int _dialogSequence = 0;
Future<void>? _dialogTurn;
typedef AuxiliaryDialogAction = Future<Map<String, dynamic>> Function(
  String,
  Map<String, dynamic>,
);
typedef PropertiesWindowAction = Future<Map<String, dynamic>> Function(
  String,
  Map<String, dynamic>,
);
Map<String, dynamic> _taskPayload(TaskFeedback data, AppSettings settings) => {
  ...data.toJson(),
  'themeMode': settings.themeMode.name,
  'accent': settings.accent.name,
  'language': settings.language.name,
};

Future<Widget?> initializeTaskWindows() async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return null;
  }
  final current = await WindowController.fromCurrentEngine();
  final args = current.arguments.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(current.arguments) as Map<String, dynamic>;
  if (!['task', 'settings', 'properties', 'dialog'].contains(args['type'])) {
    _main = current;
    await current.setWindowMethodHandler((call) async {
      if (call.method == 'dialogResult') {
        final request = Map<String, dynamic>.from(call.arguments as Map);
        final reply = _dialogReplies[request['id']];
        if (reply != null && !reply.isCompleted) {
          reply.complete(
            request['result'] == null
                ? null
                : Map<String, dynamic>.from(request['result'] as Map),
          );
        }
        return true;
      }
      if (call.method == 'dialogAction') {
        final request = Map<String, dynamic>.from(call.arguments as Map);
        final action = _dialogActions[request['id']];
        if (action == null) throw StateError('操作已取消');
        return action(
          request['action'] as String,
          Map<String, dynamic>.from(request['data'] as Map),
        );
      }
      if (call.method == 'propertiesAction') {
        final request = Map<String, dynamic>.from(call.arguments as Map);
        final action = _propertiesActions[request['id']];
        if (action == null) throw StateError('操作已取消');
        return action(
          request['action'] as String,
          Map<String, dynamic>.from(request['data'] as Map),
        );
      }
      if (call.method == 'taskAction') {
        _taskAction?.call(call.arguments as String);
        return true;
      }
      if (call.method == 'settingsChanged') {
        final values = call.arguments;
        String? accent;
        String? themeMode;
        String? language;
        String? windowMode;
        if (values is Map) {
          accent = values['accent'] as String?;
          themeMode = values['themeMode'] as String?;
          language = values['language'] as String?;
          windowMode = values['windowMode'] as String?;
          if (windowMode != null) {
            AppSettings.instance.synchronizeWindowMode(windowMode);
          }
          if (accent != null) AppSettings.instance.synchronizeAccent(accent);
          if (themeMode != null) {
            AppSettings.instance.synchronizeTheme(themeMode);
          }
          if (language != null) {
            AppSettings.instance.synchronizeLanguage(language);
          }
        }
        await _settingsChanged?.call();
        if (windowMode != null) {
          AppSettings.instance.synchronizeWindowMode(windowMode);
        }
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
  if (args['type'] == 'dialog') {
    final navigator = GlobalKey<NavigatorState>();
    final ready = Completer<void>();
    final parent = WindowController.fromWindowId(args['parent'] as String);
    var opening = false;
    Future<void> close() async {
      if (navigator.currentState?.canPop() == true) {
        await navigator.currentState!.maybePop();
      }
    }

    setTaskWindowCloseAction(() => unawaited(close()));
    _host.setMethodCallHandler((call) async {
      if (call.method == 'closeRequested') await close();
    });
    Future<void> open(Map<String, dynamic> request) async {
      await ready.future;
      if (opening) throw StateError('A dialog is already open');
      opening = true;
      final settings = AppSettings.instance;
      settings.synchronizeAccent(request['accent'] as String);
      settings.synchronizeTheme(request['themeMode'] as String);
      settings.synchronizeLanguage(request['language'] as String);
      settings.dpiScale = (request['dpiScale'] as num).toDouble();
      final kind = request['kind'] as String;
      configureAuxiliaryDialogWindow(
        kind,
        Map<String, dynamic>.from(request['bounds'] as Map),
      );
      final selection = <String, dynamic>{};
      try {
        final result = await showAppDialog<Object>(
          context: navigator.currentContext!,
          languageCode: settings.locale.languageCode,
          barrierDismissible: false,
          builder: (_) => DesktopDialogScope(
            child: Builder(
              builder: (context) => buildAuxiliaryDialog(
                context,
                kind,
                Map<String, dynamic>.from(request['data'] as Map),
                (action, data) async {
                  final result = await parent.invokeMethod<Map>(
                    'dialogAction',
                    {'id': request['id'], 'action': action, 'data': data},
                  );
                  return Map<String, dynamic>.from(result ?? const {});
                },
                selection,
              ),
            ),
          ),
        );
        await _host.invokeMethod('endModal');
        await current.hide();
        opening = false;
        await parent.invokeMethod('dialogResult', {
          'id': request['id'],
          'result': encodeAuxiliaryDialogResult(kind, result, selection),
        });
      } finally {
        opening = false;
      }
    }

    await current.setWindowMethodHandler((call) async {
      if (call.method == 'ready') {
        await ready.future;
        return true;
      }
      if (call.method == 'open') {
        unawaited(open(Map<String, dynamic>.from(call.arguments as Map)));
        return true;
      }
      if (call.method == 'beginModal' || call.method == 'endModal') {
        await _host.invokeMethod(call.method);
        return true;
      }
      if (call.method == 'cancel') {
        await close();
        return true;
      }
      throw MissingPluginException(call.method);
    });
    return _AuxiliaryDialogWindowApp(
      navigator: navigator,
      onReady: () {
        if (!ready.isCompleted) ready.complete();
      },
    );
  }
  if (args['type'] == 'properties') {
    final state = ValueNotifier(Map<String, dynamic>.from(args['data'] as Map));
    final parent = WindowController.fromWindowId(args['parent'] as String);
    final settings = AppSettings.instance;
    void syncAppearance(Map<String, dynamic> data) {
      settings.synchronizeAccent(data['accent'] as String);
      settings.synchronizeTheme(data['themeMode'] as String);
      settings.synchronizeLanguage(data['language'] as String);
      setAuxiliaryWindowTitle(
        'HiZip · ${translateAppText('属性', settings.locale.languageCode)}',
      );
    }

    syncAppearance(state.value);
    configurePropertiesWindow();
    final workspaceKey = GlobalKey<State<ArchiveWorkspace>>();
    setTaskWindowCloseAction(() async {
      final dynamic workspace = workspaceKey.currentState;
      if (workspace == null || await workspace.savePropertyDrafts() == true) {
        await current.hide();
      }
    });
    await current.setWindowMethodHandler((call) async {
      if (call.method == 'ready') return true;
      if (call.method == 'update') {
        final data = Map<String, dynamic>.from(call.arguments as Map);
        syncAppearance(data);
        state.value = data;
        return true;
      }
      throw MissingPluginException(call.method);
    });
    return _PropertiesWindowApp(
      workspaceKey: workspaceKey,
      state: state,
      onAction: (action, data) async {
        final result = await parent.invokeMethod<Map>('propertiesAction', {
          'id': args['id'],
          'action': action,
          'data': data,
        });
        if (result == null) throw StateError('操作已取消');
        final updated = Map<String, dynamic>.from(result);
        syncAppearance(updated);
        state.value = updated;
        return updated;
      },
    );
  }
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
            'windowMode': settings.windowMode.name,
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
  _host.setMethodCallHandler((call) async {
    if (call.method == 'closeRequested') {
      await _host.invokeMethod('endModal');
      await WindowController.fromWindowId(args['parent'] as String)
          .invokeMethod('taskAction', 'dismiss');
      await current.hide();
    }
  });
  configureAuxiliaryDialogWindow(
    'confirmation',
    Map<String, dynamic>.from(args['bounds'] as Map? ?? const {}),
  );
  setAuxiliaryWindowTitle(
    'HiZip · ${translateAppText('操作信息', AppSettings.instance.locale.languageCode)}',
  );
  await current.setWindowMethodHandler((call) async {
    if (call.method == 'beginModal' || call.method == 'endModal') {
      await _host.invokeMethod(call.method);
      return true;
    }
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

Future<bool> showSettingsWindow(
  AppSettings settings, {
  bool forceInline = false,
}) async {
  if (forceInline || !settings.separateWindows) {
    try {
      await _settingsWindow?.hide();
    } catch (_) {
      _settingsWindow = null;
    }
    return false;
  }
  return _settingsOpening ??= _showSettingsWindow(settings)
      .whenComplete(() => _settingsOpening = null);
}

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
      if (!settings.separateWindows) return false;
      await _settingsWindow!.show();
      return true;
    } on WindowChannelException {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  throw StateError('设置窗口未能启动，请重试。');
}

class PropertiesWindowTransport {
  PropertiesWindowTransport({AppSettings? settings})
    : settings = settings ?? AppSettings.instance;
  final AppSettings settings;
  WindowController? controller;
  final id = 'properties-${++_propertiesSequence}';
  bool disposed = false;
  Map<String, dynamic> payload(Map<String, dynamic> data) => {
    ...data,
    'accent': settings.accent.name,
    'themeMode': settings.themeMode.name,
    'language': settings.language.name,
  };

  Future<bool> show(
    Map<String, dynamic> data,
    PropertiesWindowAction action,
  ) async {
    if (disposed) return false;
    if (!settings.separateWindows) {
      await hide();
      return false;
    }
    if (_main == null) return false;
    _propertiesActions[id] = action;
    final all = await WindowController.getAll();
    if (controller != null &&
        !all.any((window) => window.windowId == controller!.windowId)) {
      controller = null;
    }
    controller ??= await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({
          'type': 'properties',
          'id': id,
          'parent': _main!.windowId,
          'data': payload(data),
        }),
      ),
    );
    var ready = false;
    for (var attempt = 0; attempt < 80 && !disposed; attempt++) {
      try {
        await controller!.invokeMethod('ready');
        ready = true;
        break;
      } on WindowChannelException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    if (!ready || disposed || !settings.separateWindows) return false;
    await controller!.invokeMethod('update', payload(data));
    await controller!.show();
    return true;
  }

  Future<void> hide() async {
    try {
      await controller?.hide();
    } catch (_) {
      controller = null;
    }
  }

  void dispose() {
    disposed = true;
    _propertiesActions.remove(id);
    unawaited(hide());
  }
}

class _PropertiesWindowApp extends StatelessWidget {
  const _PropertiesWindowApp({
    required this.state,
    required this.onAction,
    required this.workspaceKey,
  });
  final GlobalKey<State<ArchiveWorkspace>> workspaceKey;
  final ValueNotifier<Map<String, dynamic>> state;
  final PropertiesWindowAction onAction;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([state, AppSettings.instance]),
    builder: (_, _) {
      final settings = AppSettings.instance;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: desktopTheme(accent: settings.accent),
        darkTheme: desktopTheme(
          brightness: Brightness.dark,
          accent: settings.accent,
        ),
        themeMode: settings.themeMode,
        locale: settings.locale,
        supportedLocales: supportedAppLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => AppLanguageScope(
          languageCode: settings.locale.languageCode,
          child: DpiScale(
            scale: settings.dpiScale,
            child: foruiBuilder(context, child),
          ),
        ),
        home: windowResizeArea(
          ArchiveWorkspace(
            key: workspaceKey,
            propertiesData: state.value,
            propertiesAction: onAction,
          ),
        ),
      );
    },
  );
}

class AuxiliaryDialogWindowResult {
  const AuxiliaryDialogWindowResult(this.shown, this.result);
  final bool shown;
  final Map<String, dynamic>? result;
}

class AuxiliaryDialogWindowTransport {
  AuxiliaryDialogWindowTransport({required this.settings});
  final AppSettings settings;
  final id = 'dialog-${++_dialogSequence}';
  bool disposed = false;
  Future<AuxiliaryDialogWindowResult> show(
    String kind,
    Map<String, dynamic> data, {
    AuxiliaryDialogAction? onAction,
  }) async {
    final previous = _dialogTurn;
    final done = Completer<void>();
    _dialogTurn = done.future;
    if (previous != null) await previous;
    try {
      return await _show(kind, data, onAction: onAction);
    } finally {
      if (identical(_dialogTurn, done.future)) _dialogTurn = null;
      done.complete();
    }
  }

  Future<AuxiliaryDialogWindowResult> _show(
    String kind,
    Map<String, dynamic> data, {
    AuxiliaryDialogAction? onAction,
  }) async {
    if (_main == null || disposed || !settings.separateWindows) {
      return const AuxiliaryDialogWindowResult(false, null);
    }
    final reply = Completer<Map<String, dynamic>?>();
    _dialogReplies[id] = reply;
    if (onAction != null) _dialogActions[id] = onAction;
    auxiliaryModalDepth.value++;
    StreamSubscription<void>? changes;
    var shown = false;
    try {
      final all = await WindowController.getAll();
      if (_dialogWindow != null &&
          !all.any((w) => w.windowId == _dialogWindow!.windowId)) {
        _dialogWindow = null;
      }
      _dialogWindow ??= await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: jsonEncode({'type': 'dialog', 'parent': _main!.windowId}),
        ),
      );
      final controller = _dialogWindow!;
      changes = onWindowsChanged.listen((_) async {
        final windows = await WindowController.getAll();
        if (!windows.any((w) => w.windowId == controller.windowId) &&
            !reply.isCompleted) {
          reply.complete(null);
        }
      });
      var ready = false;
      for (var attempt = 0; attempt < 80; attempt++) {
        try {
          await controller.invokeMethod('ready');
          ready = true;
          break;
        } on WindowChannelException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      if (!ready || disposed) {
        return const AuxiliaryDialogWindowResult(false, null);
      }
      await controller.invokeMethod('open', {
        'id': id,
        'kind': kind,
        'data': data,
        'bounds': windowFrame(),
        'themeMode': settings.themeMode.name,
        'accent': settings.accent.name,
        'language': settings.language.name,
        'dpiScale': settings.dpiScale,
      });
      await controller.show();
      await controller.invokeMethod('beginModal');
      shown = true;
      return AuxiliaryDialogWindowResult(true, await reply.future);
    } catch (_) {
      // An unavailable secondary engine falls back to the same inline dialog.
      return AuxiliaryDialogWindowResult(shown, null);
    } finally {
      unawaited(changes?.cancel());
      try {
        if (!reply.isCompleted) await _dialogWindow?.invokeMethod('cancel');
        await _dialogWindow?.invokeMethod('endModal');
        await _dialogWindow?.hide();
      } catch (_) {}
      _dialogReplies.remove(id);
      _dialogActions.remove(id);
      auxiliaryModalDepth.value--;
    }
  }

  void dispose() {
    disposed = true;
    final reply = _dialogReplies[id];
    if (reply != null && !reply.isCompleted) reply.complete(null);
  }
}

class _AuxiliaryDialogWindowApp extends StatelessWidget {
  const _AuxiliaryDialogWindowApp({
    required this.navigator,
    required this.onReady,
  });
  final GlobalKey<NavigatorState> navigator;
  final VoidCallback onReady;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppSettings.instance,
    builder: (_, _) {
      final settings = AppSettings.instance;
      return MaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        theme: desktopTheme(accent: settings.accent),
        darkTheme: desktopTheme(
          brightness: Brightness.dark,
          accent: settings.accent,
        ),
        themeMode: settings.themeMode,
        locale: settings.locale,
        supportedLocales: supportedAppLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => AppLanguageScope(
          languageCode: settings.locale.languageCode,
          child: DpiScale(
            scale: settings.dpiScale,
            child: foruiBuilder(context, child),
          ),
        ),
        home: Builder(
          builder: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onReady());
            return const Scaffold();
          },
        ),
      );
    },
  );
}

class TaskWindowTransport {
  TaskWindowTransport({AppSettings? settings})
    : settings = settings ?? AppSettings.instance;
  final AppSettings settings;
  WindowController? controller;
  ValueChanged<String>? onAction;
  StreamSubscription<void>? changes;
  bool disposed = false, shown = false;
  bool modal = false;
  bool get supported => _main != null && settings.separateWindows;
  Future<bool> show(TaskFeedback data, ValueChanged<String> action) async {
    if (!supported ||
        disposed ||
        data.running ||
        !data.actions.keys.any((key) => key != 'dismiss')) {
      await hide();
      return false;
    }
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
          'data': _taskPayload(data, settings),
          'bounds': windowFrame(),
        }),
      ),
    );
    // The new engine registers its method handler asynchronously.
    for (var attempt = 0; attempt < 80; attempt++) {
      if (disposed) return false;
      try {
        await controller!.invokeMethod('update', _taskPayload(data, settings));
        if (!supported || disposed) {
          await hide();
          return false;
        }
        if (!shown) {
          await controller!.show();
          await controller!.invokeMethod('beginModal');
          modal = true;
          auxiliaryModalDepth.value++;
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
    if (modal) {
      modal = false;
      auxiliaryModalDepth.value--;
    }
    try {
      await controller?.invokeMethod('endModal');
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
      home: DesktopDialogScope(
        child: ValueListenableBuilder<TaskFeedback>(
          valueListenable: state,
          builder: (context, data, _) => DesktopDialog(
            title: AppText(data.title),
            content: AppText(
              data.detail,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            actions: [
              for (final action in data.actions.entries)
                DesktopButton(
                  primary: action.key == 'save' || action.key == 'create',
                  onPressed: () async {
                    await _host.invokeMethod('endModal');
                    await parent.invokeMethod('taskAction', action.key);
                    await controller.hide();
                  },
                  child: AppText(action.value),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
