import 'package:flutter/material.dart';

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

String translateAppText(String text, String language) {
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
        final value = match[int.parse(placeholder[1]!)];
        return entry.value == 'ZIP compression level: {1}' && value == '不压缩'
            ? localizedMessage('Store', language)
            : value ?? '';
      });
    }
  }
  return text;
}

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

const appEnglishMessages = <String, String>{
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
  '海蓝': 'Ocean Blue',
  '紫罗兰': 'Violet',
  '青绿': 'Teal',
  '森林绿': 'Forest Green',
  '琥珀橙': 'Amber Orange',
  '玫瑰红': 'Rose',
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
  '浏览器版本需要 WebAssembly 引擎。请使用原生桌面版本。': 'The browser version requires a WebAssembly engine. Use the native desktop app.',
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
