import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/archive_index.dart';
import 'package:hizip/models/preview_text.dart';

void main() {
  test(
    'index matches directory synthesis, order, duplicate checks and subtree sizes',
    () {
      const entries = [
        ArchiveEntry(path: '资料/nested/a.txt', size: 7, directory: false),
        ArchiveEntry(path: '资料/', size: 0, directory: true),
        ArchiveEntry(path: 'empty/', size: 0, directory: true),
        ArchiveEntry(path: 'one.txt', size: 4, directory: false),
        ArchiveEntry(path: '资料/b.txt', size: 9, directory: false),
        ArchiveEntry(path: '资料/b.txt', size: 9, directory: false),
      ];
      final index = ArchiveIndex(entries);
      for (final folder in ['', '资料', '资料/nested', 'empty', 'missing']) {
        expect(
          index.inFolder(folder).map((e) => e.path),
          childrenOf(entries, folder).map((e) => e.path),
        );
      }
      expect(index.sizes['资料'], 25);
      expect(index.totalSize, 29);
      expect(index.counts['资料/b.txt'], 2);
      expect(index.byNormalized['资料']!.path, '资料/');
      expect(index.tree.children.map((f) => f.path), ['empty', '资料']);
      final selection = [entries[0], entries[1], entries[3]];
      expect(topLevelEntries(selection).map((e) => e.path), ['资料/', 'one.txt']);
    },
  );
  test('large directory index can be reused without rescanning or sorting', () {
    final entries = List.generate(
      30000,
      (i) => ArchiveEntry(
        path: 'folder${i % 100}/file$i.txt',
        size: 1,
        directory: false,
      ),
    );
    final index = ArchiveIndex(entries);
    expect(index.inFolder('').length, 100);
    expect(index.inFolder('folder50').length, 300);
    expect(
      identical(index.inFolder('folder50'), index.inFolder('folder50')),
      isTrue,
    );
    expect(index.sizes['folder50'], 300);
  });
  test(
    'text preview bounds layout while preserving the original file bytes',
    () {
      final bytes = Uint8List.fromList(List.filled(100000, 65));
      final text = decodePreviewText(bytes);
      expect(text.length, lessThan(66000));
      expect(text, contains('预览已截断'));
      expect(bytes.length, 100000);
      expect(decodePreviewText(Uint8List.fromList('hello'.codeUnits)), 'hello');
    },
  );
}
