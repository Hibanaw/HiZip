import 'dart:async';
import 'app_localizations.dart';
import '../services/app_settings.dart';

import 'dart:io';
import 'dart:ffi' as ffi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nativeapi/nativeapi.dart' as native;

import 'desktop_widgets.dart';
import 'window_close_button.dart';

bool _enabled = false, _secondary = false, _harmony = false;
native.Window? _window;
VoidCallback? _closeSecondary;
native.NativeHostWindowState? _harmonyState;
void setTaskWindowCloseAction(VoidCallback action) => _closeSecondary = action;
void setWindowClosePreparation(Future<void> Function()? prepare) {
  if (native.NativePlatform.isHarmonyOS) {
    native.NativeHostWindow.setClosePreparation(prepare);
  }
}

/// Resolve and configure the existing Flutter window rather than creating one.
Future<void> initializeWindowChrome({int? nativePointer}) async {
  _enabled = false;
  _harmony = false;
  _harmonyState = null;
  if (native.NativePlatform.isHarmonyOS) {
    try {
      final host = await native.NativePlatform.hostInfo();
      if (host.capabilities.contains('windowControl')) {
        await native.NativeHostWindow.configure(title: 'HiZip');
        await native.NativeHostWindow.setDecorVisible(
          false,
          height: windowChromeHeight().round(),
        );
        _harmonyState = await native.NativeHostWindow.state();
        _enabled = true;
        _harmony = true;
      }
    } on PlatformException catch (error) {
      // Some HarmonyOS device modes do not expose desktop window controls.
      debugPrint('Native window configuration unavailable: ${error.message}');
    }
    return;
  }
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  _secondary = nativePointer != null;
  _window = nativePointer == null
      ? native.WindowManager.instance.getCurrent()
      : native.Window.createWithNativeWindow(
          ffi.Pointer<ffi.Void>.fromAddress(nativePointer),
        );
  if (_window == null) return;
  // macOS chrome is configured before the Flutter view by AppKit.
  if (_secondary) {
    _window!.titleBarStyle = native.TitleBarStyle.normal;
  } else if (!Platform.isMacOS) {
    _window!.titleBarStyle = native.TitleBarStyle.hidden;
  }
  _window!.isWindowControlButtonsVisible = _secondary || Platform.isMacOS;
  _enabled = true;
}

Widget windowDragArea(Widget child) => _harmony
    ? _HarmonyDragArea(child: child)
    : !_enabled
    ? child
    : native.DragToMoveArea(window: _window, child: child);

double windowChromeHeight() => 49;

Widget windowResizeArea(Widget child) =>
    !_enabled || _harmony || _secondary || Platform.isMacOS
    ? child // AppKit retains the system resize edges and rounded window corners.
    : native.DragToResizeArea(window: _window, resizeEdgeSize: 5, child: child);

Widget windowLeadingControls() => _enabled && !_harmony && Platform.isMacOS
    ? const SizedBox(
        width: 88,
      ) // Real NSWindow traffic lights overlay this area.
    : const SizedBox.shrink();

Widget windowTrailingControls() => _enabled && (_harmony || !Platform.isMacOS)
    ? _harmony
          ? const _HarmonySystemControlsSpace()
          : _WindowControls(window: _window!)
    : const SizedBox.shrink();

class _HarmonyDragArea extends StatelessWidget {
  const _HarmonyDragArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onPanStart: (_) =>
        unawaited(_harmonyWindowAction(native.NativeHostWindow.startMoving)),
    onDoubleTap: () => unawaited(
      _harmonyWindowAction(() async {
        final state = await native.NativeHostWindow.state();
        if (state.isMaximized || state.isFullScreen) {
          await native.NativeHostWindow.restore();
        } else {
          await native.NativeHostWindow.maximize();
        }
      }),
    ),
    child: child,
  );
}

Future<void> _harmonyWindowAction(Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    debugPrint('Harmony window action unavailable: $error');
  }
}

class _HarmonySystemControlsSpace extends StatefulWidget {
  const _HarmonySystemControlsSpace();

  @override
  State<_HarmonySystemControlsSpace> createState() =>
      _HarmonySystemControlsSpaceState();
}

