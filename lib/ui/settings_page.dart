import '../models/app_language.dart';
import '../models/auxiliary_window_mode.dart';
import 'app_localizations.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../services/app_settings.dart';
import '../services/desktop_integration.dart';
import '../models/theme_accent.dart';
import '../models/archive_preferences.dart';
import 'desktop_widgets.dart';
import 'window_chrome.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    this.onClose,
    this.systemFrame = false,
  });
  final AppSettings settings;
  final VoidCallback? onClose;
  final bool systemFrame;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    settings.addListener(languageChanged);
    updateWindowTitle();
    WidgetsBinding.instance.addObserver(this);
  }

  void updateWindowTitle() {
    if (widget.systemFrame) {
      setAuxiliaryWindowTitle(
        'HiZip · ${translateAppText('设置', settings.locale.languageCode)}',
      );
    }
  }

  void languageChanged() {
    updateWindowTitle();
    if (mounted) setState(() {});
  }

  @override
  void didChangeLocales(List<Locale>? locales) => languageChanged();
  @override
  void dispose() {
    settings.removeListener(languageChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String section = 'appearance';
  bool associating = false;
  String? associationResult;
  bool get appearance => section == 'appearance';

  Widget encodingPicker({
    required String title,
    required String value,
    required bool creating,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      DesktopSelect<String>(
        value: value,
        items: {
          for (final option in archiveEncodings.entries)
            if (!creating || option.key != 'auto') option.value: option.key,
        },
        onChanged: settings.saving
            ? null
            : (value) {
                settings.setArchive(
                  ArchivePreferences(
                    readEncoding: creating
                        ? settings.archive.readEncoding
                        : value,
                    createEncoding: creating
                        ? value
                        : settings.archive.createEncoding,
                    compressionLevel: settings.archive.compressionLevel,
                  ),
                );
              },
      ),
    ],
  );
  String get systemLanguageCode =>
      resolveAppLocale(WidgetsBinding.instance.platformDispatcher.locale)
          .languageCode;

  AppSettings get settings => widget.settings;
  VoidCallback? get onClose => widget.onClose;
  @override
  Widget build(BuildContext context) => AppLanguageScope(
    languageCode: settings.locale.languageCode,
    child: settingsBody(context),
  );

  Widget settingsBody(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          (onClose ?? () => Navigator.pop(context))(),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        body: Column(
          children: [
            if (!widget.systemFrame)
              Container(
                height: windowChromeHeight(),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: context.theme.colors.muted,
                  border: Border(
                    bottom: BorderSide(color: context.theme.colors.border),
                  ),
                ),
                child: Row(
                  children: [
                    windowLeadingControls(),
                    if (onClose == null)
                      DesktopIconButton(
                        tooltip: '返回',
                        icon: const Icon(CupertinoIcons.chevron_left, size: 17),
                        onPressed: () => Navigator.pop(context),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: windowDragArea(
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: AppText(
                            '设置',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    windowTrailingControls(),
                  ],
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sidebarWidth =
                      !['zh', 'ja', 'ko'].contains(settings.locale.languageCode)
                      ? (constraints.maxWidth < 500 ? 152.0 : 170.0)
                      : (constraints.maxWidth < 500 ? 116.0 : 150.0);
                  final content = ListenableBuilder(
                    listenable: settings,
                    builder: (_, _) => SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: (constraints.maxWidth - 40).clamp(
                              0.0,
                              560.0,
                            ),
                            maxWidth: 560,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (appearance) ...[
                                const AppText(
                                  '外观',
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final mode in ThemeMode.values)
                                      DesktopButton(
                                        active: settings.themeMode == mode,
                                        onPressed: settings.saving
                                            ? null
                                            : () => settings.setThemeMode(mode),
                                        child: mode == ThemeMode.system
                                            ? Text(
                                                translateAppText(
                                                  '跟随系统',
                                                  systemLanguageCode,
                                                ),
                                              )
                                            : AppText(
                                                mode == ThemeMode.light
                                                    ? '浅色'
                                                    : '深色',
                                              ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                const AppText(
                                  '语言',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppLanguageScope(
                                  languageCode: systemLanguageCode,
                                  child: DesktopSelect<AppLanguage>(
                                    key: const ValueKey('language-select'),
                                    value: settings.language,
                                    items: {
                                      for (final value in AppLanguage.values)
                                        value.label: value,
                                    },
                                    onChanged: settings.saving
                                        ? null
                                        : settings.setLanguage,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const AppText(
                                  '语言设置自动保存，立即生效。',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 24),
                                const AppText(
                                  '主题色',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final value in ThemeAccent.values)
                                      DesktopButton(
                                        active: settings.accent == value,
                                        onPressed: settings.saving
                                            ? null
                                            : () => settings.setAccent(value),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (settings.accent == value)
                                              const Icon(
                                                CupertinoIcons.check_mark,
                                                size: 14,
                                              )
                                            else
                                              DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: value.colorFor(
                                                    Theme.of(context)
                                                        .brightness,
                                                  ),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                ),
                                              ),
                                            const SizedBox(width: 6),
                                            AppText(value.label),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                AppText(
                                  '主题色用于主要按钮、文件选择和交互高亮，立即生效。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.6,
                                    color: context.theme.colors.mutedForeground,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Wrap(
                                  children: [
                                    const AppText(
                                      '界面 DPI',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    AppText(
                                      '：${(settings.dpiScale * 100).round()}%',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                DesktopSlider(
                                  value: settings.dpiScale,
                                  min: .75,
                                  max: 1.5,
                                  divisions: 15,
                                  onChanged: settings.saving
                                      ? null
                                      : settings.setDpiScale,
                                ),
                                const AppText(
                                  '调整界面文字大小，重启应用后仍会保留。',
                                  style: TextStyle(fontSize: 12, height: 1.6),
                                ),
                                const SizedBox(height: 24),
                                const AppText(
                                  '辅助窗口显示方式',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                DesktopSelect<AuxiliaryWindowMode>(
                                  key: const ValueKey('window-mode-select'),
                                  value: settings.windowMode,
                                  items: const {
                                    '画面内显示': AuxiliaryWindowMode.inline,
                                    '独立窗口显示': AuxiliaryWindowMode.separate,
                                  },
                                  onChanged: settings.saving
                                      ? null
                                      : settings.setWindowMode,
                                ),
                                const SizedBox(height: 8),
                                const AppText(
                                  '控制设置、属性和对话框的显示位置。任务进度和结果始终显示在下方状态栏。紧凑布局下对话框全屏显示。',
                                  style: TextStyle(fontSize: 12, height: 1.6),
                                ),
                              ],
                              if (section == 'archive') ...[
                                const AppText(
                                  '压缩包',
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                encodingPicker(
                                  title: '读取默认文件名编码',
                                  value: settings.archive.readEncoding,
                                  creating: false,
                                ),
                                const SizedBox(height: 8),
                                const AppText(
                                  '自动识别优先使用压缩包声明的编码。文件名乱码时，可在“文件 → 编码”中切换当前压缩包的编码。',
                                  style: TextStyle(fontSize: 12, height: 1.6),
                                ),
                                const SizedBox(height: 24),
                                encodingPicker(
                                  title: '创建 ZIP 的文件名编码',
                                  value: settings.archive.createEncoding,
                                  creating: true,
                                ),
                                const AppText(
                                  '建议使用 UTF-8。此设置用于新建 ZIP，不改变文件内容的编码。',
                                  style: TextStyle(fontSize: 12, height: 1.6),
                                ),
                                const SizedBox(height: 24),
                                AppText(
                                  '创建 ZIP 的压缩等级：${settings.archive.compressionLevel == 0 ? "不压缩" : settings.archive.compressionLevel}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                DesktopSlider(
                                  value: settings.archive.compressionLevel
                                      .toDouble(),
                                  min: 0,
                                  max: 9,
                                  divisions: 9,
                                  onChanged: settings.saving
                                      ? null
                                      : (value) => settings.setArchive(
                                          ArchivePreferences(
                                            readEncoding:
                                                settings.archive.readEncoding,
                                            createEncoding:
                                                settings.archive.createEncoding,
                                            compressionLevel: value.round(),
                                          ),
                                        ),
                                ),
                                const AppText(
                                  '0 不压缩，1 更快，9 压缩率更高。设置自动保存，下次创建时生效。',
                                  style: TextStyle(fontSize: 12, height: 1.6),
                                ),
                              ],
                              if (section == 'general') ...[
                                const AppText(
                                  '通用',
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                const AppText(
                                  '文件关联',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const AppText(
                                  '可在系统的“打开方式”中选择 HiZip。下方按钮将支持的压缩包格式设为由 HiZip 默认打开。',
                                  style: TextStyle(fontSize: 12, height: 1.6),
                                ),
                                const SizedBox(height: 16),
                                DesktopButton(
                                  onPressed:
                                      associating ||
                                          !DesktopIntegration()
                                              .supportsDefaultApplication
                                      ? null
                                      : () async {
                                          setState(() {
                                            associating = true;
                                            associationResult = null;
                                          });
                                          try {
                                            await DesktopIntegration()
                                                .setDefaultArchiveHandler();
                                            if (mounted) {
                                              setState(
                                                () => associationResult =
                                                    '已设为默认打开方式',
                                              );
                                            }
                                          } catch (error) {
                                            if (mounted) {
                                              setState(
                                                () => associationResult =
                                                    '设置失败：$error',
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(
                                                () => associating = false,
                                              );
                                            }
                                          }
                                        },
                                  child: const AppText('设为默认打开方式'),
                                ),
                                if (DesktopIntegration().supportsQuickLook) ...[
                                  const SizedBox(height: 24),
                                  const AppText('Finder 右键菜单'),
                                  const SizedBox(height: 10),
                                  const AppText(
                                    '启用 HiZip Finder 扩展后，可在文件右键菜单中创建压缩包或快速创建 ZIP。',
                                  ),
                                  const SizedBox(height: 12),
                                  DesktopButton(
                                    onPressed: () async {
                                      try {
                                        await DesktopIntegration()
                                            .showFinderExtensionSettings();
                                      } catch (error) {
                                        if (mounted) {
                                          setState(
                                            () => associationResult =
                                                '设置失败：$error',
                                          );
                                        }
                                      }
                                    },
                                    child: const AppText('管理 Finder 扩展'),
                                  ),
                                ],
                                if (associationResult != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: AppText(
                                      associationResult!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                              ],
                              if (section == 'performance') ...[
                                const AppText(
                                  '性能',
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                const AppText(
                                  '解压线程数',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final value in <int?>[null, 1, 2, 4])
                                      DesktopButton(
                                        active:
                                            settings.extractionWorkers == value,
                                        onPressed: settings.saving
                                            ? null
                                            : () => settings
                                                  .setExtractionWorkers(value),
                                        child: AppText(
                                          value == null ? '自动' : '$value 个线程',
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                AppText(
                                  '自动根据处理器数量分配，最多使用 4 个线程。更多线程适合包含多个大文件的 ZIP；减少线程可降低 CPU 和磁盘占用。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.6,
                                    color: context.theme.colors.mutedForeground,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppText(
                                  '自动模式下，小压缩包使用单线程。单文件及不适合并行解压的格式使用顺序读取。设置自动保存，下次解压时生效。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.6,
                                    color: context.theme.colors.mutedForeground,
                                  ),
                                ),
                              ],
                              if (settings.error != null) ...[
                                const SizedBox(height: 16),
                                AppText(
                                  settings.error!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: sidebarWidth,
                        decoration: BoxDecoration(
                          color: context.theme.colors.muted,
                          border: Border(
                            right: BorderSide(
                              color: context.theme.colors.border,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            for (final category in [
                              'general',
                              'appearance',
                              'archive',
                              'performance',
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: DesktopButton(
                                  flat: true,
                                  active: section == category,
                                  onPressed: () =>
                                      setState(() => section = category),
                                  child: Row(
                                    children: [
                                      Icon(switch (category) {
                                        'general' => CupertinoIcons.gear,
                                        'appearance' =>
                                          CupertinoIcons.paintbrush,
                                        'archive' => CupertinoIcons.archivebox,
                                        _ => CupertinoIcons.speedometer,
                                      }, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: AppText(
                                          switch (category) {
                                            'general' => '通用',
                                            'appearance' => '外观',
                                            'archive' => '压缩包',
                                            _ => '性能',
                                          },
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
