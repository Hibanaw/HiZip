import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../models/archive_create_options.dart';
import 'app_localizations.dart';
import 'desktop_widgets.dart';

class ArchivePasswordDialog extends StatefulWidget {
  const ArchivePasswordDialog({super.key, required this.onUnlock});
  final Future<void> Function(String) onUnlock;
  @override
  State<ArchivePasswordDialog> createState() => _ArchivePasswordDialogState();
}

class _ArchivePasswordDialogState extends State<ArchivePasswordDialog> {
  final password = TextEditingController();
  bool working = false;
  String? error;
  Future<void> unlock() async {
    if (working || password.text.isEmpty) return;
    setState(() {
      working = true;
      error = null;
    });
    try {
      await widget.onUnlock(password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          working = false;
          error = '无法解锁：密码错误、格式不受支持或文件已损坏。';
        });
      }
    }
  }

  @override
  void dispose() {
    password.clear();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !working,
    child: DesktopDialog(
      title: const AppText('输入压缩包密码'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DesktopTextField(
              key: const ValueKey('archive-password'),
              controller: password,
              obscureText: true,
              autofocus: true,
              enabled: !working,
              onSubmitted: (_) => unlock(),
              label: const AppText('密码'),
            ),
            const SizedBox(height: 12),
            const AppText('密码仅在当前会话中使用，不会保存到设置。'),
            if (error != null)
              AppText(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        DesktopButton(
          onPressed: working ? null : () => Navigator.of(context).pop(false),
          child: const AppText('取消'),
        ),
        DesktopButton(
          primary: true,
          onPressed: working ? null : unlock,
          child: AppText(working ? '正在解锁…' : '解锁'),
        ),
      ],
    ),
  );
}

class ArchiveCreateDialog extends StatefulWidget {
  const ArchiveCreateDialog({
    super.key,
    required this.format,
    required this.aesAvailable,
    required this.initialLevel,
    this.empty = false,
    this.formats = const {},
    this.initialNestInFolder = false,
    this.initialPaths = const [],
    this.initialOutputPath = '',
    this.selectContents,
    this.selectOutputPath,
    this.formatDisplayPath,
    this.suggestOutputPath,
    this.onSelectionConfirmed,
  });
  final String format;
  final bool aesAvailable, empty;
  final int initialLevel;
  final Map<String, String> formats;
  final bool initialNestInFolder;
  final List<String> initialPaths;
  final String initialOutputPath;
  final Future<List<String>> Function({bool foldersOnly})? selectContents;
  final Future<String?> Function(String path, String format)? selectOutputPath;
  final String Function(String path)? formatDisplayPath;
  final Future<String> Function(List<String> paths, String format)?
  suggestOutputPath;
  final void Function(List<String> paths, String outputPath)?
  onSelectionConfirmed;
  @override
  State<ArchiveCreateDialog> createState() => _ArchiveCreateDialogState();
}

class _ArchiveCreateDialogState extends State<ArchiveCreateDialog> {
  final password = TextEditingController(),
      confirm = TextEditingController(),
      comment = TextEditingController();
  late final output = TextEditingController(text: widget.initialOutputPath);
  final displayOutput = TextEditingController();
  void updateDisplayOutput() {
    displayOutput.text =
        widget.formatDisplayPath?.call(output.text) ?? output.text;
  }

  late List<String> paths = List.of(widget.initialPaths);
  bool picking = false, customOutput = false, customNesting = false;
  bool overwriteAllowed = false;
  bool get fullConfiguration => widget.onSelectionConfirmed != null;
  bool split = false;
  late String format = widget.format;
  late bool nestInFolder = widget.initialNestInFolder;
  int volumeMiB = 100;
  late int level = widget.initialLevel;
  bool encrypted = false;
  String method = 'deflate';
  String? error;
  bool get zip => format == 'zip';
  bool get adjustableLevel => zip || format == '7z';
  @override
  void initState() {
    super.initState();
    output.addListener(updateDisplayOutput);
    updateDisplayOutput();
    if (fullConfiguration && paths.isNotEmpty && output.text.isEmpty) {
      updateSuggestedOutput();
    }
  }

