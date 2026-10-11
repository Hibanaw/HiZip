import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A mouse marquee that starts only in the empty part of a file viewport.
class FileSelectionArea extends StatefulWidget {
  const FileSelectionArea({
    super.key,
    required this.child,
    required this.scrollController,
    required this.selectedPaths,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    this.enabled = true,
  });

  final Widget child;
  final ScrollController scrollController;
  final Set<String> selectedPaths;
  final VoidCallback onStart, onEnd;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  @override
  State<FileSelectionArea> createState() => _FileSelectionAreaState();
}

class _FileSelectionAreaState extends State<FileSelectionArea> {
  final items = <_FileSelectionItemState>{};
  final bounds = <String, List<Rect>>{};
  Set<String> original = {}, base = {}, lastSelection = {};
  Offset? origin, pointer;
  int? pointerId;
  bool dragging = false;
  Timer? scrollTimer;

  RenderBox get box => context.findRenderObject()! as RenderBox;
  Offset get scrollOffset {
    final controller = widget.scrollController;
    if (!controller.hasClients) return Offset.zero;
    return axisDirectionToAxis(controller.position.axisDirection) ==
            Axis.vertical
        ? Offset(0, controller.offset)
        : Offset(controller.offset, 0);
  }

  List<Rect> itemBounds(_FileSelectionItemState item) {
    final regions = item.widget.hitRegions;
    final contexts = regions == null
        ? [item.context]
        : regions.map((key) => key.currentContext).whereType<BuildContext>();
    return [
      for (final context in contexts)
        if (context.findRenderObject() case final RenderBox render)
          Rect.fromPoints(
            box.globalToLocal(render.localToGlobal(Offset.zero)),
            box.globalToLocal(
              render.localToGlobal(render.size.bottomRight(Offset.zero)),
            ),
          ),
    ];
  }

  void down(PointerDownEvent event) {
    if (!widget.enabled ||
        pointerId != null ||
        event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    final local = box.globalToLocal(event.position);
    // Files keep their normal click, activation and drag handlers.
    if (items.any(
      (item) => itemBounds(item).any((rect) => rect.contains(local)),
    )) {
      return;
    }
    bool overScrollbar = false;
    void inspect(Element element) {
      final widget = element.widget;
      if (widget is CustomPaint) {
        final render = element.findRenderObject()! as RenderBox;
        final local = render.globalToLocal(event.position);
        for (final painter in [widget.painter, widget.foregroundPainter]) {
          if (painter is ScrollbarPainter) {
            overScrollbar |= painter.hitTestInteractive(local, event.kind);
          }
        }
      }
      if (!overScrollbar) element.visitChildren(inspect);
    }

    (context as Element).visitChildren(inspect);
    if (overScrollbar) return;
    pointerId = event.pointer;
    pointer = local;
    origin = local + scrollOffset;
    original = Set.of(widget.selectedPaths);
    final keys = HardwareKeyboard.instance;
    base = keys.isMetaPressed || keys.isControlPressed || keys.isShiftPressed
        ? Set.of(original)
        : {};
    lastSelection = Set.of(original);
    bounds.clear();
    rememberBounds();
  }

  void rememberBounds() {
    for (final item in items) {
      final path = item.widget.path;
      if (path != null) {
        bounds[path] = [
          for (final rect in itemBounds(item)) rect.shift(scrollOffset),
        ];
      }
    }
  }

  void move(PointerMoveEvent event) {
    if (event.pointer != pointerId) return;
    if (!widget.enabled) {
      finish(cancelled: true);
      return;
    }
    pointer = box.globalToLocal(event.position);
    if (!dragging && (pointer! + scrollOffset - origin!).distance <= kPanSlop) {
      return;
    }
    if (!dragging) {
      dragging = true;
      HardwareKeyboard.instance.addHandler(key);
      widget.onStart();
    }
    updateSelection();
    if (scrollDelta != 0) {
      scrollTimer ??= Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => autoScroll(),
      );
    } else {
      scrollTimer?.cancel();
      scrollTimer = null;
    }
  }

