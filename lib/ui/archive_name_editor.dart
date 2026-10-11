import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'app_localizations.dart';
import 'desktop_widgets.dart';

class ArchiveNameEditor extends StatefulWidget {
  const ArchiveNameEditor({
    super.key,
    required this.name,
    required this.directory,
    required this.onRename,
    required this.onCancel,
    this.onDismiss,
    this.compact = false,
    this.textAlign = TextAlign.start,
    this.fontSize = 12,
  });
  final String name;
  final bool directory, compact;
  final Future<void> Function(String) onRename;
  final VoidCallback onCancel;
  final VoidCallback? onDismiss;
  final TextAlign textAlign;
  final double fontSize;
  @override
  State<ArchiveNameEditor> createState() => _ArchiveNameEditorState();
}

class _ArchiveNameEditorState extends State<ArchiveNameEditor> {
  late final input = TextEditingController(text: widget.name);
  late final focus = FocusNode(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        if (!saving) cancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  bool saving = false, cancelled = false;
  String? error;
  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (mounted &&
          !widget.compact &&
          !focus.hasFocus &&
          !saving &&
          !cancelled) {
        dismiss();
      }
    });
    final extension = widget.directory ? '' : p.extension(widget.name);
    final stem = widget.name.length - extension.length;
    input.selection = TextSelection(
      baseOffset: 0,
      extentOffset: stem > 0 ? stem : widget.name.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !cancelled) focus.requestFocus();
    });
  }

  void cancel() {
    if (saving || cancelled) return;
    cancelled = true;
    widget.onCancel();
  }

  void dismiss() {
    if (saving || cancelled) return;
    cancelled = true;
    (widget.onDismiss ?? widget.onCancel)();
  }

  Future<void> submit() async {
    if (saving || cancelled) return;
    final name = input.text.trim();
    if (name == widget.name) {
      cancel();
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (name.isEmpty) throw StateError('请输入有效的名称，不能包含路径分隔符。');
      await widget.onRename(name);
    } catch (failure) {
      if (mounted) {
        setState(() {
          saving = false;
          error = failure.toString().replaceFirst('Bad state: ', '');
        });
        focus.requestFocus();
      }
    }
  }

  @override
  void dispose() {
    cancelled = true;
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget field({
      EdgeInsets padding = const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
    }) => DesktopTextField(
      key: const ValueKey('rename-entry-name'),
      groupId: this,
      controller: input,
      focusNode: focus,
      autofocus: true,
      readOnly: saving,
      textAlign: widget.textAlign,
      fontSize: widget.fontSize,
      contentPadding: padding,
      onSubmitted: (_) => submit(),
      onTapOutside: widget.compact ? null : (_) => dismiss(),
      onChanged: (_) {
        if (error != null) setState(() => error = null);
      },
    );
    if (!widget.compact) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final preferredHeight = desktopInputHeight(
            context,
            fontSize: widget.fontSize,
          );
          final height = constraints.constrainHeight(preferredHeight);
          // Fit the editor into the existing row instead of resizing the list.
          final verticalPadding = ((height - (preferredHeight - 12)) / 2).clamp(
            1.0,
            6.0,
          );
          return SizedBox(
            height: height,
            child: Center(
              child: Tooltip(
                message: error == null ? '' : appText(context, error!),
                child: field(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: verticalPadding,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    return PopScope(
      canPop: !saving,
      child: DesktopDialog(
        title: const AppText('重命名'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppText(error!, style: TextStyle(color: colors.error)),
              ),
          ],
        ),
        actions: [
          DesktopButton(
            onPressed: saving ? null : cancel,
            child: const AppText('取消'),
          ),
          DesktopButton(
            primary: true,
            onPressed: saving ? null : submit,
            child: AppText(saving ? '正在保存…' : '重命名'),
          ),
        ],
      ),
    );
  }
}
