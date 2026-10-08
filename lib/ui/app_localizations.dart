import 'package:flutter/material.dart';

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
  if (language != 'en') return text;
  if (text.startsWith('✓ ')) {
    return '✓ ${translateAppText(text.substring(2), language)}';
  }
  final exact = _english[text];
  if (exact != null) return exact;
  for (final entry in _patterns.entries) {
    final match = entry.key.firstMatch(text);
    if (match != null) return entry.value(match);
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

final _patterns = <RegExp, String Function(RegExpMatch)>{
  RegExp(r'^双击展开剩余 (\d+) 项$'): (m) =>
      'Double-click to show ${m[1]} remaining items',
  RegExp(r'^队列 \((\d+)\)$'): (m) => 'Queue (${m[1]})',
  RegExp(r'^已删除 (\d+) 个项目$'): (m) => 'Deleted ${m[1]} items',
  RegExp(r'^(\d+) 个所选项目将从压缩包中删除，文件夹内的内容也会删除。$'): (m) =>
      '${m[1]} selected items will be deleted from the archive, including folder contents.',

  RegExp(r'^已打开压缩包：(.+)$'): (m) => 'Opened archive: ${m[1]}',
  RegExp(r'^已关闭压缩包：(.+)$'): (m) => 'Closed archive: ${m[1]}',
  RegExp(r'^预览已就绪：(.+)$'): (m) => 'Preview ready: ${m[1]}',
  RegExp(r'^文件已准备好：(.+)$'): (m) => 'File ready: ${m[1]}',
  RegExp(r'^拖拽完成：(\d+) 个项目$'): (m) => 'Drag complete: ${m[1]} items',
  RegExp(r'^(.+) 个线程$'): (m) => '${m[1]} threads',
  RegExp(r'^创建 ZIP 的压缩等级：(.+)$'): (m) =>
      'ZIP compression level: ${m[1] == "不压缩" ? "Store" : m[1]}',
  RegExp(r'^(\d+) 个项目(.*)$'): (m) =>
      '${m[1]} items${m[2]!.replaceAllMapped(RegExp(r' · 已选 (\d+) 个'), (selection) => ' · ${selection[1]} selected')}',
  RegExp(r'^(.+) 个文件、(.+) 个文件夹$'): (m) => '${m[1]} files, ${m[2]} folders',
  RegExp(r'^(.+) 个$'): (m) => '${m[1]}',
  RegExp(r'^用 (.+) 打开$'): (m) => 'Open with ${m[1]}',
  RegExp(r'^(.+)（默认）$'): (m) => '${m[1]} (default)',
  RegExp(r'^正在解压 (.+)$'): (m) => 'Extracting ${m[1]}',
  RegExp(r'^(.+) 个文件 · (.+)$'): (m) => '${m[1]} files · ${m[2]}',
  RegExp(r'^解压完成：(.+)$'): (m) => 'Extracted to: ${m[1]}',
  RegExp(r'^已复制 (.+) 个项目$'): (m) => 'Copied ${m[1]} items',
  RegExp(r'^已传入 (.+) 个项目$'): (m) => 'Imported ${m[1]} items',
  RegExp(r'^已移动 (.+) 个项目$'): (m) => 'Moved ${m[1]} items',
  RegExp(r'^拖拽 (.+) 个项目$'): (m) => 'Dragging ${m[1]} items',
  RegExp(r'^已用 (.+) 打开 · 修改检测已开启$'): (m) =>
      'Opened with ${m[1]} · Watching for changes',
  RegExp(r'^(.+) 文件$'): (m) => '${m[1]} file',
  RegExp(
    r'^“(.+)” 已修改，是否更新压缩包？\n\n选择“否”不会保存修改。关闭压缩包后，未保存的内容将丢失。$',
    dotAll: true,
  ): (m) =>
      '“${m[1]}” has changed. Update the archive?\n\nChoosing “No” leaves the changes unsaved. They will be lost when you close the archive.',
};

const _english = <String, String>{
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
  '主题色': 'Accent color',
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
  '正在确认修改': 'Acknowledging changes',
  '正在保留临时文件': 'Retaining temporary file',
  '正在放弃修改': 'Discarding changes',
  '正在处理文件': 'Processing files',
  '压缩文件': 'Archives',
  'ZIP 已创建': 'ZIP created',
  '已在默认应用中打开 · 修改检测已开启': 'Opened in the default app · Watching for changes',
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
  '修改日期': 'Modified',
  '种类': 'Kind',
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
};
