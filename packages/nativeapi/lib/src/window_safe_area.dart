import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'host_services.dart';

/// Insets overlap the Flutter surface, in physical pixels. Native decoration
/// outside that surface has already been removed by the host.
class NativeWindowInsets {
  const NativeWindowInsets({
    required this.ready,
    required this.padding,
    required this.status,
  });
  factory NativeWindowInsets.fromMap(Map<Object?, Object?> data) =>
      NativeWindowInsets(
        ready: data['ready'] == true,
        padding: EdgeInsets.fromLTRB(
          (data['left']! as num).toDouble(),
          (data['top']! as num).toDouble(),
          (data['right']! as num).toDouble(),
          (data['bottom']! as num).toDouble(),
        ),
        status: (data['status']! as num).toInt(),
      );
  final bool ready;
  final EdgeInsets padding;
  final int status;
}

abstract final class NativeWindowSafeArea {
  static const _events = EventChannel('nativeapi/hizip/windowInsets');
  static final changes = _events.receiveBroadcastStream().map(
    (event) => NativeWindowInsets.fromMap(event as Map),
  );
  static Future<NativeWindowInsets?> current() async {
    final data = await NativePlatform.channel.invokeMapMethod<Object?, Object?>(
      'windowInsets',
    );
    return data == null ? null : NativeWindowInsets.fromMap(data);
  }

  /// Use authoritative OH surface overlap, without adding it to SDK padding.
  /// Android and other hosts continue using the Flutter engine's live metrics.
  static MediaQueryData mediaQuery(
    MediaQueryData data,
    NativeWindowInsets? native,
  ) {
    if (native == null || !native.ready) return data;
    final ratio = data.devicePixelRatio;
    double edge(double value) =>
        value.isFinite ? math.max(0, value / ratio) : 0;
    final padding = EdgeInsets.fromLTRB(
      edge(native.padding.left),
      edge(native.padding.top),
      edge(native.padding.right),
      edge(native.padding.bottom),
    );
    return data.copyWith(
      viewPadding: padding,
      padding: EdgeInsets.fromLTRB(
        math.max(0, padding.left - data.viewInsets.left),
        math.max(0, padding.top - data.viewInsets.top),
        math.max(0, padding.right - data.viewInsets.right),
        math.max(0, padding.bottom - data.viewInsets.bottom),
      ),
    );
  }
}

/// One safe boundary for the navigator, toolbar, drawers and dialogs.
/// No fixed status-bar height; updates on host events, metrics and resume.
class NativeSafeArea extends StatefulWidget {
  const NativeSafeArea({
    super.key,
    required this.child,
    required this.backgroundColor,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
  });
  final Widget child;
  final Color backgroundColor;
  final bool left, top, right, bottom;
  @override
  State<NativeSafeArea> createState() => _NativeSafeAreaState();
}

class _NativeSafeAreaState extends State<NativeSafeArea>
    with WidgetsBindingObserver {
  NativeWindowInsets? _insets;
  StreamSubscription<NativeWindowInsets>? _subscription;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    if (NativePlatform.isHarmonyOS) {
      WidgetsBinding.instance.addObserver(this);
      _subscription = NativeWindowSafeArea.changes.listen(
        (value) {
          _generation++;
          if (mounted) setState(() => _insets = value);
        },
        onError: (Object error) {
          if (mounted) setState(() => _insets = null);
        },
      );
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    try {
      final value = await NativeWindowSafeArea.current();
      if (mounted && generation == _generation) setState(() => _insets = value);
    } on PlatformException {
      if (mounted && generation == _generation) setState(() => _insets = null);
    } on MissingPluginException {
      if (mounted && generation == _generation) setState(() => _insets = null);
    }
  }

  @override
  void didChangeMetrics() => unawaited(_refresh());
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = NativeWindowSafeArea.mediaQuery(
      MediaQuery.of(context),
      _insets,
    );
    // Keep physical viewPadding available, but do not let nested SafeAreas
    // reapply edges the application deliberately allows content to extend into.
    final padding = data.padding.copyWith(
      left: widget.left ? data.padding.left : 0,
      top: widget.top ? data.padding.top : 0,
      right: widget.right ? data.padding.right : 0,
      bottom: widget.bottom ? data.padding.bottom : 0,
    );
    return ColoredBox(
      color: widget.backgroundColor,
      child: MediaQuery(
        data: data.copyWith(padding: padding),
        child: SafeArea(
          left: widget.left,
          top: widget.top,
          right: widget.right,
          bottom: widget.bottom,
          child: widget.child,
        ),
      ),
    );
  }
}