  Future<void> updateSuggestedOutput() async {
    setState(() => picking = true);
    try {
      final suggested = await widget.suggestOutputPath!(List.of(paths), format);
      if (mounted) setState(() => output.text = suggested);
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void changeFormat(String value) {
    setState(() {
      if (output.text.endsWith('.$format')) {
        output.text =
            '${output.text.substring(0, output.text.length - format.length)}$value';
      }
      format = value;
      overwriteAllowed = false;
      encrypted = false;
      split = false;
      method = 'deflate';
      password.clear();
      confirm.clear();
      error = null;
    });
    if (fullConfiguration && !customOutput && paths.isNotEmpty) {
      updateSuggestedOutput();
    }
  }

  Future<void> pickContents({bool foldersOnly = false}) async {
    setState(() => picking = true);
    try {
      final selected = await widget.selectContents!(foldersOnly: foldersOnly);
      if (!mounted || selected.isEmpty) return;
      final updated = {...paths, ...selected}.toList();
      final suggested = customOutput
          ? output.text
          : await widget.suggestOutputPath!(updated, format);
      if (!mounted) return;
      setState(() {
        paths = updated;
        output.text = suggested;
        if (!customNesting) nestInFolder = paths.length > 1;
        error = null;
      });
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> pickOutput() async {
    setState(() => picking = true);
    try {
      final selected = await widget.selectOutputPath!(output.text, format);
      if (!mounted || selected == null) return;
      setState(() {
        output.text = selected;
        customOutput = true;
        overwriteAllowed = true;
        error = null;
      });
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void create() {
    if (fullConfiguration && !widget.empty && paths.isEmpty) {
      setState(() => error = '请选择要压缩的文件或文件夹。');
      return;
    }
    if (fullConfiguration && output.text.isEmpty) {
      setState(() => error = '请选择压缩包的保存位置。');
      return;
    }
    if (utf8.encode(comment.text).length > 65535) {
      setState(() => error = '注释不能超过 65535 个 UTF-8 字节。');
      return;
    }
    if (encrypted && (password.text.isEmpty || password.text != confirm.text)) {
      setState(() => error = '密码不能为空，两次输入必须一致。');
      return;
    }
    widget.onSelectionConfirmed?.call(List.of(paths), output.text);
    Navigator.of(context).pop(
      ArchiveCreateOptions(
        format: format,
        nestInFolder: !widget.empty && nestInFolder,
        volumeSize: split ? volumeMiB * 1024 * 1024 : 0,
        comment: zip ? comment.text : '',
        password: encrypted ? password.text : '',
        encryption: encrypted ? 'aes256' : 'none',
        zipCompression: method,
        compressionLevel: adjustableLevel ? level : 6,
        // Only the save picker can confirm replacement of an existing target.
        // Changing formats or using an automatic name invalidates that consent.
        overwrite: !fullConfiguration || overwriteAllowed,
      ),
    );
  }

  @override
  void dispose() {
    password.clear();
    confirm.clear();
    comment.dispose();
    output.removeListener(updateDisplayOutput);
    output.dispose();
    displayOutput.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DesktopDialog(
    title: AppText(fullConfiguration ? '创建压缩包' : '压缩选项'),
    content: SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fullConfiguration) ...[
              if (!widget.empty) ...[
                const AppText('压缩内容'),
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('create-contents'),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.theme.colors.border),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  constraints: const BoxConstraints(maxHeight: 116),
                  child: paths.isEmpty
                      ? const AppText('尚未选择文件或文件夹')
                      : SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final path in paths)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Tooltip(
                                        message:
                                            widget.formatDisplayPath?.call(
                                              path,
                                            ) ??
                                            path,
                                        child: Text(
                                          widget.formatDisplayPath?.call(
                                                path,
                                              ) ??
                                              path,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DesktopIconButton(
                                      tooltip: '移除',
                                      icon: const Icon(Icons.close, size: 14),
                                      onPressed: picking
                                          ? null
                                          : () => setState(() {
                                              paths.remove(path);
                                              if (!customNesting) {
                                                nestInFolder = paths.length > 1;
                                              }
                                            }),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DesktopButton(
                      key: const ValueKey('create-select-contents'),
                      onPressed: picking ? null : pickContents,
                      child: const AppText('选择文件或文件夹…'),
                    ),
                    if (Theme.of(context).platform != TargetPlatform.macOS)
                      DesktopButton(
                        key: const ValueKey('create-select-folders'),
                        onPressed: picking
                            ? null
                            : () => pickContents(foldersOnly: true),
                        child: const AppText('添加文件夹…'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              const AppText('保存位置'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DesktopTextField(
                      key: const ValueKey('create-output-path'),
                      controller: displayOutput,
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DesktopButton(
                    key: const ValueKey('create-select-output'),
                    onPressed: picking ? null : pickOutput,
                    child: const AppText('选择…'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (widget.formats.isEmpty)
              Text(format.toUpperCase())
            else ...[
              const AppText('压缩格式'),
              const SizedBox(height: 8),
              DesktopSelect<String>(
                key: const ValueKey('create-format'),
                value: format,
                items: {
                  for (final entry in widget.formats.entries)
                    entry.value: entry.key,
                },
                onChanged: picking ? null : changeFormat,
              ),
            ],
            if (!widget.empty) ...[
              const SizedBox(height: 12),
              FCheckbox(
                key: const ValueKey('create-nested-folder'),
                label: const AppText('嵌套与压缩包同名的文件夹'),
                value: nestInFolder,
                onChange: (value) => setState(() {
                  nestInFolder = value;
                  customNesting = true;
                }),
              ),
            ],
            if (zip) ...[
              const SizedBox(height: 12),
              const AppText('压缩算法'),
              const SizedBox(height: 8),
              DesktopSelect<String>(
                key: const ValueKey('zip-method'),
                value: method,
                items: const {'Deflate': 'deflate', 'Store（不压缩）': 'store'},
                onChanged: (value) => setState(() => method = value),
              ),
            ],
            if (adjustableLevel) ...[
              const SizedBox(height: 16),
              AppText('压缩等级：$level'),
              DesktopSlider(
                value: level.toDouble(),
                min: 0,
                max: 9,
                divisions: 9,
                onChanged: zip && method == 'store'
                    ? null
                    : (value) => setState(() => level = value.round()),
              ),
            ],
            if (zip && !widget.empty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: FCheckbox(
                  key: const ValueKey('zip-encryption'),
                  label: const AppText('ZIP AES-256 加密'),
                  value: encrypted,
                  enabled: widget.aesAvailable,
                  onChange: (value) => setState(() => encrypted = value),
                ),
              ),
            if (zip && !widget.aesAvailable) const AppText('当前引擎不支持 AES 加密。'),
            if (!zip) const AppText('此格式暂不支持加密压缩。'),
            if (encrypted) ...[
              const AppText('ZIP 加密不会隐藏文件名。加密压缩包目前只支持读取。'),
              const SizedBox(height: 12),
              DesktopTextField(
                key: const ValueKey('create-password'),
                controller: password,
                obscureText: true,
                label: const AppText('密码'),
              ),
              const SizedBox(height: 12),
              DesktopTextField(
                key: const ValueKey('confirm-password'),
                controller: confirm,
                obscureText: true,
                label: const AppText('确认密码'),
              ),
            ],
            if (zip) ...[
              const SizedBox(height: 16),
              DesktopTextField(
                key: const ValueKey('create-comment'),
                controller: comment,
                label: const AppText('压缩包注释'),
                maxLines: 3,
              ),
            ],
            if (zip || format == '7z') ...[
              const SizedBox(height: 16),
              FCheckbox(
                key: const ValueKey('split-volumes'),
                label: const AppText('创建连续分卷'),
                value: split,
                onChange: (value) => setState(() => split = value),
              ),
              if (split) ...[
                const SizedBox(height: 8),
                DesktopSelect<int>(
                  key: const ValueKey('volume-size'),
                  value: volumeMiB,
                  items: const {
                    '1 MiB': 1,
                    '10 MiB': 10,
                    '100 MiB': 100,
                    '500 MiB': 500,
                    '1 GiB': 1024,
                    '2 GiB': 2048,
                  },
                  onChanged: (value) => setState(() => volumeMiB = value),
                ),
                const SizedBox(height: 8),
                const AppText('连续分卷使用 .001、.002 等后缀，并附带校验清单。分卷压缩包只读。'),
              ],
            ],
            if (error != null)
              AppText(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      DesktopButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const AppText('取消'),
      ),
      DesktopButton(
        primary: true,
        onPressed: picking ? null : create,
        child: const AppText('创建'),
      ),
    ],
  );
}
