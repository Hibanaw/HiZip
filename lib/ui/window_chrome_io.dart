import 'dart:io';
import 'dart:ffi' as ffi;

import 'package:flutter/material.dart';
import 'package:nativeapi_flutter/nativeapi_flutter.dart' as native;

import 'desktop_widgets.dart';

bool _enabled = false, _secondary = false;
native.Window? _window;
VoidCallback? _closeSecondary;
void setTaskWindowCloseAction(VoidCallback action) => _closeSecondary = action;

/// Resolve and configure the existing Flutter window rather than creating one.
Future<void> initializeWindowChrome({int? nativePointer}) async {
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

Widget windowDragArea(Widget child) =>
    !_enabled ? child : native.DragToMoveArea(window: _window, child: child);

double windowChromeHeight() => 49;

Widget windowResizeArea(Widget child) =>
    !_enabled || _secondary || Platform.isMacOS
    ? child // AppKit retains the system resize edges and rounded window corners.
    : native.DragToResizeArea(window: _window, resizeEdgeSize: 5, child: child);

Widget windowLeadingControls() => _enabled && Platform.isMacOS
    ? const SizedBox(
        width: 88,
      ) // Real NSWindow traffic lights overlay this area.
    : const SizedBox.shrink();

Widget windowTrailingControls() => _enabled && !Platform.isMacOS
    ? _WindowControls(window: _window!)
    : const SizedBox.shrink();

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
      DesktopIconButton(
        tooltip: '关闭',
        icon: const Icon(Icons.close, size: 17),
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
  final rect = _window?.bounds.toRect();
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
  window.setSize(const Size(480, 240).toNative(), false);
  window.minimumSize = const Size(480, 240).toNative();
  window.maximumSize = const Size(480, 240).toNative();
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
    window.bounds = rect.toNative();
  }
  window.title = 'HiZip · 操作信息';
}

void configureSettingsWindow() {
  _window!
    ..title = 'HiZip · 设置'
    ..minimumSize = const Size(440, 360).toNative();
  _window!.setSize(const Size(600, 440).toNative(), false);
  _window!.center();
}

void setAuxiliaryWindowTitle(String title) {
  _window?.title = title;
}
