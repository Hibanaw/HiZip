import 'app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../models/task_feedback.dart';
import 'desktop_widgets.dart';

/// Shared content for native task windows and centered non-desktop panels.
class TaskFeedbackPanel extends StatelessWidget {
  const TaskFeedbackPanel({
    super.key,
    required this.data,
    required this.onAction,
    this.inWindow = false,
  });
  final TaskFeedback data;
  final ValueChanged<String> onAction;
  final bool inWindow;
  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('task-feedback'),
    width: 440,
    height: 216,
    child: inWindow
        ? panelContent(context)
        : FCard.raw(child: panelContent(context)),
  );

  Widget panelContent(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (data.running)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: FCircularProgress(
                      size: FCircularProgressSizeVariant.sm,
                    ),
                  )
                else
                  Icon(
                    data.error ? FIcons.circleAlert : FIcons.circleCheck,
                    size: 20,
                    color: data.error
                        ? Theme.of(context).colorScheme.error
                        : context.theme.colors.foreground,
                  ),
                const SizedBox(width: 12),
                Flexible(
                  child: AppText(
                    data.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (data.detail.isNotEmpty) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: data.running ? 36 : 104),
                child: SingleChildScrollView(
                  child: SelectableText(
                    appText(context, data.detail),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ),
            ],
            if (data.running) ...[
              const SizedBox(height: 12),
              Text(
                data.currentFile.isEmpty
                    ? appText(context, '当前文件')
                    : data.currentFile,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              _progress('当前文件', data.fileProgress, 'file-progress'),
              const SizedBox(height: 12),
              _progress('全部进度', data.progress, 'overall-progress'),
            ],
            if (data.actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in data.actions.entries)
                    DesktopButton(
                      primary: action.key == 'save',
                      onPressed: () => onAction(action.key),
                      child: AppText(action.value),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
  Widget _progress(String label, double? value, String key) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          AppText(label, style: const TextStyle(fontSize: 11)),
          AppText(
            value == null ? '正在处理…' : '${(value.clamp(0, 1) * 100).round()}%',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
      const SizedBox(height: 4),
      KeyedSubtree(
        key: ValueKey(key),
        child: value == null
            ? const FProgress()
            : FDeterminateProgress(value: value.clamp(0, 1)),
      ),
    ],
  );
}
