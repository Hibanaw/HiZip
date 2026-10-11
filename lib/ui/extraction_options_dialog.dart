import 'package:flutter/material.dart';

import '../services/archive_service.dart';
import 'app_localizations.dart';
import 'desktop_widgets.dart';

class ExtractionOptionsDialog extends StatefulWidget {
  const ExtractionOptionsDialog({super.key});
  @override
  State<ExtractionOptionsDialog> createState() =>
      _ExtractionOptionsDialogState();
}

class _ExtractionOptionsDialogState extends State<ExtractionOptionsDialog> {
  ExtractionConflictPolicy policy = ExtractionConflictPolicy.rename;
  @override
  Widget build(BuildContext context) => DesktopDialog(
    title: const AppText('解压选项'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppText('遇到同名项目时'),
          const SizedBox(height: 8),
          DesktopSelect<ExtractionConflictPolicy>(
            key: const ValueKey('extraction-conflict-policy'),
            value: policy,
            items: const {
              '自动重命名': ExtractionConflictPolicy.rename,
              '每次询问': ExtractionConflictPolicy.ask,
              '覆盖': ExtractionConflictPolicy.overwrite,
              '跳过': ExtractionConflictPolicy.skip,
            },
            onChanged: (value) => setState(() => policy = value),
          ),
          const SizedBox(height: 16),
          const AppText('覆盖、跳过或询问时，同名文件夹合并，内部文件按所选策略处理。自动重命名会保留独立副本。'),
        ],
      ),
    ),
    actions: [
      DesktopButton(
        onPressed: () => Navigator.pop(context),
        child: const AppText('取消'),
      ),
      DesktopButton(
        primary: true,
        onPressed: () => Navigator.pop(context, policy),
        child: const AppText('解压'),
      ),
    ],
  );
}
