import 'archive_entry.dart';

/// Built once in the archive worker. Browsing never scans/sorts the full archive.
class ArchiveIndex {
  ArchiveIndex(List<ArchiveEntry> entries) {
    final childMaps = <String, Map<String, ArchiveEntry>>{'': {}};
    final folders = <String, ArchiveFolder>{'': tree};
    for (final entry in entries) {
      byPath.putIfAbsent(entry.path, () => entry);
      final normalized = entry.normalized;
      final parts = normalized.split('/');
      final safeTree = entry.safe && isSafeArchivePath(normalized);
      var parent = '';
      for (var i = 0; i < parts.length; i++) {
        final path = parent.isEmpty ? parts[i] : '$parent/${parts[i]}';
        final last = i == parts.length - 1;
        final children = childMaps.putIfAbsent(parent, () => {});
        if (last) {
          children[path] = entry;
        } else {
          children.putIfAbsent(
            path,
            () => ArchiveEntry(path: path, size: 0, directory: true),
          );
        }
        if (!last || entry.directory) {
          childMaps.putIfAbsent(path, () => {});
          if (safeTree) {
            folders.putIfAbsent(path, () {
              final folder = ArchiveFolder(path);
              folders[parent]!.children.add(folder);
              return folder;
            });
          }
        }
        sizes.update(path, (v) => v + entry.size, ifAbsent: () => entry.size);
        descendants.update(path, (v) => v + 1, ifAbsent: () => 1);
        parent = path;
      }
      totalSize += entry.size;
      counts.update(normalized, (v) => v + 1, ifAbsent: () => 1);
    }
    for (final folder in folders.values) {
      folder.children.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    for (final map in childMaps.entries) {
      final list = map.value.values.toList();
      list.sort(
        (a, b) => a.directory != b.directory
            ? (a.directory ? -1 : 1)
            : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      children[map.key] = List.unmodifiable(list);
      for (final item in list) {
        byPath.putIfAbsent(item.path, () => item);
        byNormalized[item.normalized] = item;
      }
    }
  }
  final tree = ArchiveFolder('');
  final byPath = <String, ArchiveEntry>{};
  final byNormalized = <String, ArchiveEntry>{};
  final children = <String, List<ArchiveEntry>>{};
  final sizes = <String, int>{};
  final counts = <String, int>{};
  // Entries at or below each path, so inspectors need no per-build scan.
  final descendants = <String, int>{};
  int totalSize = 0;
  List<ArchiveEntry> inFolder(String folder) => children[folder] ?? const [];
}

List<ArchiveEntry> topLevelEntries(List<ArchiveEntry> entries) {
  final directories = entries
      .where((e) => e.directory)
      .map((e) => e.normalized)
      .toSet();
  return entries.where((e) {
    var path = e.normalized;
    while (path.contains('/')) {
      path = path.substring(0, path.lastIndexOf('/'));
      if (directories.contains(path)) return false;
    }
    return true;
  }).toList();
}

List<ArchiveEntry> filterArchiveEntries((List<ArchiveEntry>, String) input) {
  final term = input.$2.toLowerCase();
  return input.$1.where((e) => e.name.toLowerCase().contains(term)).toList();
}