  Offset get clampedPointer => Offset(
    pointer!.dx.clamp(0, box.size.width),
    pointer!.dy.clamp(0, box.size.height),
  );

  void updateSelection() {
    if (!mounted || !dragging) return;
    rememberBounds();
    final rect = Rect.fromPoints(origin!, clampedPointer + scrollOffset);
    final selection = {
      ...base,
      for (final entry in bounds.entries)
        if (entry.value.any(rect.overlaps)) entry.key,
    };
    if (selection.length != lastSelection.length ||
        !selection.containsAll(lastSelection)) {
      lastSelection = selection;
      widget.onChanged(selection);
    }
    setState(() {});
  }

  double get scrollDelta {
    if (!dragging || !widget.scrollController.hasClients) return 0;
    final vertical =
        axisDirectionToAxis(widget.scrollController.position.axisDirection) ==
        Axis.vertical;
    final position = vertical ? pointer!.dy : pointer!.dx;
    final extent = vertical ? box.size.height : box.size.width;
    const edge = 28.0;
    if (position < edge) return -12 * ((edge - position) / edge).clamp(0, 1);
    if (position > extent - edge) {
      return 12 * ((position - extent + edge) / edge).clamp(0, 1);
    }
    return 0;
  }

  void autoScroll() {
    if (!widget.enabled) {
      finish(cancelled: true);
      return;
    }
    final controller = widget.scrollController;
    if (!controller.hasClients) return;
    final next = (controller.offset + scrollDelta).clamp(
      controller.position.minScrollExtent,
      controller.position.maxScrollExtent,
    );
    if (next == controller.offset) {
      scrollTimer?.cancel();
      scrollTimer = null;
      return;
    }
    controller.jumpTo(next);
    WidgetsBinding.instance.addPostFrameCallback((_) => updateSelection());
  }

  bool key(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      finish(cancelled: true);
      return true;
    }
    return false;
  }

  void finish({bool cancelled = false}) {
    if (dragging) {
      HardwareKeyboard.instance.removeHandler(key);
      if (cancelled) widget.onChanged(original);
      widget.onEnd();
    }
    scrollTimer?.cancel();
    scrollTimer = null;
    pointerId = null;
    bounds.clear();
    setState(() => dragging = false);
  }

  @override
  void dispose() {
    scrollTimer?.cancel();
    if (dragging) HardwareKeyboard.instance.removeHandler(key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FileSelectionScope(
    area: this,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: down,
      onPointerMove: move,
      onPointerUp: (event) {
        if (event.pointer == pointerId) finish();
      },
      onPointerCancel: (event) {
        if (event.pointer == pointerId) finish(cancelled: true);
      },
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (_) {
          if (dragging) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => updateSelection(),
            );
          }
          return false;
        },
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            widget.child,
            if (dragging)
              Positioned.fromRect(
                rect: Rect.fromPoints(origin! - scrollOffset, clampedPointer),
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: const ValueKey('file-selection-marquee'),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: .65),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _FileSelectionScope extends InheritedWidget {
  const _FileSelectionScope({required this.area, required super.child});
  final _FileSelectionAreaState area;
  @override
  bool updateShouldNotify(_FileSelectionScope oldWidget) =>
      area != oldWidget.area;
}

/// Registers only mounted file items, keeping large directories lazy.
class FileSelectionItem extends StatefulWidget {
  const FileSelectionItem({
    super.key,
    required this.path,
    required this.child,
    this.hitRegions,
  });
  // Controls such as "expand remaining files" block the marquee without being
  // included in the selected file paths.
  final String? path;
  final List<GlobalKey>? hitRegions;
  final Widget child;
  @override
  State<FileSelectionItem> createState() => _FileSelectionItemState();
}

class _FileSelectionItemState extends State<FileSelectionItem> {
  _FileSelectionAreaState? area;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    area?.items.remove(this);
    area = context
        .dependOnInheritedWidgetOfExactType<_FileSelectionScope>()
        ?.area;
    area?.items.add(this);
  }

  @override
  void deactivate() {
    area?.items.remove(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    area?.items.add(this);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
