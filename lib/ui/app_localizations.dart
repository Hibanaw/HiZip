import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'translations.dart';

class AppLanguageScope extends InheritedWidget {
  const AppLanguageScope({
    super.key,
    required this.languageCode,
    required super.child,
  });
  final String languageCode;
  @override
  bool updateShouldNotify(AppLanguageScope oldWidget) =>
      languageCode != oldWidget.languageCode;
}

String appText(BuildContext context, String text) => translateAppText(
  text,
  context
          .dependOnInheritedWidgetOfExactType<AppLanguageScope>()
          ?.languageCode ??
      'zh',
);

/// Dialog routes live above their caller's language scope.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? languageCode,
  bool barrierDismissible = true,
}) {
  final language =
      languageCode ??
      context
          .dependOnInheritedWidgetOfExactType<AppLanguageScope>()
          ?.languageCode ??
      Localizations.localeOf(context).languageCode;
  return showFDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context, _, _) => AppLanguageScope(
      languageCode: language,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: Focus(autofocus: true, child: Builder(builder: builder)),
      ),
    ),
  );
}

String translateAppText(String text, String language) {
  final diagnostic = text.replaceFirst(RegExp(r'^FormatException: '), '');
  text = archiveOperationErrorAliases[diagnostic] ?? text;
  if (language == 'zh') return _chineseTerminology[text] ?? text;
  if (text.startsWith('✓ ')) {
    return '✓ ${translateAppText(text.substring(2), language)}';
  }
  final exact = appEnglishMessages[text];
  if (exact != null) return localizedMessage(exact, language);
  for (final entry in _patterns.entries) {
    final match = entry.key.firstMatch(text);
    if (match != null) {
      var template = localizedMessage(entry.value, language);
      if (language == 'en' && match[1] == '1') {
        template = template
            .replaceAll('items', 'item')
            .replaceAll('files', 'file')
            .replaceAll('threads', 'thread');
      }
      if (language == 'en' &&
          entry.value == '{1} files, {2} folders' &&
          match[2] == '1') {
        template = template.replaceAll('folders', 'folder');
      }
      return template.replaceAllMapped(RegExp(r'\{(\d+)\}'), (placeholder) {
        final index = int.parse(placeholder[1]!);
        final value = match[index];
        // Only these captures contain interface messages. Other captures are
        // filenames, paths, app names or content and must remain literal.
        if (index == 1 &&
            entry.value ==
                'Extraction completed with warnings: {1}\nDestination: {2}') {
          return (value ?? '')
              .split('；')
              .map((notice) => translateAppText(notice, language))
              .join('; ');
        }
        if (index == 1 && _errorTemplates.contains(entry.value)) {
          return translateAppText(
            (value ?? '').replaceFirst(RegExp(r'^Bad state: '), ''),
            language,
          );
        }
        return entry.value == 'ZIP compression level: {1}' && value == '不压缩'
            ? localizedMessage('Store', language)
            : value ?? '';
      });
    }
  }
  return text;
}

const _errorTemplates = {
  'Save failed: {1}\nTemporary file retained at: {2}',
  'Settings update failed: {1}',
  'Quick Look failed: {1}',
  'Temporary cache cleanup failed. Try closing the window again: {1}',
  'Unable to detect filename encoding. Select it from the Encoding menu: {1}',
};

class AppTooltip extends StatelessWidget {
  const AppTooltip({super.key, required this.message, required this.child});
  final String message;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Tooltip(message: appText(context, message), child: child);
}

// Translate interface text only; filenames and document contents stay untouched.
class AppText extends StatelessWidget {
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  @override
  Widget build(BuildContext context) => Text(
    appText(context, data),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
  );
}

