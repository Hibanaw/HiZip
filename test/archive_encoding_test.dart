import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_preferences.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service_io.dart';

void main() {
  test(
    'archive defaults persist and invalid encodings fall back safely',
    () async {
      String? stored;
      AppSettings create() => AppSettings(
        readArchive: () async => stored,
        writeArchive: (value) async => stored = value,
        read: () async => null,
        readTheme: () async => null,
        readHighlight: () async => null,
        readBrowsing: () async => null,
      );
      final first = create();
      await first.setArchive(
        const ArchivePreferences(
          readEncoding: 'BIG5',
          createEncoding: 'GB18030',
          compressionLevel: 0,
        ),
      );
      final restored = create();
      await restored.load();
      expect(restored.archive.toJson(), first.archive.toJson());
      expect(
        ArchivePreferences.fromJson({
          'readEncoding': 'bad',
          'createEncoding': 'auto',
          'compressionLevel': 10,
        }).toJson(),
        const ArchivePreferences().toJson(),
      );
      first.dispose();
      restored.dispose();
    },
  );

  test('legacy ZIP encoding survives auto detection, preview, export, extraction and write-back', () async {
    final root = await Directory.systemTemp.createTemp('hizip-encoding-test-');
    final service = ArchiveService(temporaryRoot: root.path)
      ..createEncoding = 'GB18030'
      ..compressionLevel = 0;
    try {
      final input = File('${root.path}/资料.txt');
      await input.writeAsString('old content');
      final zip = '${root.path}/legacy.zip';
      await service.create(zip, [input.path]);
      final doc = await service.read(zip);
      expect(doc.encoding, 'auto');
      expect(doc.resolvedEncoding, 'GB18030');
      expect(doc.entries.single.path, '资料.txt');
      expect(
        utf8.decode(await service.preview(doc, doc.entries.single)),
        'old content',
      );
      final exports = await service.exportEntries(doc, doc.entries);
      expect(await File(exports.single).readAsString(), 'old content');
      final output = await service.extract(doc, root.path);
      expect(await File('$output/资料.txt').readAsString(), 'old content');
      final watched = await service.prepareExternal(doc, doc.entries.single);
      await File(watched.path).writeAsString('changed');
      await service.save(watched);
      final updated = await service.read(zip);
      expect(updated.entries.single.path, '资料.txt');
      expect(
        utf8.decode(await service.preview(updated, updated.entries.single)),
        'changed',
      );
      service.readEncoding = 'GB18030';
      expect((await service.read(zip)).encoding, 'GB18030');
      service.createEncoding = 'UTF-8';
      service.compressionLevel = 9;
      await service.create('${root.path}/utf8.zip', [input.path]);
      expect(
        (await service.read('${root.path}/utf8.zip')).entries.single.path,
        '资料.txt',
      );
    } finally {
      await service.dispose();
      await root.delete(recursive: true);
    }
  }, skip: Platform.environment['HIZIP_NATIVE_LIBRARY'] == null);
}
