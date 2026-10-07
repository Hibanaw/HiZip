import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';

void main() {
  test('synthesizes folders for archives with no directory entries', () {
    const entries = [
      ArchiveEntry(path: 'photos/trip/a.png', size: 12, directory: false),
      ArchiveEntry(path: 'readme.txt', size: 2, directory: false),
    ];
    expect(childrenOf(entries, '').map((e) => e.path), [
      'photos',
      'readme.txt',
    ]);
    expect(childrenOf(entries, 'photos').single.path, 'photos/trip');
    expect(childrenOf(entries, 'photos/trip').single.name, 'a.png');
    expect(childrenOf(entries, '', search: 'READ').single.name, 'readme.txt');
  });
  test('rejects traversal and cross-platform absolute paths', () {
    for (final path in [
      '../a',
      '/a',
      'a/../b',
      'C:/a',
      r'a\b',
      './a',
      'a//b',
      'a\u0000b',
    ]) {
      expect(isSafeArchivePath(path), false, reason: path);
    }
    expect(isSafeArchivePath('目录/file.txt'), true);
  });
  test(
    'folder tree retains implicit parents, empty folders and rejects unsafe paths',
    () {
      final root = buildFolderTree(const [
        ArchiveEntry(path: 'docs/nested/a.txt', size: 1, directory: false),
        ArchiveEntry(path: 'docs/second.txt', size: 1, directory: false),
        ArchiveEntry(path: 'empty/', size: 0, directory: true),
        ArchiveEntry(path: '../outside/a.txt', size: 1, directory: false),
      ]);
      expect(root.children.map((e) => e.path), ['docs', 'empty']);
      expect(root.children.first.children.single.path, 'docs/nested');
    },
  );
}