final _patterns = <RegExp, String>{
  RegExp(r'^恢复未完成，备份目录：(.+)。请保留该目录。$', dotAll: true):
      'Recovery incomplete. Keep this backup directory: {1}',
  RegExp(r'^发现 (\d+) 个指向绝对路径或解压目录之外的符号链接$', dotAll: true): "Found {1} symbolic links pointing to absolute paths or outside the extraction folder",
  RegExp(
    r'^发现 (\d+) 个指向绝对路径或解压目录之外的符号链接，例如 (.+) → (.+)。\n\n保留后，解压出的链接会指向压缩包之外的位置。$',
    dotAll: true,
  ): "Found {1} symbolic links pointing to absolute paths or outside the extraction folder, such as {2} → {3}.\n\nKeeping them makes the extracted links point outside the archive.",
  RegExp(r'^有 (\d+) 个文件仅大小写不同，目标磁盘不区分大小写$', dotAll: true):
      "{1} files differ only in case; the destination disk is case-insensitive",
  RegExp(
    r'^有 (\d+) 个文件仅大小写不同，目标磁盘不区分大小写，例如 (.+)。\n\n自动重命名会保留两个文件（后者加上“ \(2\)”），跳过则只保留第一个。$',
    dotAll: true,
  ): "{1} files differ only in case; the destination disk is case-insensitive, for example {2}.\n\nAutomatic renaming keeps both files (adding “ (2)” to the later one). Skipping keeps only the first.",
  RegExp(r'^已跳过 (\d+) 个硬链接或特殊文件$', dotAll: true):
      "Skipped {1} hard links or special files",
  RegExp(r'^(\d+) 个符号链接无法创建$', dotAll: true):
      "Could not create {1} symbolic links",
  RegExp(r'^已重命名 (\d+) 个仅大小写不同的文件$', dotAll: true):
      "Renamed {1} files differing only in case",
  RegExp(r'^已跳过 (\d+) 个仅大小写不同的文件$', dotAll: true):
      "Skipped {1} files differing only in case",
  RegExp(r'^解压完成，但(.+?)：(.+)$', dotAll: true):
      "Extraction completed with warnings: {1}\nDestination: {2}",
  RegExp(r'^正在解压 (\d+) / (\d+)$', dotAll: true): "Extracting {1} / {2}",

  RegExp(r'^压缩等级：(\d+)$'): 'Compression level: {1}',
  RegExp(r'^校验通过：(\d+) 个项目，(\d+) 字节$'):
      'Integrity check passed: {1} entries, {2} bytes',
  RegExp(r'^双击展开剩余 (\d+) 项$'): 'Double-click to show {1} remaining items',
  RegExp(r'^队列 \((\d+)\)$'): 'Queue ({1})',
  RegExp(r'^已删除 (\d+) 个项目$'): 'Deleted {1} items',
  RegExp(r'^(\d+) 个所选项目将从压缩包中删除，文件夹内的内容也会删除。$'): '{1} selected items will be deleted from the archive, including folder contents.',
  RegExp(r'^已打开压缩包：(.+)$'): 'Opened archive: {1}',
  RegExp(r'^已关闭压缩包：(.+)$'): 'Closed archive: {1}',
  RegExp(r'^预览已就绪：(.+)$'): 'Preview ready: {1}',
  RegExp(r'^文件已准备好：(.+)$'): 'File ready: {1}',
  RegExp(r'^拖拽完成：(\d+) 个项目$'): 'Drag complete: {1} items',
  RegExp(r'^(\d+) 个线程$'): '{1} threads',
  RegExp(r'^创建 ZIP 的压缩等级：(.+)$'): 'ZIP compression level: {1}',
  RegExp(r'^(\d+) 个项目 · (?:已选择 (\d+) 个项目|已选 (\d+) 个)$'):
      '{1} items · {2}{3} selected',
  RegExp(r'^(\d+) 个项目 · (.+)$'): '{1} items · {2}',
  RegExp(r'^(\d+) 个项目$'): '{1} items',
  RegExp(r'^(\d+) 个文件、(\d+) 个文件夹$'): '{1} files, {2} folders',
  RegExp(r'^(\d+) 个$'): '{1}',
  RegExp(r'^用 (.+) 打开$'): 'Open with {1}',
  RegExp(r'^(.+)（默认）$'): '{1} (default)',
  RegExp(r'^正在解压 (.+)$'): 'Extracting {1}',
  RegExp(r'^(.+) 个文件 · (.+)$'): '{1} files · {2}',
  RegExp(r'^解压完成：(.+)$'): 'Extracted to: {1}',
  RegExp(r'^已复制 (\d+) 个项目$'): 'Copied {1} items',
  RegExp(r'^已(?:传入|导入) (\d+) 个项目$'): 'Imported {1} items',
  RegExp(r'^已移动 (\d+) 个项目$'): 'Moved {1} items',
  RegExp(r'^拖拽 (\d+) 个项目$'): 'Dragging {1} items',
  RegExp(r'^已用 (.+) 打开 · 修改检测已开启$'):
      'Opened with {1} · Change monitoring enabled',
  RegExp(r'^(.+) 文件$'): '{1} file',
  RegExp(r'^当前格式只读。修改后的文件保留在 (.+)$'):
      'Read-only archive. Modified file retained at: {1}',
  RegExp(r'^保存失败：(.+)\n临时文件仍保留在 (.+)$', dotAll: true):
      'Save failed: {1}\nTemporary file retained at: {2}',
  RegExp(r'^设置失败：(.+)$', dotAll: true): 'Settings update failed: {1}',
  RegExp(r'^系统预览失败：(.+)$', dotAll: true): 'Quick Look failed: {1}',
  RegExp(r'^临时缓存清理失败，请重试关闭窗口：(.+)$', dotAll: true):
      'Temporary cache cleanup failed. Try closing the window again: {1}',
  RegExp(r'^无法识别文件名编码，请通过编码菜单选择：(.+)$', dotAll: true): 'Unable to detect filename encoding. Select it from the Encoding menu: {1}',
  RegExp(
    r'^“(.+)” 已修改，是否更新压缩包？\n\n选择“否”不会保存修改。关闭压缩包后，未保存的内容将丢失。$',
    dotAll: true,
  ): '“{1}” has changed. Update the archive?\n\nChoosing “No” leaves the changes unsaved. They will be lost when you close the archive.',
};

