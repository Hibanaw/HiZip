import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_formats.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/rar_volumes.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:path/path.dart' as p;

void main() {
  test('recognizes and normalizes new and old RAR volume names', () {
    expect(isReadableArchivePath('/archives/name.part002.RAR'), true);
    expect(isReadableArchivePath('/archives/name.R00'), true);
    expect(isReadableArchivePath('/archives/name.s99'), true);
    expect(isReadableArchivePath('/archives/name.r001'), false);
    expect(readableArchivePickerExtensions, containsAll(['rar', 'r00', 'r99']));
    expect(writableArchiveFormats.containsKey('rar'), false);
    expect(
      RarVolumes.firstPath('/archives/name.part002.RAR'),
      '/archives/name.part001.RAR',
    );
    expect(RarVolumes.firstPath('/archives/name.r03'), '/archives/name.rar');
    expect(RarVolumes.firstPath('/archives/name.R99'), '/archives/name.RAR');
    expect(
      RarVolumes.firstPath('/archives/ordinary.rar'),
      '/archives/ordinary.rar',
    );
    expect(
      () => RarVolumes.firstPath('/archives/name.part0.rar'),
      throwsStateError,
    );
  });

  group('native RAR service', () {
    late Directory root;
    late ArchiveService service;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('hizip-rar-');
      service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
    });
    tearDown(() async {
      await service.dispose();
      await root.delete(recursive: true);
    });
    String fixture(String name) =>
        File('test/fixtures/rar/test_read_format_$name.rar').absolute.path;

    for (final version in [4, 5]) {
      for (final variant in ['solid_encrypted', 'solid_encrypted_filenames']) {
        test(
          'RAR$version $variant unlock, preview, extract and password disposal',
          () async {
            final path = fixture('rar${version}_$variant');
            if (variant.endsWith('filenames')) {
              await expectLater(service.read(path), throwsStateError);
            } else {
              final locked = await service.read(path);
              expect(locked.entries.every((entry) => !entry.canExtract), true);
            }
            await expectLater(
              service.readWithPassword(path, 'wrong'),
              throwsStateError,
            );
            final doc = await service.readWithPassword(path, 'password');
            expect(doc.writable, false);
            expect(doc.entries.every((entry) => entry.canExtract), true);
            expect(
              utf8.decode(await service.preview(doc, doc.entries.last)),
              'This is from d.txt',
            );
            final destination = await Directory(p.join(root.path, 'extracted'))
                .create();
            final output = await service.extract(doc, destination.path);
            expect(
              await File(p.join(output, 'a.txt')).readAsString(),
              'This is from a.txt',
            );
            expect(
              await File(p.join(output, 'd.txt')).readAsString(),
              'This is from d.txt',
            );
            expect((await service.verify(doc))['bytes'], 72);
            await service.closeArchive(path);
            await expectLater(NativeArchive.verify(path), throwsStateError);
            if (variant.endsWith('filenames')) {
              await expectLater(service.read(path), throwsStateError);
            } else {
              expect((await service.read(path)).password, isEmpty);
            }
          },
        );
      }
    }

    test('opening any new-style volume uses one logical archive and native volume reads', () async {
      final base = 'test_read_format_rar5_multiarchive_solid';
      for (var i = 1; i <= 4; i++) {
        final name = '$base.part${i.toString().padLeft(2, '0')}.rar';
        await File('test/fixtures/rar/$name').copy(p.join(root.path, name));
      }
      final first = p.join(root.path, '$base.part01.rar');
      final doc = await service.read(p.join(root.path, '$base.part03.rar'));
      expect(doc.path, first);
      expect(doc.nativePath, first);
      expect(doc.entries.length, 9);
      expect(doc.writable, false);
      final last = doc.entries.last;
      final exported = await service.exportEntries(doc, [last]);
      expect(await File(exported.single).length(), last.size);
      await File(p.join(root.path, '$base.part04.rar')).delete();
      await expectLater(
        service.read(first),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Missing RAR volume'),
          ),
        ),
      );
    });

    test(
      'missing first volume is reported before opening a partial archive',
      () async {
        final path = p.join(root.path, 'archive.part02.rar');
        await File(path).writeAsBytes([1, 2, 3]);
        await expectLater(
          service.read(path),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('First RAR volume'),
            ),
          ),
        );
      },
    );

    test('legacy RAR volume opens from r00 and extracts a later file', () async {
      for (var i = 1; i <= 4; i++) {
        final fixtureName =
            'test_read_format_rar_multivolume.part${i.toString().padLeft(4, '0')}.rar';
        final name = i == 1
            ? 'legacy.rar'
            : 'legacy.r${(i - 2).toString().padLeft(2, '0')}';
        await File('test/fixtures/rar/$fixtureName')
            .copy(p.join(root.path, name));
      }
      final doc = await service.read(p.join(root.path, 'legacy.r00'));
      expect(doc.path, p.join(root.path, 'legacy.rar'));
      expect(doc.format, 'RAR 4');
      expect(doc.entries.length, 7);
      final entry = doc.entries.singleWhere(
        (entry) => entry.path == 'testdir/test.txt',
      );
      expect((await service.preview(doc, entry)).length, 20);
    });

    test('external RAR file is read-only, excluded from changes and cleaned on close', () async {
      final path = fixture('rar5_unicode');
      final doc = await service.read(path);
      final before = await File(path).readAsBytes();
      final opened = await service.prepareExternal(doc, doc.entries.first);
      expect(opened.readOnly, true);
      expect(
        identical(
          await service.prepareExternal(doc, doc.entries.first),
          opened,
        ),
        true,
      );
      if (!Platform.isWindows) {
        expect((await File(opened.path).stat()).mode & 0x92, 0); // 0222
        expect((await File(opened.path).parent.stat()).mode & 0x92, 0);
        await expectLater(
          File(opened.path).writeAsString('changed'),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          File(opened.path).rename('${opened.path}.replacement'),
          throwsA(isA<FileSystemException>()),
        );
      }
      expect(await service.changes(), isEmpty);
      await expectLater(service.save(opened), throwsStateError);
      expect(await File(path).readAsBytes(), before);
      final temporaryDirectory = File(opened.path).parent;
      await service.closeArchive(path);
      expect(await temporaryDirectory.exists(), false);
    });

    test(
      'writable archives keep writable external copies and change monitoring',
      () async {
        final source = await File(p.join(root.path, 'source.txt'))
            .writeAsString('original');
        final path = p.join(root.path, 'writable.zip');
        await service.create(path, [source.path]);
        final doc = await service.read(path);
        final opened = await service.prepareExternal(doc, doc.entries.single);
        expect(opened.readOnly, false);
        await File(opened.path).writeAsString('changed content');
        expect(await service.changes(), [opened]);
        await service.save(opened);
        final updated = await service.read(path);
        expect(
          utf8.decode(await service.preview(updated, updated.entries.single)),
          'changed content',
        );
      },
    );

    test(
      'nested archives opened from read-only parents inherit read-only status',
      () async {
        final source = await File(p.join(root.path, 'source.txt'))
            .writeAsString('nested');
        final inner = p.join(root.path, 'inner.zip');
        final outer = p.join(root.path, 'outer.zip');
        await service.create(inner, [source.path]);
        await service.create(outer, [inner]);
        final original = await service.read(outer);
        final readOnly = ArchiveDocument(
          original.path,
          original.entries,
          original.format,
          false,
        );
        final prepared = await service.prepareExternal(
          readOnly,
          readOnly.entries.single,
        );
        final nested = await service.read(prepared.path);
        expect(nested.writable, false);
        expect(
          utf8.decode(await service.preview(nested, nested.entries.single)),
          'nested',
        );
        final file = await service.prepareExternal(
          nested,
          nested.entries.single,
        );
        expect(file.readOnly, true);
      },
    );
  }, skip: Platform.environment['HIZIP_NATIVE_LIBRARY'] == null);
}
