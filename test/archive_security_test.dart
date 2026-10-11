import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_create_options.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:path/path.dart' as p;

void main() {
  group('password and ZIP configuration', () {
    late Directory root;
    late ArchiveService service;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('hizip-security-');
      service = ArchiveService(temporaryRoot: root.path);
    });
    tearDown(() async {
      await service.dispose();
      await root.delete(recursive: true);
    });
    Future<String> encryptedArchive() async {
      final one = await File(p.join(root.path, '中文.txt')).writeAsString('中文秘密');
      final two = await File(p.join(root.path, 'second.txt'))
          .writeAsString('second secret');
      final output = p.join(root.path, 'encrypted.zip');
      await service.createWithOptions(output, [
        one.path,
        two.path,
      ], const ArchiveCreateOptions(password: '密码🔑', encryption: 'aes256'));
      return output;
    }

    test(
      'runtime capabilities expose supported formats and crypto limits',
      () async {
        final capabilities = await service.capabilities();
        expect(capabilities['zipAES256'], isA<bool>());
        expect(capabilities['writableFormats'], containsAll(['zip', 'tar']));
        expect(capabilities['encryptedUpdates'], false);
        expect(capabilities['headerEncryption'], false);
      },
    );
    test(
      'AES password unlock covers preview, batch extraction and exports',
      () async {
        final archive = await encryptedArchive();
        await service.closeArchive(archive);
        final locked = await service.read(archive);
        expect(
          locked.entries.every((entry) => entry.encrypted && !entry.canExtract),
          true,
        );
        await expectLater(
          service.readWithPassword(archive, 'wrong'),
          throwsStateError,
        );
        expect(
          (await service.read(archive)).entries
              .every((entry) => !entry.canExtract),
          true,
        );
        final doc = await service.readWithPassword(archive, '密码🔑');
        expect(doc.writable, false);
        expect(
          doc.entries.every((entry) => entry.encrypted && entry.canExtract),
          true,
        );
        expect(
          utf8.decode(await service.preview(doc, doc.entries.first)),
          '中文秘密',
        );
        final destination = await Directory(p.join(root.path, 'extracted'))
            .create();
        final extracted = await service.extract(doc, destination.path);
        expect(await File(p.join(extracted, '中文.txt')).readAsString(), '中文秘密');
        expect(
          await File(p.join(extracted, 'second.txt')).readAsString(),
          'second secret',
        );
        final exports = await service.exportEntries(doc, doc.entries);
        expect(exports.length, 2);
        expect(await File(exports.first).readAsString(), '中文秘密');
        expect((await service.verify(doc))['files'], 2);
      },
    );
    test(
      'encrypted nested archive can be opened from the prepared cache',
      () async {
        final text = await File(p.join(root.path, 'nested.txt'))
            .writeAsString('nested content');
        final inner = p.join(root.path, 'inner.zip');
        await service.create(inner, [text.path]);
        final outer = p.join(root.path, 'outer.zip');
        await service.createWithOptions(
          outer,
          [inner],
          const ArchiveCreateOptions(
            password: 'outer password',
            encryption: 'aes256',
          ),
        );
        await service.closeArchive(outer);
        final doc = await service.readWithPassword(outer, 'outer password');
        final prepared = await service.prepareExternal(doc, doc.entries.single);
        final nested = await service.read(prepared.path);
        expect(
          utf8.decode(await service.preview(nested, nested.entries.single)),
          'nested content',
        );
        expect(doc.writable, false);
      },
    );
    test('closing drops the session password and no password leaks to later operations', () async {
      final archive = await encryptedArchive();
      final doc = await service.read(archive);
      expect(doc.entries.first.canExtract, true);
      await service.closeArchive(archive);
      expect((await service.read(archive)).entries.first.canExtract, false);
      await expectLater(NativeArchive.verify(archive), throwsStateError);
      final source = await File(p.join(root.path, 'plain.txt'))
          .writeAsString('plain');
      final plain = p.join(root.path, 'plain.zip');
      await service.create(plain, [source.path]);
      expect((await service.read(plain)).entries.single.encrypted, false);
      expect((await NativeArchive.verify(plain))['files'], 1);
    });
    test(
      'Store is actually written to ZIP headers and content round trips',
      () async {
        final source = await File(p.join(root.path, 'source.txt'))
            .writeAsString('data' * 100);
        final output = p.join(root.path, 'stored.zip');
        await service.createWithOptions(output, [
          source.path,
        ], const ArchiveCreateOptions(zipCompression: 'store'));
        final bytes = await File(output).readAsBytes();
        expect(ByteData.sublistView(bytes).getUint16(8, Endian.little), 0);
        final doc = await service.read(output);
        expect(
          utf8.decode(await service.preview(doc, doc.entries.single)),
          'data' * 100,
        );
      },
    );
    test(
      'invalid encryption requests never commit an unencrypted fallback',
      () async {
        final source = await File(p.join(root.path, 'source.txt'))
            .writeAsString('data');
        final output = p.join(root.path, 'bad.7z');
        await expectLater(
          service.createWithOptions(
            output,
            [source.path],
            const ArchiveCreateOptions(
              password: 'secret',
              encryption: 'aes256',
            ),
          ),
          throwsStateError,
        );
        expect(await File(output).exists(), false);
        await expectLater(
          service.createWithOptions(
            p.join(root.path, 'empty.zip'),
            [],
            const ArchiveCreateOptions(
              password: 'secret',
              encryption: 'aes256',
            ),
          ),
          throwsStateError,
        );
        await expectLater(
          NativeArchive.create(
            p.join(root.path, 'null.zip'),
            [source.path],
            ['source.txt'],
            password: 'a\u0000b',
            encryption: 'aes256',
          ),
          throwsArgumentError,
        );
      },
    );
    test(
      'worker passwords remain isolated during concurrent verification',
      () async {
        final archive = await encryptedArchive();
        final results = await Future.wait([
          NativeArchive.verify(
            archive,
            password: '密码🔑',
          ).then((value) => value['ok'], onError: (_) => false),
          NativeArchive.verify(
            archive,
            password: 'wrong',
          ).then((_) => true, onError: (_) => false),
        ]);
        expect(results, [true, false]);
      },
    );
  }, skip: Platform.environment['HIZIP_NATIVE_LIBRARY'] == null);
}
