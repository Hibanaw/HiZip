import '../services/platform_files.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/archive_create_options.dart';
import '../models/archive_formats.dart';
import '../services/app_settings.dart';
import '../services/archive_service.dart';
import '../services/desktop_integration.dart';
import '../services/finder_compression.dart';
import '../services/task_windows.dart';
import 'app_localizations.dart';
import 'archive_name_editor.dart';
import 'archive_security_dialogs.dart';
import 'desktop_widgets.dart';
import 'extraction_options_dialog.dart';

Future<T?> showAuxiliaryDialog<T>({
  required BuildContext context,
  required AppSettings settings,
  required String kind,
  required Map<String, dynamic> data,
  required WidgetBuilder builder,
  required T? Function(Map<String, dynamic>) decodeResult,
  AuxiliaryDialogAction? onAction,
  bool barrierDismissible = true,
}) async {
  if (settings.separateWindows && MediaQuery.sizeOf(context).width >= 800) {
    final transport = AuxiliaryDialogWindowTransport(settings: settings);
    try {
      final response = await transport.show(kind, data, onAction: onAction);
      if (response.shown) {
        return response.result == null ? null : decodeResult(response.result!);
      }
    } finally {
      transport.dispose();
    }
  }
  if (!context.mounted) return null;
  return showAppDialog<T>(
    context: context,
    languageCode: settings.locale.languageCode,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}

/// All separate dialog engines render the same widgets as their inline routes.
Widget buildAuxiliaryDialog(
  BuildContext context,
  String kind,
  Map<String, dynamic> data,
  AuxiliaryDialogAction action,
  Map<String, dynamic> selection,
) => switch (kind) {
  'create' => ArchiveCreateDialog(
    format: data['format'] as String,
    aesAvailable: data['aesAvailable'] as bool,
    empty: data['empty'] as bool,
    initialLevel: data['initialLevel'] as int,
    initialNestInFolder: data['initialNestInFolder'] as bool,
    initialPaths: List<String>.from(data['paths'] as List),
    initialOutputPath: data['output'] as String,
    formats: Map<String, String>.from(data['formats'] as Map),
    selectContents: ({bool foldersOnly = false}) => DesktopIntegration()
        .selectCompressionContents(foldersOnly: foldersOnly),
    suggestOutputPath: availableFinderArchivePath,
    selectOutputPath: selectArchiveOutputPath,
    onSelectionConfirmed: (paths, output) =>
        selection.addAll({'paths': paths, 'output': output}),
  ),
  'password' => ArchivePasswordDialog(
    onUnlock: (password) async {
      await action('unlock', {'password': password});
    },
  ),
  'extraction' => const ExtractionOptionsDialog(),
  'transfer' => ArchiveTransferDialog(
    move: data['move'] as bool,
    folders: List<String>.from(data['folders'] as List),
  ),
  'rename' => ArchiveNameEditor(
    name: data['name'] as String,
    directory: data['directory'] as bool,
    compact: true,
    onRename: (name) async {
      await action('rename', {'name': name});
      if (context.mounted) Navigator.pop(context, true);
    },
    onCancel: () => Navigator.pop(context),
  ),
  'entryName' => EntryNameDialog(
    title: data['title'] as String,
    initialName: data['name'] as String,
  ),
  _ => throw StateError('Unknown auxiliary dialog: $kind'),
};

Map<String, dynamic>? encodeAuxiliaryDialogResult(
  String kind,
  Object? result,
  Map<String, dynamic> selection,
) {
  if (result == null) return null;
  if (result is ArchiveCreateOptions) {
    return {...selection, 'options': result.toJson()};
  }
  if (result is ExtractionConflictPolicy) return {'value': result.name};
  return {'value': result};
}

Future<String?> selectArchiveOutputPath(String path, String format) async {
  final target = await getSaveLocation(
    suggestedName: path.isEmpty ? 'Archive.$format' : p.basename(path),
    initialDirectory: path.isEmpty ? null : p.dirname(path),
    acceptedTypeGroups: [
      XTypeGroup(label: writableArchiveFormats[format]!, extensions: [format]),
    ],
  );
  return target?.path;
}

class ArchiveTransferDialog extends StatelessWidget {
  const ArchiveTransferDialog({
    super.key,
    required this.move,
    required this.folders,
  });
  final bool move;
  final List<String> folders;
  @override
  Widget build(BuildContext context) => DesktopDialog(
    title: AppText(move ? '移动到…' : '复制到…'),
    content: SizedBox(
      width: 420,
      height: 260,
      child: ListView.builder(
        itemCount: folders.length,
        itemExtent: 36,
        itemBuilder: (_, index) => DesktopButton(
          key: ValueKey('transfer-folder-${folders[index]}'),
          flat: true,
          onPressed: () => Navigator.pop(context, folders[index]),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: folders[index].isEmpty
                    ? const AppText('压缩包根目录')
                    : Text(folders[index], overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      DesktopButton(
        onPressed: () => Navigator.pop(context),
        child: const AppText('取消'),
      ),
    ],
  );
}

class EntryNameDialog extends StatefulWidget {
  const EntryNameDialog({
    super.key,
    required this.title,
    required this.initialName,
  });
  final String title, initialName;
  @override
  State<EntryNameDialog> createState() => _EntryNameDialogState();
}

class _EntryNameDialogState extends State<EntryNameDialog> {
  late final input = TextEditingController(text: widget.initialName);
  void submit() => Navigator.pop(context, input.text);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DesktopDialog(
    title: AppText(widget.title),
    content: DesktopTextField(
      key: const ValueKey('inline-entry-name'),
      controller: input,
      autofocus: true,
      onSubmitted: (_) => submit(),
    ),
    actions: [
      DesktopButton(
        onPressed: () => Navigator.pop(context),
        child: const AppText('取消'),
      ),
      DesktopButton(
        primary: true,
        onPressed: submit,
        child: const AppText('创建'),
      ),
    ],
  );
}
