import 'desktop_widgets.dart';

import 'package:flutter/material.dart';

class TouchFileDropController extends ChangeNotifier {
  final _targets = <_TouchFileDropTargetState>{};
  _TouchFileDropTargetState? _hovered;

  void update(Offset position) {
    _TouchFileDropTargetState? target;
    var smallest = double.infinity;
    for (final candidate in _targets) {
      final box = candidate.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      if (!(Offset.zero & box.size).contains(box.globalToLocal(position))) {
        continue;
      }
      final area = box.size.width * box.size.height;
      if (area < smallest) {
        target = candidate;
        smallest = area;
      }
    }
    if (target?.widget.accepts() == false) target = null;
    if (_hovered != target) {
      _hovered = target;
      notifyListeners();
    }
  }

  void drop(Offset position) {
    update(position);
    final target = _hovered;
    cancel();
    target?.widget.onDrop();
  }

  void cancel() {
    if (_hovered == null) return;
    _hovered = null;
    notifyListeners();
  }
}

class TouchFileDropTarget extends StatefulWidget {
  const TouchFileDropTarget({
    super.key,
    required this.controller,
    required this.accepts,
    required this.onDrop,
    required this.child,
  });

  final TouchFileDropController controller;
  final bool Function() accepts;
  final VoidCallback onDrop;
  final Widget child;

  @override
  State<TouchFileDropTarget> createState() => _TouchFileDropTargetState();
}

class _TouchFileDropTargetState extends State<TouchFileDropTarget> {
  @override
  void initState() {
    super.initState();
    widget.controller._targets.add(this);
  }

  @override
  void didUpdateWidget(TouchFileDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._targets.remove(this);
      widget.controller._targets.add(this);
    }
  }

  @override
  void dispose() {
    widget.controller._targets.remove(this);
    if (widget.controller._hovered == this) widget.controller._hovered = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (_, _) => Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (widget.controller._hovered == this)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('touch-drop-highlight'),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .12),
                  border: Border.all(
                    color: desktopAccentForeground(context),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
