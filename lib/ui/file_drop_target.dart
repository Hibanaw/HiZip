import 'desktop_widgets.dart';

import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class FileDropTarget extends StatefulWidget {
  const FileDropTarget({
    super.key,
    required this.child,
    required this.operation,
    required this.perform,
  });
  final Widget child;
  final DropOperation Function(DropOverEvent) operation;
  final Future<void> Function(PerformDropEvent) perform;
  @override
  State<FileDropTarget> createState() => _FileDropTargetState();
}

class _FileDropTargetState extends State<FileDropTarget> {
  bool hovering = false;
  @override
  Widget build(BuildContext context) => DropRegion(
    formats: const [Formats.fileUri],
    hitTestBehavior: HitTestBehavior.opaque,
    onDropOver: (event) {
      final operation = widget.operation(event);
      final accepted = operation != DropOperation.none;
      if (hovering != accepted) setState(() => hovering = accepted);
      return operation;
    },
    onDropLeave: (_) {
      if (hovering) setState(() => hovering = false);
    },
    onPerformDrop: (event) async {
      setState(() => hovering = false);
      await widget.perform(event);
    },
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (hovering)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
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
