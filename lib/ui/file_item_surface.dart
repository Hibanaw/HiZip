import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'desktop_widgets.dart';
import '../models/selection_highlight.dart';

/// Select on the first pointer down. Activate on the second pointer up without
/// waiting for a tap/double-tap gesture arena or an InkWell splash to finish.
class FileItemSurface extends StatefulWidget {
  const FileItemSurface({
    super.key,
    required this.name,
    required this.selected,
    required this.onSelect,
    required this.onActivate,
    required this.child,
    this.activeSelection = true,
    this.selectionHighlight = SelectionHighlight.neutral,
    this.joinPrevious = false,
    this.joinNext = false,
    this.dividerInset = 12,
    this.onDragStart,
    this.onDragPrepare,
  });
  final String name;
  final SelectionHighlight selectionHighlight;
  final bool selected, activeSelection;
  final bool joinPrevious, joinNext;
  final double dividerInset;
  final VoidCallback? onSelect, onActivate;
  final Widget child;
  final VoidCallback? onDragStart;
  final void Function(Rect)? onDragPrepare;
  @override
  State<FileItemSurface> createState() => _FileItemSurfaceState();
}

class _FileItemSurfaceState extends State<FileItemSurface> {
  Duration? lastTap;
  Offset? lastPosition, downPosition;
  bool doubleTap = false, primary = false, deferSelection = false;
  void down(PointerDownEvent event) {
    primary = event.buttons == kPrimaryMouseButton;
    if (!primary) return;
    downPosition = event.position;
    deferSelection = widget.selected;
    doubleTap =
        lastTap != null &&
        event.timeStamp - lastTap! <= kDoubleTapTimeout &&
        (event.position - lastPosition!).distance <= kDoubleTapSlop;
    if (!doubleTap && !widget.selected) widget.onSelect?.call();
    final render = context.findRenderObject();
    if (widget.onDragPrepare != null && render is RenderBox) {
      widget.onDragPrepare!(render.localToGlobal(Offset.zero) & render.size);
    }
  }

  void up(PointerUpEvent event) {
    if (!primary ||
        (event.position - downPosition!).distance > kDoubleTapSlop) {
      lastTap = null;
      primary = false;
      return;
    }
    if (doubleTap) {
      lastTap = null;
      widget.onActivate?.call();
    } else {
      if (deferSelection) widget.onSelect?.call();
      lastTap = event.timeStamp;
      lastPosition = event.position;
    }
    primary = false;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.name,
    selected: widget.selected,
    button: true,
    onTap: widget.onSelect,
    onLongPress: widget.onActivate,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: down,
      onPointerUp: up,
      onPointerMove: (event) {
        if (primary &&
            widget.onDragStart != null &&
            (event.position - downPosition!).distance > kPanSlop) {
          primary = false;
          doubleTap = false;
          lastTap = null;
          widget.onDragStart!();
        }
      },
      onPointerCancel: (_) {
        primary = false;
        lastTap = null;
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.vertical(
            top: widget.selected && widget.joinPrevious
                ? Radius.zero
                : const Radius.circular(5),
            bottom: widget.selected && widget.joinNext
                ? Radius.zero
                : const Radius.circular(5),
          ),
          color: widget.selected
              ? widget.activeSelection
                    ? fileSelectionBackground(
                        context,
                        widget.selectionHighlight,
                      )
                    : desktopColor(context, 0xffededee, 0xff333438)
              : Colors.transparent,
        ),
        child: widget.selected && widget.joinNext
            ? Stack(
                fit: StackFit.passthrough,
                children: [
                  widget.child,
                  Positioned(
                    left: widget.dividerInset,
                    right: widget.dividerInset,
                    bottom: 0,
                    child: ColoredBox(
                      key: ValueKey('selection-divider-${widget.name}'),
                      color:
                          widget.activeSelection &&
                              widget.selectionHighlight ==
                                  SelectionHighlight.blue
                          ? const Color(0x40ffffff)
                          : desktopColor(context, 0xffc9cacf, 0xff5c5d63),
                      child: const SizedBox(height: .5),
                    ),
                  ),
                ],
              )
            : widget.child,
      ),
    ),
  );
}
