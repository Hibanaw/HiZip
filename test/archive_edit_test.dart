import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:path/path.dart' as p;

void main() {
  final enabled = Platform.environment['HIZIP_NATIVE_LIBRARY'] != null;
  for (final format in ['zip', 'tar.gz', '7z']) {
    test(
      'create and delete entries in $format without losing other contents',
      () async {
        final root = await Directory.systemTemp.createTemp('hizip-edit-');
        final service = ArchiveService(
          temporaryRoot: p.join(root.path, 'cache'),
        );
        try {
          final source = File(p.join(root.path, 'source.txt'));
          await source.writeAsString('keep this content');
          final archive = p.join(root.path, 'test.$format');
          await NativeArchive.create(
            archive,
            [source.path, source.path, source.path],
            ['keep.txt', 'folder/nested/file.txt', 'folderish/file.txt'],
          );
          var doc = await service.read(archive);
          doc = await service.createEntry(doc, '', '空目录', directory: true);
          expect(doc.index.byNormalized['空目录']!.directory, true);
          doc = await service.createEntry(doc, '空目录', '空白.txt');
          final blank = doc.index.byNormalized['空目录/空白.txt']!;
          expect(blank.size, 0);
          expect(await service.preview(doc, blank), isEmpty);
          doc = await service.createEntry(doc, '空目录', '空白.txt');
          expect(doc.index.byNormalized.containsKey('空目录/空白 2.txt'), true);
          doc = await service.deleteEntries(doc, [
            doc.index.byNormalized['folder']!,
            doc.index.byNormalized['空目录/空白.txt']!,
          ]);
          expect(
            doc.entries.any((e) => e.normalized.startsWith('folder/')),
            false,
          );
          expect(
            doc.index.byNormalized.containsKey('folderish/file.txt'),
            true,
          );
          expect(doc.index.byNormalized.containsKey('空目录/空白.txt'), false);
          expect(
            String.fromCharCodes(
              await service.preview(doc, doc.index.byPath['keep.txt']!),
            ),
            'keep this content',
          );
          final before = await File(archive).readAsBytes();
          await expectLater(
            service.createEntry(doc, '', '../escape.txt'),
            throwsStateError,
          );
          final readonly = ArchiveDocument(
            doc.path,
            doc.entries,
            doc.format,
            false,
          );
          await expectLater(
            service.deleteEntries(readonly, doc.entries),
            throwsStateError,
          );
          expect(await File(archive).readAsBytes(), before);
          doc = await service.deleteEntries(doc, doc.index.inFolder(''));
          expect(doc.entries, isEmpty);
          doc = await service.createEntry(doc, '', 'again.txt');
          expect(doc.entries.single.path, 'again.txt');
        } finally {
          await service.dispose();
          await root.delete(recursive: true);
        }
      },
      skip: enabled ? false : 'Set HIZIP_NATIVE_LIBRARY',
    );
  }
}