Iterable<String> get appMessageTemplates => _patterns.values;

const _chineseTerminology = {
  '正在传入文件': '正在导入文件',
  '全部进度': '总体进度',
  '种类': '类型',
  '操作已完成': '操作完成',
  '当前格式只支持读取。': '当前格式只读。',
};

const archiveOperationErrorAliases = <String, String>{
  "Archive comments require a writable ZIP archive": "仅可编辑未加密 ZIP 压缩包的注释。",
  "Archive comment changed. Reopen the dialog.": "注释已被其他程序修改，请重新打开弹窗。",
  "Archive changed during comment editing": "编辑注释期间压缩包已变化，请重试。",
  "First archive volume is missing": "缺少首个分卷。",
  "Archive volume is missing": "缺少分卷文件。",
  "Archive volume set is incomplete or contains unexpected parts":
      "分卷集合不完整或含有多余文件。",
  "Archive volume checksum mismatch": "分卷校验失败，文件可能已损坏。",
  "Invalid archive volume manifest": "分卷校验清单无效。",
  "Invalid or ambiguous archive volume": "分卷文件名或类型无效，或存在重复编号。",
  "Archive volume destination already exists": "分卷输出已存在，请选择其他名称。",
  "Archive volume changed while opening": "打开过程中分卷已变化，请重试。",
  "Archive volume set is truncated or missing its final part": "分卷压缩包已截断或缺少末卷。",
  "Extraction destination changed. Try again.": "目标目录已变化，请重试。",
  "Archive changed during extraction": "解压过程中压缩包已变化，请重试。",
  "Archive output changed during creation": "创建过程中目标文件已变化，请重试。",
  "Invalid archive output destination": "目标文件类型无效，请选择其他路径。",
  "Cannot safely preserve legacy ZIP entry comments": "无法安全保留旧编码的条目注释，原包未修改。",
  "ZIP comment exceeds 65535 UTF-8 bytes": "注释不能超过 65535 个 UTF-8 字节。",
  "Operation cancelled": "操作已取消",
};