class _HarmonySystemControlsSpaceState
    extends State<_HarmonySystemControlsSpace> {
  StreamSubscription<native.NativeHostWindowState>? _changes;
  native.NativeHostWindowState? _state;

  @override
  void initState() {
    super.initState();
    _state = _harmonyState;
    _changes = native.NativeHostWindow.changes.listen(
      (state) {
        if (mounted) {
          setState(() => _state = state);
        }
      },
      onError: (Object error) =>
          debugPrint('Harmony window state unavailable: $error'),
    );
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttons = _state?.titleButtons;
    return SizedBox(
      key: const ValueKey('harmony-system-controls-space'),
      width: buttons == null ? 128 : buttons.width + buttons.right,
    );
  }
}

class _WindowControls extends StatefulWidget {
  const _WindowControls({required this.window});
  final native.Window window;
  @override
  State<_WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<_WindowControls> {
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DesktopIconButton(
        tooltip: '最小化',
        icon: const Icon(Icons.remove, size: 16),
        onPressed: widget.window.minimize,
      ),
      DesktopIconButton(
        tooltip: widget.window.isMaximized ? '还原' : '最大化',
        icon: Icon(
          widget.window.isMaximized ? Icons.filter_none : Icons.crop_square,
          size: 14,
        ),
        onPressed: () => setState(() {
          if (widget.window.isMaximized) {
            widget.window.unmaximize();
          } else {
            widget.window.maximize();
          }
        }),
      ),
      WindowCloseButton(
        platform: Platform.isLinux
            ? TargetPlatform.linux
            : TargetPlatform.windows,
        onPressed: () {
          if (_secondary) {
            (_closeSecondary ?? widget.window.hide)();
          } else {
            native.Application.instance.quit(0);
          }
        },
      ),
    ],
  );
}

Map<String, double> windowFrame() {
  final rect = _window?.bounds;
  return rect == null
      ? {}
      : {
          'x': rect.left,
          'y': rect.top,
          'width': rect.width,
          'height': rect.height,
        };
}

void configureTaskWindow(Map<String, dynamic> parent) {
  final window = _window!;
  window.setSize(const Size(480, 240), false);
  window.minimumSize = const Size(480, 240);
  window.maximumSize = const Size(480, 240);
  window.isResizable = false;
  if (parent.isEmpty) {
    window.center();
  } else {
    final rect = Rect.fromLTWH(
      (parent['x'] as num).toDouble() +
          ((parent['width'] as num).toDouble() - 480) / 2,
      (parent['y'] as num).toDouble() +
          ((parent['height'] as num).toDouble() - 240) / 2,
      480,
      240,
    );
    window.bounds = rect;
  }
  window.title =
      'HiZip · ${translateAppText('操作信息', AppSettings.instance.locale.languageCode)}';
}

void configureSettingsWindow() {
  _window!
    ..title =
        'HiZip · ${translateAppText('设置', AppSettings.instance.locale.languageCode)}'
    ..minimumSize = const Size(440, 360);
  _window!.setSize(const Size(600, 440), false);
  _window!.center();
}

void setAuxiliaryWindowTitle(String title) {
  _window?.title = title;
}

void configurePropertiesWindow() {
  _window!.minimumSize = const Size(320, 340);
  _window!.setSize(const Size(380, 600), false);
  _window!.center();
}

void configureAuxiliaryDialogWindow(String kind, Map<String, dynamic> parent) {
  final window = _window!;
  final title = switch (kind) {
    'create' => '创建压缩包',
    'password' => '输入压缩包密码',
    'extraction' => '解压选项',
    'transfer' => '目录',
    'rename' => '重命名',
    'entryName' => '创建',
    _ => '操作信息',
  };
  window.title =
      'HiZip · ${translateAppText(title, AppSettings.instance.locale.languageCode)}';
  window.minimumSize = const Size(380, 280);
  window.isResizable = true;
  window.isMinimizable = false;
  final parentHeight = (parent['height'] as num?)?.toDouble() ?? 800;
  final width = kind == 'create' ? 520.0 : 480.0;
  final height =
      (kind == 'create'
              ? 720.0
              : kind == 'transfer'
              ? 440.0
              : 360.0)
          .clamp(280.0, (parentHeight - 80).clamp(280.0, 720.0));
  window.setSize(Size(width, height), false);
  if (parent.isEmpty) {
    window.center();
  } else {
    window.bounds = Rect.fromLTWH(
      (parent['x'] as num).toDouble() +
          ((parent['width'] as num).toDouble() - width) / 2,
      (parent['y'] as num).toDouble() + (parentHeight - height) / 2,
      width,
      height,
    );
  }
}
