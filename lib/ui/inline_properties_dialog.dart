import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_settings.dart';
import '../services/task_windows.dart';
import 'app_localizations.dart';
import 'archive_app.dart';
import 'desktop_widgets.dart';

class InlinePropertiesDialog extends StatefulWidget {
  const InlinePropertiesDialog({
    super.key,
    required this.settings,
    required this.data,
    required this.onAction,
  });
  final AppSettings settings;
  final Map<String, dynamic> data;
  final PropertiesWindowAction onAction;

  @override
  State<InlinePropertiesDialog> createState() => _InlinePropertiesDialogState();
}

class _InlinePropertiesDialogState extends State<InlinePropertiesDialog> {
  final workspaceKey = GlobalKey<State<ArchiveWorkspace>>();
  bool closing = false;

  Future<void> close() async {
    if (closing) return;
    closing = true;
    try {
      final dynamic workspace = workspaceKey.currentState;
      if (workspace != null && await workspace.savePropertyDrafts() != true) {
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      closing = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: DesktopDialog(
          key: const ValueKey('inline-properties-dialog'),
          maxWidth: 600,
          title: Row(
            children: [
              const Expanded(child: AppText('属性')),
              DesktopIconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, size: 17),
                onPressed: close,
              ),
            ],
          ),
          actions: const [],
          content: SizedBox(
            width: double.infinity,
            height: (MediaQuery.sizeOf(context).height - 140).clamp(0, 620),
            child: ArchiveWorkspace(
              key: workspaceKey,
              settings: widget.settings,
              propertiesData: widget.data,
              propertiesAction: widget.onAction,
              enableNativeTransfers: false,
            ),
          ),
        ),
      ),
    ),
  );
}