const appEnglishMessages = <String, String>{
  '快速创建 ZIP': 'Quick Create ZIP',
  '创建压缩包…': 'Create Archive…',
  '压缩内容': 'Archive contents',
  '尚未选择文件或文件夹': 'No files or folders selected',
  '选择文件或文件夹…': 'Select Files or Folders…',
  '保存位置': 'Save location',
  '选择…': 'Choose…',
  '选择': 'Choose',
  '移除': 'Remove',
  '请选择要压缩的文件或文件夹。': 'Select files or folders to compress.',
  '请选择压缩包的保存位置。': 'Choose where to save the archive.',
  "HiZip 需要访问此目录中的文件，并在此创建或安全更新压缩包。授权会被记住。": "HiZip needs access to files in this folder to create or safely update archives here. Your permission will be remembered.",
  "授权此目录": "Allow This Folder",
  "请选择所需目录或包含它的上级目录。":
      "Choose the required folder or a folder that contains it.",
  "无法访问所选目录，请检查权限后重试。":
      "Cannot access the selected folder. Check its permissions and try again.",
  "正在检查文件名": "Checking filenames",

  '辅助窗口显示方式': 'Auxiliary window display',
  '画面内显示': 'Inside the main window',
  '独立窗口显示': 'Separate windows',
  '控制设置、属性和对话框的显示位置。任务进度和结果始终显示在下方状态栏。紧凑布局下对话框全屏显示。': 'Choose where settings, properties and dialogs appear. Task progress and results always appear in the bottom status bar. Dialogs fill the screen in compact layouts.',
  '窗口显示设置保存失败，请重试。': 'Could not save the window display setting. Try again.',
  "仅可编辑未加密 ZIP 压缩包的注释。": "Archive comments require a writable ZIP archive",
  "注释已被其他程序修改，请重新打开弹窗。": "Archive comment changed. Reopen the dialog.",
  "编辑注释期间压缩包已变化，请重试。": "Archive changed during comment editing",
  "缺少首个分卷。": "First archive volume is missing",
  "缺少分卷文件。": "Archive volume is missing",
  "分卷集合不完整或含有多余文件。":
      "Archive volume set is incomplete or contains unexpected parts",
  "分卷校验失败，文件可能已损坏。": "Archive volume checksum mismatch",
  "分卷校验清单无效。": "Invalid archive volume manifest",
  "分卷文件名或类型无效，或存在重复编号。": "Invalid or ambiguous archive volume",
  "分卷输出已存在，请选择其他名称。": "Archive volume destination already exists",
  "打开过程中分卷已变化，请重试。": "Archive volume changed while opening",
  "分卷压缩包已截断或缺少末卷。": "Archive volume set is truncated or missing its final part",
  "目标目录已变化，请重试。": "Extraction destination changed. Try again.",
  "解压过程中压缩包已变化，请重试。": "Archive changed during extraction",
  "创建过程中目标文件已变化，请重试。": "Archive output changed during creation",
  "目标文件类型无效，请选择其他路径。": "Invalid archive output destination",
  "无法安全保留旧编码的条目注释，原包未修改。": "Cannot safely preserve legacy ZIP entry comments",

  "压缩包注释": "Archive Comment",
  "压缩包注释…": "Archive Comment…",
  "暂无注释": "No comment",
  "注释": "Comment",
  "属性": "Properties",
  "属性窗口未能启动，请重试。": "The properties window could not start. Try again.",
  "展开": "Show more",
  "收起": "Show less",
  "查看": "View",
  "正在保存注释": "Saving comment",
  "注释已保存": "Comment saved",
  "创建连续分卷": "Create Split Volumes",
  "连续分卷使用 .001、.002 等后缀，并附带校验清单。分卷压缩包只读。": "Split volumes use .001, .002, etc. and include a checksum manifest. Split archives are read-only.",
  "注释不能超过 65535 个 UTF-8 字节。": "The comment must not exceed 65535 UTF-8 bytes.",
  "解压选项": "Extraction Options",
  "遇到同名项目时": "When an item already exists",
  "每次询问": "Ask Each Time",
  "覆盖": "Overwrite",
  "跳过": "Skip",
  "覆盖、跳过或询问时，同名文件夹合并，内部文件按所选策略处理。自动重命名会保留独立副本。": "Overwrite, skip and ask merge matching folders and apply the policy to their files. Rename keeps a separate copy.",
  "目标项目已存在": "Destination Item Already Exists",
  "失败": "Failed",
  "已暂停": "Paused",
  "重试": "Retry",
  "暂停": "Pause",
  "继续": "Resume",

  "关于 HiZip": "About HiZip",
  "服务": "Services",
  "隐藏 HiZip": "Hide HiZip",
  "隐藏其他": "Hide Others",
  "全部显示": "Show All",
  "退出 HiZip": "Quit HiZip",
  "粘贴并匹配样式": "Paste and Match Style",
  "查找": "Find",
  "查找…": "Find…",
  "查找并替换…": "Find and Replace…",
  "查找下一个": "Find Next",
  "查找上一个": "Find Previous",
  "使用所选内容查找": "Use Selection for Find",
  "跳到所选内容": "Jump to Selection",
  "拼写和语法": "Spelling and Grammar",
  "拼写": "Spelling",
  "显示拼写和语法": "Show Spelling and Grammar",
  "立即检查文档": "Check Document Now",
  "键入时检查拼写": "Check Spelling While Typing",
  "检查拼写时检查语法": "Check Grammar With Spelling",
  "自动纠正拼写": "Correct Spelling Automatically",
  "替换": "Substitutions",
  "显示替换": "Show Substitutions",
  "智能复制粘贴": "Smart Copy/Paste",
  "智能引号": "Smart Quotes",
  "智能破折号": "Smart Dashes",
  "智能链接": "Smart Links",
  "数据检测器": "Data Detectors",
  "文本替换": "Text Replacement",
  "文本转换": "Transformations",
  "转换为大写": "Make Upper Case",
  "转换为小写": "Make Lower Case",
  "首字母大写": "Capitalize",
  "语音": "Speech",
  "开始朗读": "Start Speaking",
  "停止朗读": "Stop Speaking",
  "进入全屏": "Enter Full Screen",
  "退出全屏": "Exit Full Screen",

  '不压缩': 'Store',
  "解压全部": "Extract All",
  "解压全部…": "Extract All…",
  "解压全部到同名文件夹": "Extract All to Named Folder",
  "解压全部到同名文件夹…": "Extract All to Named Folder…",
  "压缩包含有可能不安全的符号链接": "Archive contains potentially unsafe symbolic links",
  "保留链接": "Keep Links",
  "跳过这些链接": "Skip These Links",
  "文件名仅大小写不同": "Filenames differ only in case",
  "自动重命名": "Rename Automatically",
  "跳过后者": "Skip Later Files",
  "设置窗口未能启动，请重试。": "The settings window could not start. Please try again.",
  "当前平台不支持文件剪贴板。": "File clipboard is not supported on this platform.",
  "当前平台不支持设置默认打开方式":
      "Setting the default app is not supported on this platform",
  "无法确定 Linux 用户数据目录": "Unable to locate the Linux user data directory",
  "Linux 文件关联仅支持 Linux 桌面端":
      "Linux file associations are supported only on Linux desktops",

  '清除搜索': 'Clear search',
  "输入压缩包密码": "Enter archive password",
  "密码": "Password",
  "密码仅在当前会话中使用，不会保存到设置。": "The password is used only for this session and is not saved in settings.",
  "无法解锁：密码错误、格式不受支持或文件已损坏。":
      "Cannot unlock: incorrect password, unsupported format, or damaged file.",
  "正在解锁…": "Unlocking…",
  "解锁": "Unlock",
  "压缩选项": "Compression options",
  '压缩格式': 'Archive format',
  '嵌套与压缩包同名的文件夹': 'Nest inside a folder named after the archive',
  'Finder 右键菜单': 'Finder context menu',
  '启用 HiZip Finder 扩展后，可在文件右键菜单中创建压缩包或快速创建 ZIP。': 'Enable the HiZip Finder extension to create archives or quickly create ZIP files from the file context menu.',
  '管理 Finder 扩展': 'Manage Finder extensions',
  "压缩算法": "Compression method",
  "Store（不压缩）": "Store (no compression)",
  "ZIP AES-256 加密": "ZIP AES-256 encryption",
  "当前引擎不支持 AES 加密。": "The current engine does not support AES encryption.",
  "此格式暂不支持加密压缩。": "Encrypted creation is not supported for this format yet.",
  "ZIP 加密不会隐藏文件名。加密压缩包目前只支持读取。": "ZIP encryption does not hide filenames. Encrypted archives currently support reading only.",
  "确认密码": "Confirm password",
  "密码不能为空，两次输入必须一致。":
      "The password must not be empty and both entries must match.",
  "当前引擎不支持此压缩格式。":
      "The current engine does not support this compression format.",
  "加密压缩需要 ZIP 格式、密码和至少一个文件。": "Encrypted creation requires ZIP format, a password, and at least one file.",
  "设置密码时必须启用加密。": "Encryption must be enabled when setting a password.",
  "加密压缩需要至少一个普通文件。": "Encrypted creation requires at least one regular file.",
  "ZIP 压缩算法仅适用于 ZIP 格式。": "ZIP compression methods apply only to ZIP format.",
  "正在解锁压缩包": "Unlocking archive",
  '重命名': 'Rename',
  '保存': 'Save',
  '放弃': 'Discard',
  "重命名…": "Rename…",
  "重命名完成": "Rename complete",
  "正在重命名": "Renaming",
  "新建空压缩包": "New Empty Archive",
  "测试压缩包": "Test Archive",
  "正在测试压缩包": "Testing archive",
  "放弃未保存的修改？": "Discard unsaved changes?",
  "正在保存…": "Saving…",
  "目标名称已存在。": "The destination name already exists.",
  "重命名结果校验失败。": "The renamed archive failed validation.",
  "压缩包在操作过程中已变化，请重试。":
      "The archive changed during the operation. Please try again.",
  "所选条目已变化，请重新打开压缩包。": "The selected entry changed. Reopen the archive.",
  "压缩包在保存过程中已变化，请重试。": "The archive changed while saving. Please try again.",
  '文件超过预览限制，请打开文件查看完整内容。':
      'File exceeds the preview limit. Open it to view the full content.',
  '新建文件夹': 'New Folder',
  '新建文件夹…': 'New Folder…',
  '新建空白文档': 'New Blank Document',
  '新建空白文档…': 'New Blank Document…',
  '未命名文件夹': 'Untitled Folder',
  '未命名.txt': 'Untitled.txt',
  '创建': 'Create',
  '取消': 'Cancel',
  '删除': 'Delete',
  '删除…': 'Delete…',
  '删除所选项目？': 'Delete selected items?',
  '文件夹已创建': 'Folder created',
  '空白文档已创建': 'Blank document created',
  '正在新建文件夹': 'Creating folder',
  '正在新建空白文档': 'Creating blank document',
  '正在删除文件': 'Deleting files',
  '当前格式只支持读取。': 'This archive format is read-only.',
  '请输入有效的名称，不能包含路径分隔符。': 'Enter a valid name without path separators.',
  '所选条目已变化或路径不安全，请重新选择。':
      'The selected items changed or have unsafe paths. Select them again.',
  '压缩包在删除过程中已被修改，请重试。': 'The archive changed during deletion. Try again.',

  '语言': 'Language',
  '简体中文': '简体中文',
  '跟随系统': 'Follow System',
  '语言设置自动保存，立即生效。': 'Your language preference is saved automatically and applies immediately.',
  '返回': 'Back',
  '设置': 'Settings',
  '外观': 'Appearance',
  '主题色': 'Accent Color',
  '紫色': 'Purple',
  '青绿': 'Teal',
  '森林绿': 'Forest Green',
  '橙色': 'Orange',
  '玫瑰红': 'Rose',
  '粉色': 'Pink',
  '红色': 'Red',
  '黄色': 'Yellow',
  '绿色': 'Green',
  '灰色': 'Gray',
  '主题色用于主要按钮、文件选择和交互高亮，立即生效。': 'Applies immediately to primary buttons, file selections and interactive highlights.',
  '主题色保存失败，请重试。': 'Could not save the accent color. Try again.',
  '浅色': 'Light',
  '深色': 'Dark',
  '文件选择高亮': 'File selection highlight',
  '蓝色': 'Blue',
  '淡灰色': 'Soft Gray',
  '多栏视图仅最右侧列使用此高亮，左侧路径列使用灰色。':
      'Only the rightmost column uses this highlight. Path columns use gray.',
  '压缩包': 'Archives',
  '读取默认文件名编码': 'Default filename encoding for reading',
  '自动识别优先使用压缩包声明的编码。文件名乱码时，可在“文件 → 编码”中切换当前压缩包的编码。': 'Auto detection honors the archive’s encoding. If filenames look incorrect, choose another encoding under File → Encoding.',
  '创建 ZIP 的文件名编码': 'Filename encoding for new ZIP archives',
  '建议使用 UTF-8。此设置用于新建 ZIP，不改变文件内容的编码。': 'UTF-8 is recommended. This applies to new ZIP filenames and does not change file contents.',
  '0 不压缩，1 更快，9 压缩率更高。设置自动保存，下次创建时生效。': '0 stores without compression, 1 is faster, and 9 compresses more. Applies to the next archive you create.',
  '性能': 'Performance',
  '解压线程数': 'Extraction threads',
  '自动': 'Automatic',
  '自动根据处理器数量分配，最多使用 4 个线程。更多线程适合包含多个大文件的 ZIP；减少线程可降低 CPU 和磁盘占用。': 'Automatic uses up to 4 threads based on your processor. More threads help with large ZIP files; fewer reduce CPU and disk usage.',
  '自动模式下，小压缩包使用单线程。单文件及不适合并行解压的格式使用顺序读取。设置自动保存，下次解压时生效。': 'Small archives and formats that cannot be extracted in parallel use one thread. Changes apply to the next extraction.',
  '自动识别': 'Auto Detect',
  '简体中文（GB18030 / GBK）': 'Chinese Simplified (GB18030 / GBK)',
  '繁体中文（Big5）': 'Chinese Traditional (Big5)',
  '日文（Shift-JIS）': 'Japanese (Shift-JIS)',
  '韩文（CP949）': 'Korean (CP949)',
  '西欧（Windows-1252）': 'Western European (Windows-1252)',
  '更多': 'More',
  '通用': 'General',
  '文件关联': 'File Associations',
  '设为默认打开方式': 'Set as Default',
  '已设为默认打开方式': 'Default app updated',
  '创建压缩包': 'Create Archive',
  '压缩包已创建': 'Archive created',
  'gzip（单个文件）': 'gzip (single file)',
  'bzip2（单个文件）': 'bzip2 (single file)',
  'xz（单个文件）': 'xz (single file)',
  'LZMA（单个文件）': 'LZMA (single file)',
  '可在系统的“打开方式”中选择 HiZip。下方按钮将支持的压缩包格式设为由 HiZip 默认打开。': 'Choose HiZip in the system Open With menu. The button below makes HiZip the default app for supported archive formats.',
  '关闭标签页': 'Close Tab',
  '未打开压缩包': 'No archive open',
  '队列为空': 'Queue is empty',
  '进行中': 'Running',
  '等待中': 'Waiting',
  '等待保存确认': 'Waiting for save confirmation',
  '等待删除确认': 'Waiting for delete confirmation',
  '正在读取压缩包': 'Reading archive',
  '正在准备文件': 'Preparing file',
  '正在准备导出': 'Preparing export',
  '正在导入文件': 'Importing files',
  '正在传输文件': 'Transferring files',
  '正在创建项目': 'Creating item',
  '正在删除项目': 'Deleting items',
  '正在确认修改': 'Confirming changes',
  '正在保留临时文件': 'Retaining temporary file',
  '正在放弃修改': 'Discarding changes',
  '正在处理文件': 'Processing files',
  '压缩文件': 'Archives',
  'ZIP 已创建': 'ZIP created',
  '已在默认应用中打开 · 修改检测已开启':
      'Opened in the default app · Change monitoring enabled',
  '已以只读模式打开。编辑时请另存到其他位置。': 'Opened read-only. Save a copy elsewhere to edit.',
  '当前格式仅支持读取。请将文件另存到其他位置。':
      'This format is read-only. Save the file elsewhere.',
  '解压到这里': 'Extract Here',
  '正在解压': 'Extracting',
  '文件已修改': 'File Modified',
  '否': 'No',
  '是': 'Yes',
  '正在保存回压缩包': 'Updating archive',
  '修改已保存回压缩包': 'Changes saved to the archive',
  '剪贴板中没有文件': 'No files on the clipboard',
  '来源目录已变化，请重新拖拽': 'The source folder changed. Drag the files again.',
  '无法读取拖入的文件。': 'Unable to read the dropped files.',
  '正在准备拖拽文件': 'Preparing files for drag',
  '拖拽文件已准备好': 'Files are ready to drag',
  '拖拽已取消': 'Drag cancelled',
  '目标不接受此拖拽': 'The destination does not accept this drag',
  '正在打开压缩包': 'Opening archive',
  '正在关闭压缩包': 'Closing archive',
  '正在创建压缩包': 'Creating archive',
  '正在打开文件': 'Opening file',
  '正在生成预览': 'Generating preview',
  '正在搜索': 'Searching',
  '搜索已完成': 'Search complete',
  '正在复制文件': 'Copying files',
  '正在移动文件': 'Moving files',
  '正在传入文件': 'Importing files',
  '没有匹配的文件': 'No matching files',
  '空文件夹': 'Empty folder',
  '打开方式': 'Open With',
  '在 HiZip 中打开': 'Open in HiZip',
  '其他应用': 'Other Applications',
  '目录': 'Folders',
  '列表视图': 'List View',
  '图标视图': 'Icon View',
  '多栏视图': 'Column View',
  '画廊视图': 'Gallery View',
  '预览栏': 'Preview Pane',
  '复制': 'Copy',
  '粘贴': 'Paste',
  '解压': 'Extract',
  '打开压缩包': 'Open Archive',
  '创建 ZIP': 'Create ZIP',
  '本次打开': 'Opened This Session',
  '文件名编码': 'Filename Encoding',
  '当前平台暂不支持压缩文件操作': 'Archive operations are unavailable on this platform',
  '搜索': 'Search',
  '名称': 'Name',
  '大小': 'Size',
  '修改日期': 'Date Modified',
  '种类': 'Type',
  '系统预览（空格）': 'Quick Look (Space)',
  '预览': 'Preview',
  '打开': 'Open',
  '解压所选': 'Extract Selection',
  '文件夹': 'Folder',
  '在默认应用中打开': 'Open in Default App',
  '图片': 'Image',
  '文本文档': 'Text Document',
  '文件': 'File',
  '应用菜单': 'Application Menu',
  '打开压缩包…': 'Open Archive…',
  '打开所选项目': 'Open Selection',
  '添加文件…': 'Add Files…',
  '添加文件夹…': 'Add Folder…',
  '解压所选…': 'Extract Selection…',
  '解压当前文件夹…': 'Extract Current Folder…',
  '校验压缩包': 'Verify Archive',
  '移动到…': 'Move To…',
  '复制到…': 'Copy To…',
  '压缩包属性': 'Archive Properties',
  '任务列表': 'Task List',
  '排序方式': 'Sort By',
  '升序': 'Ascending',
  '降序': 'Descending',
  '放大图标': 'Increase Icon Size',
  '缩小图标': 'Decrease Icon Size',
  '前往': 'Go',
  '上级文件夹': 'Enclosing Folder',
  '压缩包根目录': 'Archive Root',
  '上一个标签页': 'Previous Tab',
  '下一个标签页': 'Next Tab',
  '编辑': 'Edit',
  '显示': 'View',
  '全选': 'Select All',
  '设置…': 'Settings…',
  '打开…': 'Open…',
  '创建 ZIP…': 'Create ZIP…',
  '解压…': 'Extract…',
  '编码': 'Encoding',
  '最近打开': 'Open Recent',
  '暂无最近打开的文件': 'No Recent Files',
  '清除菜单': 'Clear Menu',
  '界面 DPI': 'Interface DPI',
  '关闭搜索': 'Close Search',
  '调整界面文字大小，重启应用后仍会保留。':
      'Adjust interface text size. The setting persists after restart.',
  '信息': 'Information',
  '路径': 'Path',
  '项目': 'Items',
  '当前层级': 'This Folder',
  '状态': 'Status',
  '可写入': 'Writable',
  '只读': 'Read Only',
  '调整图标大小': 'Adjust Icon Size',
  '正在读取应用…': 'Loading applications…',
  '其他…': 'Other…',
  '快速查看': 'Quick Look',
  '空格': 'Space',
  '当前文件': 'Current File',
  '全部进度': 'Overall Progress',
  '正在处理…': 'Processing…',
  '语言设置保存失败，请重试。': 'Unable to save the language preference. Please try again.',
  '操作信息': 'Operation Details',
  '操作失败': 'Operation failed',
  '操作完成': 'Operation complete',
  '操作已完成': 'Operation complete',
  '操作已取消': 'Operation cancelled',
  '正在取消': 'Cancelling',
  '取消任务': 'Cancel Task',
  '关闭': 'Close',
  '关闭窗口': 'Close Window',
  '最小化': 'Minimize',
  '最大化': 'Maximize',
  '还原': 'Restore',
  '拖动': 'Drag',
  '撤销': 'Undo',
  '重做': 'Redo',
  '剪切': 'Cut',
  '窗口': 'Window',
  '缩放': 'Zoom',
  '全部置于最前': 'Bring All to Front',
  '帮助': 'Help',
  '压缩包设置保存失败，请重试。': 'Unable to save archive settings. Please try again.',
  '浏览习惯保存失败，请重试。': 'Unable to save browsing preferences. Please try again.',
  '无法读取设置，当前使用自动线程数。':
      'Unable to load settings. Automatic extraction threads are in use.',
  '文件高亮设置保存失败，请重试。': 'Unable to save selection settings. Please try again.',
  '外观设置保存失败，请重试。': 'Unable to save appearance settings. Please try again.',
  'DPI 设置保存失败，请重试。': 'Unable to save interface scaling. Please try again.',
  '设置保存失败，请重试。': 'Unable to save settings. Please try again.',
  '画廊预览已取消': 'Gallery preview cancelled',
  'zstd（单个文件）': 'zstd (single file)',
  'LZ4（单个文件）': 'LZ4 (single file)',
  'lzip（单个文件）': 'lzip (single file)',
  'compress（单个文件）': 'compress (single file)',
  'DOS（CP437）': 'DOS (CP437)',
  '压缩包缓存正在关闭。': 'The archive cache is closing.',
  '此路径存在重复条目，无法安全打开。':
      'This path has duplicate entries and cannot be opened safely.',
  '原压缩包已被其他程序修改。为避免覆盖，请保留临时文件并重新打开压缩包。': 'Another application modified the archive. Keep the temporary file and reopen the archive to avoid overwriting changes.',
  '当前格式仅支持读取。请另存临时文件，或创建新的可写压缩包。': 'This format is read-only. Save the temporary file elsewhere or create a writable archive.',
  '文件在保存过程中再次发生变化，请重试。':
      'The file changed again while saving. Please try again.',
  '当前格式只支持读取，文件传入和内部移动需要可写入的未加密压缩包。':
      'Importing and moving files requires a writable, unencrypted archive.',
  '不安全的目标目录。': 'The destination folder is unsafe.',
  '压缩包在拖拽过程中已变化，请重试。': 'The archive changed during the drag. Please try again.',
  '压缩包在传输过程中已被修改，请重试。':
      'The archive changed during transfer. Please try again.',
  '不能将目录放入它自身或子目录中。': 'A folder cannot be placed inside itself or a subfolder.',
  '压缩包已变化，请重新打开后再试。': 'The archive changed. Reopen it and try again.',
  '所选文件存在同名文件，请先重命名。':
      'Selected files have duplicate names. Rename them first.',
  '来源文件在传输过程中已变化，请重试。':
      'The source file changed during transfer. Please try again.',
  '此文件是链接、加密文件或包含不安全路径，暂不支持解压。':
      'Links, encrypted files and unsafe paths cannot be extracted.',
  '不安全的文件名。': 'The filename is unsafe.',
  '来源文件夹包含重名或大小写冲突的路径。':
      'The source folder contains duplicate or case-conflicting paths.',
  '暂不支持传入链接或特殊文件。': 'Importing links or special files is not supported.',
  '压缩包含有重复的文件路径，无法安全解压。': 'Duplicate paths prevent safe extraction.',
  '所选条目存在同名文件。': 'The selected items have duplicate names.',
  '不安全的目录路径。': 'The folder path is unsafe.',
  '不能将目录移动到它自身或子目录中。': 'A folder cannot be moved into itself or a subfolder.',
  '压缩包含有重复路径，无法安全修改。': 'Duplicate paths prevent safe archive modification.',
  '目标路径不是文件夹。': 'The destination path is not a folder.',
  '含有链接、加密或不安全条目的 ZIP 暂不支持修改。': 'ZIP archives with links, encrypted entries or unsafe paths cannot be modified.',
  '不能将压缩包加入它自身。': 'An archive cannot be added to itself.',
  '传入的文件夹包含当前压缩包，不能将压缩包加入它自身。': 'The imported folder contains this archive. An archive cannot be added to itself.',
  '事件队列已关闭': 'The task queue is closed.',
};
