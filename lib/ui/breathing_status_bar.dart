import 'package:flutter/material.dart';

/// Status bar that pulses like a breathing light while [active] and reports
/// taps so the user can acknowledge what it is showing.
class BreathingStatusBar extends StatefulWidget {
  const BreathingStatusBar({
    super.key,
    required this.active,
    required this.tint,
    required this.decoration,
    required this.height,
    required this.padding,
    required this.onTap,
    required this.child,
  });
  final bool active;
  final Color tint;
  final BoxDecoration decoration;
  final double height;
  final EdgeInsetsGeometry padding;
  final VoidCallback onTap;
  final Widget child;
  @override
  State<BreathingStatusBar> createState() => _BreathingStatusBarState();
}

class _BreathingStatusBarState extends State<BreathingStatusBar>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final curve = CurvedAnimation(
    parent: controller,
    curve: Curves.easeInOut,
  );

  @override
  @override
  void didUpdateWidget(BreathingStatusBar old) {
    super.didUpdateWidget(old);
    sync();
  }

  bool reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion = MediaQuery.disableAnimationsOf(context);
    sync();
  }

  void sync() {
    if (widget.active && reduceMotion) {
      // Honour the system "reduce motion" setting: a steady tint, no pulse.
      controller.stop();
      controller.value = 1;
    } else if (widget.active) {
      if (!controller.isAnimating) controller.repeat(reverse: true);
    } else if (controller.isAnimating || controller.value != 0) {
      controller.stop();
      controller.value = 0;
    }
  }

  @override
  void dispose() {
    curve.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.active ? SystemMouseCursors.click : MouseCursor.defer,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.active ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: curve,
        child: widget.child,
        builder: (_, child) {
          final base = widget.decoration.color ?? Colors.transparent;
          return Container(
            height: widget.height,
            padding: widget.padding,
            decoration: widget.decoration.copyWith(
              color: Color.lerp(
                base,
                widget.tint.withValues(alpha: .28),
                curve.value,
              ),
            ),
            child: child,
          );
        },
      ),
    ),
  );
}
