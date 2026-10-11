import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'app_localizations.dart';
import 'desktop_widgets.dart';

/// Retain failed or pending edits when the inspector switches to another item.
class ArchiveCommentDraft extends ChangeNotifier {
  final input = TextEditingController();
  bool editing = false, saving = false, expanded = false, _disposed = false;
  String? error;
  String _original = '';
  Future<void> Function(String, String)? _write;

  void begin(String comment, Future<void> Function(String, String) write) {
    if (editing || saving) return;
    input.text = _original = comment;
    input.selection = TextSelection.collapsed(offset: comment.length);
    _write = write;
    editing = true;
    error = null;
    notifyListeners();
  }

  void toggleExpanded() {
    expanded = !expanded;
    notifyListeners();
  }

  Future<void> save() async {
    if (!editing || saving || _disposed) return;
    final text = input.text;
    if (utf8.encode(text).length > 65535) {
      error = '注释不能超过 65535 个 UTF-8 字节。';
      notifyListeners();
      return;
    }
    if (text == _original) {
      editing = false;
      error = null;
      notifyListeners();
      return;
    }
    saving = true;
    error = null;
    notifyListeners();
    try {
      await _write!(text, _original);
      if (_disposed) return;
      editing = false;
      expanded = false;
    } catch (failure) {
      if (_disposed) return;
      error = failure.toString().replaceFirst('Bad state: ', '');
    } finally {
      if (!_disposed) {
        saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    input.dispose();
    super.dispose();
  }
}

class ArchiveCommentField extends StatelessWidget {
  const ArchiveCommentField({
    super.key,
    required this.comment,
    required this.writable,
    required this.busy,
    required this.draft,
    required this.onSave,
    this.presentEditor = true,
    this.fontSize = 11,
  });
  final String comment;
  final bool writable, busy;
  final bool presentEditor;
  final double fontSize;
  final ArchiveCommentDraft draft;
  final Future<void> Function(String, String) onSave;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) {
      final muted = context.theme.colors.mutedForeground;
      final style = TextStyle(fontSize: fontSize, height: 1.5);
      void edit() => draft.begin(comment, onSave);
      final editing = draft.editing && presentEditor;
      final canEdit = writable && !busy && presentEditor;
      return Container(
        key: const ValueKey('archive-comment-section'),
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: context.theme.colors.border, width: .5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 65,
                  child: AppText(
                    '注释',
                    style: TextStyle(fontSize: fontSize, color: muted),
                  ),
                ),
                if (comment.isEmpty && !editing)
                  Expanded(
                    child: InkWell(
                      key: const ValueKey('archive-comment-empty'),
                      onTap: canEdit ? edit : null,
                      child: AppText(
                        '暂无注释',
                        textAlign: TextAlign.right,
                        style: style,
                      ),
                    ),
                  ),
              ],
            ),
            if (editing) ...[
              const SizedBox(height: 6),
              TextFieldTapRegion(
                groupId: draft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DesktopTextField(
                      key: const ValueKey('archive-comment-input'),
                      groupId: draft,
                      controller: draft.input,
                      autofocus: true,
                      readOnly: draft.saving,
                      maxLines: null,
                      fontSize: fontSize,
                      onTapOutside: (_) => unawaited(draft.save()),
                    ),
                    if (draft.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: AppText(
                          draft.error!,
                          style: TextStyle(
                            fontSize: fontSize,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: DesktopButton(
                        key: const ValueKey('archive-comment-save'),
                        onPressed: draft.saving ? null : draft.save,
                        child: AppText(draft.saving ? '正在保存…' : '保存'),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, bounds) {
                  final painter = TextPainter(
                    text: TextSpan(
                      text: comment,
                      style: DefaultTextStyle.of(context).style.merge(style),
                    ),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    maxLines: 4,
                  )..layout(maxWidth: bounds.maxWidth);
                  final overflow = painter.didExceedMaxLines;
                  painter.dispose();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        key: const ValueKey('archive-comment-edit'),
                        onTap: canEdit ? edit : null,
                        child: Text(
                          comment,
                          key: const ValueKey('archive-comment-content'),
                          maxLines: draft.expanded ? null : 4,
                          overflow: draft.expanded
                              ? TextOverflow.clip
                              : TextOverflow.ellipsis,
                          style: style,
                        ),
                      ),
                      if (overflow)
                        Align(
                          alignment: Alignment.centerRight,
                          child: DesktopButton(
                            key: const ValueKey('archive-comment-expand'),
                            flat: true,
                            minHeight: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            tooltip: draft.expanded ? '收起' : '展开',
                            onPressed: draft.toggleExpanded,
                            child: AppText(draft.expanded ? '收起' : '…'),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      );
    },
  );
}
