import 'package:path/path.dart' as p;

class ArchiveEntry {
  const ArchiveEntry({
    required this.path,
    required this.size,
    required this.directory,
    this.regular = true,
    this.safe = true,
    this.encrypted = false,
    this.modified,
  });
  factory ArchiveEntry.fromJson(Map<String, dynamic> j) => ArchiveEntry(
    path: j['path'] as String,
    size: (j['size'] as num).toInt(),
    directory: j['directory'] as bool,
    regular: j['regular'] as bool,
    safe: j['safe'] as bool,
    encrypted: j['encrypted'] as bool,
    modified: (j['modified'] as num) > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            (j['modified'] as num).toInt() * 1000,
          )
        : null,
  );
  final String path;
  final int size;
  final bool directory, regular, safe, encrypted;
  final DateTime? modified;
  String get normalized => path.replaceAll(RegExp(r'/+$'), '');
  String get name => p.posix.basename(normalized);
  String get extension => p.posix.extension(name).toLowerCase();
  bool get isImage =>
      ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'].contains(extension);
  bool get isText =>
      [
        '.txt',
        '.md',
        '.json',
        '.yaml',
        '.yml',
        '.xml',
        '.html',
        '.css',
        '.js',
        '.ts',
        '.dart',
        '.c',
        '.h',
        '.cpp',
        '.py',
        '.sh',
        '.csv',
        '.log',
        '.ini',
        '.toml',
        '.svg',
      ].contains(extension) ||
      name.toLowerCase() == 'readme';
  bool get canExtract => safe && regular && !directory && !encrypted;
}

List<ArchiveEntry> childrenOf(
  List<ArchiveEntry> entries,
  String folder, {
  String search = '',
}) {
  final result = <String, ArchiveEntry>{};
  final prefix = folder.isEmpty ? '' : '$folder/';
  for (final e in entries) {
    if (!e.normalized.startsWith(prefix)) continue;
    final relative = e.normalized.substring(prefix.length);
    if (relative.isEmpty) continue;
    final parts = relative.split('/');
    if (parts.length == 1) {
      result[e.normalized] = e;
    } else {
      final path = '$prefix${parts.first}';
      result.putIfAbsent(
        path,
        () => ArchiveEntry(path: path, size: 0, directory: true),
      );
    }
  }
  final list = result.values
      .where((e) => e.name.toLowerCase().contains(search.toLowerCase()))
      .toList();
  list.sort(
    (a, b) => a.directory != b.directory
        ? (a.directory ? -1 : 1)
        : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );
  return list;
}

bool isSafeArchivePath(String value) {
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.contains('\\') ||
      value.contains(':')) {
    return false;
  }
  return !value.split('/').any((s) => s == '..' || s == '.' || s.isEmpty) &&
      !value.contains('\u0000');
}

String formatSize(int size) {
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
  if (size < 1024 * 1024 * 1024) {
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(size / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}

class ArchiveFolder {
  ArchiveFolder(this.path);
  final String path;
  final children = <ArchiveFolder>[];
  String get name => p.posix.basename(path);
}

/// Include implicit parent folders and explicitly empty folders. Build once
/// per document; expanding a node does not rescan the archive's file entries.
ArchiveFolder buildFolderTree(List<ArchiveEntry> entries) {
  final root = ArchiveFolder('');
  final folders = <String, ArchiveFolder>{'': root};
  for (final entry in entries) {
    if (!entry.safe || !isSafeArchivePath(entry.normalized)) continue;
    final parts = entry.normalized.split('/');
    final count = entry.directory ? parts.length : parts.length - 1;
    var parent = root;
    for (var i = 0; i < count; i++) {
      final path = parts.take(i + 1).join('/');
      parent = folders.putIfAbsent(path, () {
        final folder = ArchiveFolder(path);
        parent.children.add(folder);
        return folder;
      });
    }
  }
  for (final folder in folders.values) {
    folder.children.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  }
  return root;
}
