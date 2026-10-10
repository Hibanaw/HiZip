import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/archive_properties.dart';
import 'package:hizip/services/archive_service.dart';

void main() {
  final doc = ArchiveDocument(
    '/sample.zip',
    const [
      ArchiveEntry(path: 'docs/a.txt', size: 12, directory: false),
      ArchiveEntry(path: 'docs/b.txt', size: 7, directory: false),
      ArchiveEntry(path: 'root.txt', size: 5, directory: false),
    ],
    'ZIP',
    true,
    comment: 'Original comment',
  );

  test(
    'folder properties preserve counts and sizes without sending descendants',
    () {
      final data = archivePropertiesSnapshot(doc, '', [
        doc.index.byPath['docs']!,
      ]);
      expect(data['size'], 19);
      expect(data['itemCount'], 2);
      expect(data['currentCount'], 2);
      expect((data['selection'] as List).length, 1);
      expect(archivePropertiesDocument(data).comment, 'Original comment');
    },
  );

  test('mixed parent and child selections do not double-count contents', () {
    final data = archivePropertiesSnapshot(doc, '', [
      doc.index.byPath['docs']!,
      doc.entries.first,
      doc.entries.last,
    ]);
    expect(data['size'], 24);
    expect(data['selectionCount'], 3);
    expect(data['folderCount'], 1);
  });

  test(
    'large selections send only three icons while keeping the full summary',
    () {
      final entries = List.generate(
        10000,
        (i) => ArchiveEntry(path: '$i.txt', size: 1, directory: false),
      );
      final data = archivePropertiesSnapshot(
        ArchiveDocument('/large.zip', entries, 'ZIP', true),
        '',
        entries,
      );
      expect(data['selectionCount'], 10000);
      expect(data['size'], 10000);
      expect((data['selection'] as List).length, 3);
      expect(jsonEncode(data).length, lessThan(2000));
    },
  );
}
