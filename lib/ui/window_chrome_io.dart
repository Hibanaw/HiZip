import 'app_localizations.dart';
import '../services/app_settings.dart';

import 'dart:io';
import 'dart:ffi' as ffi;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nativeapi_flutter/nativeapi_flutter.dart' as native;

import 'desktop_widgets.dart';
import 'window_close_button.dart';

bool _enabled = false, _secondary = false;
native.Window? _window;
VoidCallback? _closeSecondary;
void setTaskWindowCloseAction(VoidCallback action) => _closeSecondary = action;

// GTK3's Wayland backend has no visible-region API (only an input region),
// so this stays false there; X11 and XWayland sessions report true.
bool _canRoundLinuxCorners = false;
const double _linuxCornerRadius = 10;

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
  if (Platform.isLinux && !_secondary) {
    _canRoundLinuxCorners = native.Window.isShapeSupported();
    if (_canRoundLinuxCorners) {
      _applyLinuxWindowShape();
      final windowId = _window!.id;
      native.WindowManager.instance.addListener((event) {
        if (event.windowId != windowId) return;
        switch (event) {
          case native.WindowResizedEvent():
          case native.WindowMaximizedEvent():
          case native.WindowRestoredEvent():
          case native.WindowEnteredFullScreenEvent():
          case native.WindowExitedFullScreenEvent():
            _applyLinuxWindowShape();
          default:
            break;
        }
      });
    }
  }
}

/// Rounds the main window's visible (and input) region on Linux, skipping
/// the corners while maximized or full screen like other desktop windows do.
void _applyLinuxWindowShape() {
  final window = _window;
  if (window == null || !_canRoundLinuxCorners) return;
  if (window.isMaximized || window.isFullScreen) {
    window.setShape(null);
    return;
  }
  final size = window.contentSize;
  if (size.width <= _linuxCornerRadius * 2 ||
      size.height <= _linuxCornerRadius * 2) {
    return;
  }
  final shape = native.WindowShape.create();
  if (shape == null) return;
  try {
    for (final point in _roundedRectanglePoints(
      size.width,
      size.height,
      _linuxCornerRadius,
    )) {
      shape.addPoint(point);
    }
    window.setShape(shape);
  } finally {
    shape.dispose();
  }
}

/// Vertices of a rectangle with its corners cut to quarter-circle arcs,
/// approximated with short segments (`WindowShape` only takes line segments).
List<native.Point> _roundedRectanglePoints(
  double width,
  double height,
  double radius,
) {
  const segmentsPerCorner = 8;
  final points = <native.Point>[];
  void arc(double centerX, double centerY, double startDeg, double endDeg) {
    for (var i = 0; i <= segmentsPerCorner; i++) {
      final t =
          (startDeg + (endDeg - startDeg) * i / segmentsPerCorner) *
          (3.14159265358979323846 / 180);
      points.add(
        native.Point(
          x: centerX + radius * math.cos(t),
          y: centerY + radius * math.sin(t),
        ),
      );
    }
  }

  arc(width - radius, radius, -90, 0);
  arc(width - radius, height - radius, 0, 90);
  arc(radius, height - radius, 90, 180);
  arc(radius, radius, 180, 270);
  return points;
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
  window.title =
      'HiZip · ${translateAppText('操作信息', AppSettings.instance.locale.languageCode)}';
}

void configureSettingsWindow() {
  _window!
    ..title =
        'HiZip · ${translateAppText('设置', AppSettings.instance.locale.languageCode)}'
    ..minimumSize = const Size(440, 360).toNative();
  _window!.setSize(const Size(600, 440).toNative(), false);
  _window!.center();
}

void setAuxiliaryWindowTitle(String title) {
  _window?.title = title;
}

void configurePropertiesWindow() {
  _window!.minimumSize = const Size(320, 340).toNative();
  _window!.setSize(const Size(380, 600).toNative(), false);
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
  window.minimumSize = const Size(380, 280).toNative();
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
  window.setSize(Size(width, height).toNative(), false);
  if (parent.isEmpty) {
    window.center();
  } else {
    window.bounds = Rect.fromLTWH(
      (parent['x'] as num).toDouble() +
          ((parent['width'] as num).toDouble() - width) / 2,
      (parent['y'] as num).toDouble() + (parentHeight - height) / 2,
      width,
      height,
    ).toNative();
  }
}
