import '../services/archive_service.dart';
import 'archive_entry.dart';
import 'archive_formats.dart';
import 'archive_index.dart';

/// Send only inspector metadata and at most three icons to another engine.
Map<String, dynamic> archivePropertiesSnapshot(
  ArchiveDocument doc,
  String folder,
  List<ArchiveEntry> selected,
) {
  final summaryFolder = selected.length == 1 && selected.single.directory
      ? selected.single.normalized
      : folder;
  final roots = topLevelEntries(selected);
  final size =
      selected.isEmpty || (selected.length == 1 && selected.single.directory)
      ? summaryFolder.isEmpty
            ? doc.index.totalSize
            : doc.index.sizes[summaryFolder] ?? 0
      : roots.fold<int>(
          0,
          (sum, entry) =>
              sum +
              (entry.directory
                  ? doc.index.sizes[entry.normalized] ?? 0
                  : entry.size),
        );
  final canOpen = selected.any((entry) => entry.directory || entry.canExtract);
  return {
    'path': doc.path,
    'format': doc.format,
    'writable': doc.writable,
    'comment': doc.comment,
    'folder': folder,
    'size': size,
    'itemCount': summaryFolder.isEmpty
        ? doc.entries.length
        : doc.index.descendants[summaryFolder] ?? 0,
    'currentCount': doc.index.inFolder(summaryFolder).length,
    'selectionCount': selected.length,
    'folderCount': selected.where((entry) => entry.directory).length,
    'selection': [
      for (final entry in selected.take(3))
        {
          'path': entry.path,
          'size': entry.size,
          'directory': entry.directory,
          'regular': entry.regular,
          'safe': entry.safe,
          'encrypted': entry.encrypted,
          'unlocked': entry.unlocked,
          'link': entry.linkTarget,
          'modified': (entry.modified?.millisecondsSinceEpoch ?? 0) ~/ 1000,
        },
    ],
    'actions': [
      if (canOpen)
        {
          'id': 'open',
          'label': selected.length == 1 && !selected.single.directory
              ? isReadableArchivePath(selected.single.name)
                    ? '在 HiZip 中打开'
                    : '在默认应用中打开'
              : '打开',
        },
      {
        'id': 'extract',
        'label': selected.isEmpty && folder.isEmpty ? '解压全部' : '解压',
      },
      if (selected.isEmpty && folder.isEmpty)
        {'id': 'extractNamed', 'label': '解压全部到同名文件夹'},
    ],
  };
}

List<ArchiveEntry> archivePropertiesSelection(Map<String, dynamic> data) => [
  for (final entry in data['selection'] as List)
    ArchiveEntry.fromJson(
      Map<String, dynamic>.from(entry as Map),
      unlocked: entry['unlocked'] == true,
    ),
];

ArchiveDocument archivePropertiesDocument(Map<String, dynamic> data) =>
    ArchiveDocument(
      data['path'] as String,
      archivePropertiesSelection(data),
      data['format'] as String,
      data['writable'] as bool,
      comment: data['comment'] as String,
    );
