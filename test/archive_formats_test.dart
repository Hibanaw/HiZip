import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_formats.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('recognizes archive paths case-insensitively', () {
    expect(isReadableArchivePath('/tmp/archive.zip'), isTrue);
    expect(isReadableArchivePath('/tmp/archive.TAR.Z'), isTrue);
    expect(isReadableArchivePath('/tmp/document.txt'), isFalse);
  });

  for (final extension in [
    'zip',
    '7z',
    'tar',
    'tar.gz',
    'tar.bz2',
    'tar.xz',
    'tar.lzma',
    'tar.zst',
    'tar.lz4',
    'tar.lzip',
    'tar.Z',
    'cpio',
    'ar',
    'gz',
    'bz2',
    'xz',
    'lzma',
    'zst',
    'lz4',
    'lzip',
    'Z',
  ]) {
    test('service round trip preserves $extension during edits', () async {
      final root = await Directory.systemTemp.createTemp('hizip-formats-');
      final service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
      try {
        final source = File(p.join(root.path, '中文.txt'));
        await source.writeAsString('original');
        final archive = p.join(root.path, '中文.txt.$extension');
        await service.create(archive, [source.path]);
        final doc = await service.read(archive);
        expect(doc.writable, isTrue);
        expect(doc.entries.single.path, '中文.txt');
        final opened = await service.prepareExternal(doc, doc.entries.single);
        await File(opened.path).writeAsString('modified');
        await service.save(opened);
        final updated = await service.read(archive);
        expect(updated.format, doc.format);
        expect(
          String.fromCharCodes(
            await service.preview(updated, updated.entries.single),
          ),
          'modified',
        );
        if ([
          'zip',
          '7z',
          'tar',
          'tar.gz',
          'tar.bz2',
          'tar.xz',
          'tar.lzma',
          'tar.zst',
          'tar.lz4',
          'tar.lzip',
          'tar.Z',
          'cpio',
          'ar',
        ].contains(extension)) {
          final added = File(p.join(root.path, 'second.txt'));
          await added.writeAsString('second');
          final imported = await service.importFiles(updated, [added.path], '');
          expect(imported.entries.map((e) => e.path), contains('second.txt'));
          expect(imported.format, doc.format);
        }
      } finally {
        await service.dispose();
        await root.delete(recursive: true);
      }
    }, skip: Platform.environment['HIZIP_NATIVE_LIBRARY'] == null);
  }
}
