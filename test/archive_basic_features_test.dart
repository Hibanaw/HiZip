import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:path/path.dart' as p;

void main() {
  group('native editing features', () {
    late Directory root;
    late ArchiveService service;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('hizip-basic-features-');
      service = ArchiveService(temporaryRoot: root.path);
    });
    tearDown(() async {
      await service.dispose();
      await root.delete(recursive: true);
    });
    Future<ArchiveDocument> fixture() async {
      final source = await File(p.join(root.path, 'source.txt'))
          .writeAsString('原始内容');
      final archive = p.join(root.path, 'sample.zip');
      await NativeArchive.create(
        archive,
        [source.path, source.path],
        ['folder/a.txt', 'other.txt'],
      );
      return service.read(archive);
    }

    test('empty containers can be opened and subsequently populated', () async {
      for (final extension in ['zip', '7z', 'tar']) {
        final path = p.join(root.path, 'empty.$extension');
        await service.create(path, []);
        final empty = await service.read(path);
        expect(empty.entries, isEmpty);
        final updated = await service.createEntry(empty, '', 'hello.txt');
        expect(updated.entries.single.path, 'hello.txt');
      }
    });
    test(
      'rename implicit folder retains all bytes and rejects collisions',
      () async {
        final doc = await fixture();
        final folder = doc.index.byNormalized['folder']!;
        final updated = await service.renameEntry(doc, folder, 'renamed');
        expect(updated.entries.map((e) => e.path), [
          'renamed/a.txt',
          'other.txt',
        ]);
        expect(
          utf8.decode(await service.preview(updated, updated.entries.first)),
          '原始内容',
        );
        await expectLater(
          service.renameEntry(updated, updated.entries.first, '../escape'),
          throwsStateError,
        );
        final file = await service.createEntry(updated, 'renamed', 'other.txt');
        await expectLater(
          service.renameEntry(file, file.entries.first, 'other.txt'),
          throwsStateError,
        );
      },
    );
    test(
      'rename keeps an existing external edit attached to its new path',
      () async {
        final doc = await fixture();
        final opened = await service.prepareExternal(doc, doc.entries.first);
        final updated = await service.renameEntry(
          doc,
          doc.entries.first,
          'new.txt',
        );
        expect(opened.entry, 'folder/new.txt');
        await File(opened.path).writeAsString('external edit');
        await service.save(opened);
        final finalDoc = await service.read(updated.path);
        expect(
          utf8.decode(await service.preview(finalDoc, finalDoc.entries.first)),
          'external edit',
        );
      },
    );
    test('integrity check detects damaged compressed payloads', () async {
      final doc = await fixture();
      final file = File(doc.path);
      final bytes = await file.readAsBytes();
      final header = ByteData.sublistView(bytes);
      final offset =
          30 +
          header.getUint16(26, Endian.little) +
          header.getUint16(28, Endian.little);
      bytes[offset] ^= 0xff;
      await file.writeAsBytes(bytes);
      await expectLater(service.verify(doc), throwsStateError);
    });
    test(
      'integrity check reads all data and returns counts without extraction',
      () async {
        final doc = await fixture();
        final report = await service.verify(doc);
        expect(report['files'], 2);
        expect(report['bytes'], utf8.encode('原始内容').length * 2);
      },
    );
  }, skip: Platform.environment['HIZIP_NATIVE_LIBRARY'] == null);
}
