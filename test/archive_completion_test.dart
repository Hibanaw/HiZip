import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_create_options.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/archive_task_queue.dart';
import 'package:hizip/services/archive_volumes.dart';
import 'package:hizip/services/extraction_transaction.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:hizip_native/zip_metadata.dart';
import 'package:path/path.dart' as p;

const fixture =
    'UEsDBBQAAAAAAAAAIQCvHSe+BwAAAAcAAAAMAAAAZm9sZGVyL2EudHh0aW5pdGlhbFBLAwQUAAAACAAraEpdIDVY2QcAAAAFAAAACQAAAG90aGVyLnR4dMsvyUgtAgBQSwECFAMUAAAAAAAAACEArx0nvgcAAAAHAAAADAAAAA0AAAAAAAAAgAEAAAAAZm9sZGVyL2EudHh0ZW50cnkgY29tbWVudFBLAQIUAxQAAAAIACtoSl0gNVjZBwAAAAUAAAAJAAAAAAAAAAAAAACAATEAAABvdGhlci50eHRQSwUGAAAAAAIAAgB+AAAAXwAAAAwA5YyF5rOo6YeK4pyT';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('hizip-completion-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<File> sample() =>
      File(p.join(root.path, 'sample.zip'))
          .writeAsBytes(base64.decode(fixture));

  test('ZIP comment edit preserves entry comments and payload bytes', () async {
    final file = await sample(),
        before = ZipMetadata.read(p.join(root.path, 'sample.zip'))!;
    ZipMetadata.setComment(file.path, '新的注释 😀');
    final after = ZipMetadata.read(file.path)!;
    expect(after.text, '新的注释 😀');
    expect(after.entries.first.comment, before.entries.first.comment);
    expect(
      (await file.readAsBytes()).sublist(0, before.centralOffset),
      base64.decode(fixture).sublist(0, before.centralOffset),
    );
    ZipMetadata.setComment(file.path, '');
    expect(ZipMetadata.read(file.path)!.comment, isEmpty);
  });
  test(
    'ZIP64 comment changes preserve central directory and locator',
    () async {
      final file = await sample(), metadata = ZipMetadata.read(file.path)!;
      final original = await file.readAsBytes();
      final record = Uint8List(56), locator = Uint8List(20);
      final r = ByteData.sublistView(record), l = ByteData.sublistView(locator);
      r.setUint32(0, 0x06064b50, Endian.little);
      r.setUint64(4, 44, Endian.little);
      r.setUint16(12, 45, Endian.little);
      r.setUint16(14, 45, Endian.little);
      r.setUint64(24, 2, Endian.little);
      r.setUint64(32, 2, Endian.little);
      r.setUint64(40, metadata.centralSize, Endian.little);
      r.setUint64(48, metadata.centralOffset, Endian.little);
      l.setUint32(0, 0x07064b50, Endian.little);
      l.setUint64(8, metadata.endOffset, Endian.little);
      l.setUint32(16, 1, Endian.little);
      final end = Uint8List.fromList(original.sublist(metadata.endOffset));
      final e = ByteData.sublistView(end);
      e.setUint16(8, 0xffff, Endian.little);
      e.setUint16(10, 0xffff, Endian.little);
      e.setUint32(12, 0xffffffff, Endian.little);
      e.setUint32(16, 0xffffffff, Endian.little);
      await file.writeAsBytes([
        ...original.sublist(0, metadata.endOffset),
        ...record,
        ...locator,
        ...end,
      ]);
      ZipMetadata.setComment(file.path, 'ZIP64 注释');
      final changed = ZipMetadata.read(file.path)!;
      expect(changed.text, 'ZIP64 注释');
      expect(changed.entries.first.comment, metadata.entries.first.comment);
      expect(changed.centralOffset, metadata.centralOffset);
      expect(changed.zip64Offset, metadata.endOffset);
      if (Platform.environment.containsKey('HIZIP_NATIVE_LIBRARY')) {
        await NativeArchive.verify(file.path);
      }
    },
  );
  test('comment byte limit is checked without damaging the archive', () async {
    final file = await sample(),
        bytes = await File(p.join(root.path, 'sample.zip')).readAsBytes();
    expect(
      () => ZipMetadata.setComment(file.path, '汉' * 22000),
      throwsFormatException,
    );
    expect(await file.readAsBytes(), bytes);
  });
  test('unflagged legacy names are not guessed as UTF-8', () async {
    final file = await sample(), metadata = ZipMetadata.read(file.path)!;
    final bytes = await file.readAsBytes();
    // These bytes form valid UTF-8 but the entry does not declare UTF-8.
    bytes[metadata.centralOffset + 46] = 0xc3;
    bytes[metadata.centralOffset + 47] = 0xa9;
    await file.writeAsBytes(bytes);
    final entry = ZipMetadata.read(file.path)!.entries.first;
    expect(entry.name, isNull);
    expect(entry.comment, metadata.entries.first.comment);
  });
  test('malformed central directory bounds are rejected', () async {
    final file = await sample(),
        bytes = await File(p.join(root.path, 'sample.zip')).readAsBytes();
    bytes[bytes.length - 12 - 22 + 16] = 0xff;
    await file.writeAsBytes(bytes);
    expect(() => ZipMetadata.read(file.path), throwsFormatException);
  });
  group('transaction publication', () {
    for (final policy in [
      ExtractionConflictPolicy.overwrite,
      ExtractionConflictPolicy.skip,
      ExtractionConflictPolicy.rename,
    ]) {
      test('conflict policy $policy preserves the appropriate data', () async {
        final staging = await root.createTemp('stage-'),
            destination = await Directory(p.join(root.path, 'out')).create();
        await File(p.join(staging.path, 'a.txt')).writeAsString('new');
        await File(p.join(destination.path, 'a.txt')).writeAsString('old');
        await publishExtraction(staging, destination.path, policy);
        expect(
          await File(p.join(destination.path, 'a.txt')).readAsString(),
          policy == ExtractionConflictPolicy.overwrite ? 'new' : 'old',
        );
        expect(
          await File(p.join(destination.path, 'a 2.txt')).exists(),
          policy == ExtractionConflictPolicy.rename,
        );
      });
    }
    test(
      'cancelling an ask decision leaves all destination files unchanged',
      () async {
        final staging = await root.createTemp('stage-'),
            destination = await Directory(p.join(root.path, 'out')).create();
        await File(p.join(staging.path, 'new.txt')).writeAsString('new');
        await File(p.join(staging.path, 'a.txt')).writeAsString('replacement');
        await File(p.join(destination.path, 'a.txt')).writeAsString('old');
        await expectLater(
          publishExtraction(
            staging,
            destination.path,
            ExtractionConflictPolicy.ask,
            resolve: (_) async => null,
          ),
          throwsA(isA<ArchiveOperationCancelled>()),
        );
        expect(
          await File(p.join(destination.path, 'a.txt')).readAsString(),
          'old',
        );
        expect(await File(p.join(destination.path, 'new.txt')).exists(), false);
      },
    );
    test('publication failure restores all overwritten files', () async {
      final staging = await root.createTemp('stage-'),
          destination = await root.createTemp('out-');
      for (final name in ['a', 'b']) {
        await File(p.join(staging.path, name)).writeAsString('new $name');
        await File(p.join(destination.path, name)).writeAsString('old $name');
      }
      var calls = 0;
      await expectLater(
        publishExtraction(
          staging,
          destination.path,
          ExtractionConflictPolicy.overwrite,
          publish: (source, target) async {
            if (++calls == 2) {
              throw const FileSystemException('Simulated disk full');
            }
            await NativeArchive.commitNew(source, target);
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      for (final name in ['a', 'b']) {
        expect(
          await File(p.join(destination.path, name)).readAsString(),
          'old $name',
        );
      }
    });
    test(
      'rollback retains backups when published data changed externally',
      () async {
        final staging = await root.createTemp('stage-'),
            destination = await root.createTemp('out-');
        for (final name in ['a', 'b']) {
          await File(p.join(staging.path, name)).writeAsString('new $name');
          await File(p.join(destination.path, name)).writeAsString('old $name');
        }
        var calls = 0;
        await expectLater(
          publishExtraction(
            staging,
            destination.path,
            ExtractionConflictPolicy.overwrite,
            publish: (source, target) async {
              if (++calls == 2) {
                await File(p.join(destination.path, 'a'))
                    .writeAsString('external edit');
                throw const FileSystemException('Simulated disk full');
              }
              await NativeArchive.commitNew(source, target);
            },
          ),
          throwsA(isA<ExtractionRecoveryRequired>()),
        );
        expect(
          await File(p.join(destination.path, 'a')).readAsString(),
          'external edit',
        );
        final backup =
            (await staging
                    .list()
                    .where(
                      (e) =>
                          e is Directory &&
                          p.basename(e.path).startsWith('recovery-'),
                    )
                    .first)
                .path;
        final journal = jsonDecode(
          await File(p.join(backup, 'journal.json')).readAsString(),
        ) as Map;
        for (final name in ['a', 'b']) {
          expect(
            await File(
              (journal['backups'] as Map)[p.join(
                    await destination.resolveSymbolicLinks(),
                    name,
                  )]
                  as String,
            ).readAsString(),
            'old $name',
          );
        }
      },
    );
    test('folder merge skips existing files and adds new files', () async {
      final staging = await root.createTemp('stage-'),
          destination = await Directory(p.join(root.path, 'out')).create();
      await Directory(p.join(staging.path, 'folder')).create();
      await Directory(p.join(destination.path, 'folder')).create();
      await File(p.join(staging.path, 'folder/a')).writeAsString('new');
      await File(p.join(staging.path, 'folder/b')).writeAsString('added');
      await File(p.join(destination.path, 'folder/a')).writeAsString('old');
      await publishExtraction(
        staging,
        destination.path,
        ExtractionConflictPolicy.skip,
      );
      expect(
        await File(p.join(destination.path, 'folder/a')).readAsString(),
        'old',
      );
      expect(
        await File(p.join(destination.path, 'folder/b')).readAsString(),
        'added',
      );
    });
    test('existing symlink folder is replaced rather than followed', () async {
      final staging = await root.createTemp('stage-'),
          destination = await Directory(p.join(root.path, 'out')).create(),
          outside = await root.createTemp('outside-');
      await Directory(p.join(staging.path, 'folder')).create();
      await File(p.join(staging.path, 'folder/a')).writeAsString('new');
      await File(p.join(outside.path, 'a')).writeAsString('outside');
      await Link(p.join(destination.path, 'folder')).create(outside.path);
      await publishExtraction(
        staging,
        destination.path,
        ExtractionConflictPolicy.overwrite,
      );
      expect(await File(p.join(outside.path, 'a')).readAsString(), 'outside');
      expect(
        await File(p.join(destination.path, 'folder/a')).readAsString(),
        'new',
      );
    }, skip: Platform.isWindows);
  }, skip: Platform.environment['HIZIP_NATIVE_LIBRARY'] == null);

  test('failed tasks can retry and leave the queue clean', () async {
    final queue = ArchiveTaskQueue();
    var attempts = 0;
    Future<int> work() async {
      if (++attempts == 1) throw StateError('temporary failure');
      return 42;
    }

    await expectLater(
      queue.run('a.zip', 'read', work, retryable: true),
      throwsStateError,
    );
    expect(queue.tasks.single.failed, true);
    await queue.retry(queue.tasks.single);
    expect(attempts, 2);
    expect(queue.tasks, isEmpty);
    queue.dispose();
  });
  test('paused tasks can be cancelled before any work starts', () async {
    final queue = ArchiveTaskQueue();
    var worked = false;
    final gate = Completer<void>();
    final operation = queue.run('a.zip', 'read', () async {
      worked = true;
    }, after: gate.future);
    final check = expectLater(operation, throwsA(isA<ArchiveTaskCancelled>()));
    queue.pause(queue.tasks.single);
    queue.cancel(queue.tasks.single);
    gate.complete();
    await check;
    expect(worked, false);
    expect(queue.tasks, isEmpty);
    queue.dispose();
  });

  group('real engine completion', () {
    late ArchiveService service;
    setUp(() {
      service = ArchiveService(temporaryRoot: root.path);
    });
    tearDown(() async {
      await service.dispose();
    });
    test('rename, replace, import and delete retain ZIP comments', () async {
      final file = await sample();
      var doc = await service.read(file.path);
      expect(doc.comment, '包注释✓');
      doc = await service.renameEntry(doc, doc.entries.first, 'b.txt');
      expect(
        utf8.decode(ZipMetadata.read(file.path)!.entries.first.comment),
        'entry comment',
      );
      final opened = await service.prepareExternal(doc, doc.entries.first);
      await File(opened.path).writeAsString('replacement');
      await service.save(opened);
      doc = await service.read(file.path);
      final source = await File(p.join(root.path, 'add.txt'))
          .writeAsString('added');
      doc = await service.importFiles(doc, [source.path], '');
      doc = await service.deleteEntries(doc, [
        doc.entries.firstWhere((e) => e.path == 'other.txt'),
      ]);
      expect(doc.comment, '包注释✓');
      expect(
        utf8.decode(ZipMetadata.read(file.path)!.entries.first.comment),
        'entry comment',
      );
      expect(
        utf8.decode(await service.preview(doc, doc.entries.first)),
        'replacement',
      );
    });
    test('copy and move preserve entry comments at their new paths', () async {
      final file = await sample();
      var doc = await service.read(file.path);
      doc = await service.transferEntries(doc, [doc.entries.first], 'copies');
      var metadata = ZipMetadata.read(file.path)!;
      expect(
        utf8.decode(
          metadata.entries.firstWhere((e) => e.name == 'copies/a.txt').comment,
        ),
        'entry comment',
      );
      doc = await service.transferEntries(
        doc,
        [doc.entries.firstWhere((e) => e.path == 'copies/a.txt')],
        'moved',
        move: true,
      );
      metadata = ZipMetadata.read(file.path)!;
      expect(
        utf8.decode(
          metadata.entries.firstWhere((e) => e.name == 'moved/a.txt').comment,
        ),
        'entry comment',
      );
    });
    test('comment save rejects stale dialogs and retains payload', () async {
      final file = await sample(),
          doc = await service.read(p.join(root.path, 'sample.zip'));
      final updated = await service.writeComment(
        doc,
        'first edit',
        original: doc.comment,
      );
      await expectLater(
        service.writeComment(doc, 'stale edit', original: doc.comment),
        throwsStateError,
      );
      expect((await service.read(file.path)).comment, 'first edit');
      expect(
        utf8.decode(await service.preview(updated, updated.entries.first)),
        'initial',
      );
    });
    test(
      'volume creation, opening later parts and extraction round trip',
      () async {
        final source = File(p.join(root.path, 'source.bin'));
        final bytes = List<int>.generate(180000, (i) => i % 251);
        await source.writeAsBytes(bytes);
        final output = p.join(root.path, 'split.zip');
        await service.createWithOptions(
          output,
          [source.path],
          const ArchiveCreateOptions(
            zipCompression: 'store',
            volumeSize: 65536,
            comment: 'split comment',
          ),
        );
        final doc = await service.read('$output.002');
        expect(doc.path, '$output.001');
        expect(doc.writable, false);
        expect(doc.comment, 'split comment');
        final destination = await Directory(p.join(root.path, 'extract'))
            .create();
        await service.extract(doc, destination.path, roots: doc.entries);
        expect(
          await File(p.join(destination.path, 'source.bin')).readAsBytes(),
          bytes,
        );
        await File('$output.002').delete();
        await expectLater(service.read('$output.001'), throwsStateError);
      },
    );
    test(
      'volume checksum catches corruption and no existing part is overwritten',
      () async {
        final file = await sample(), output = p.join(root.path, 'split.zip');
        final staging = await root.createTemp('volumes-');
        await ArchiveVolumes.split(file.path, output, staging, 65536);
        final old = await File('$output.001').readAsBytes();
        await expectLater(
          ArchiveVolumes.split(file.path, output, staging, 65536),
          throwsStateError,
        );
        expect(await File('$output.001').readAsBytes(), old);
        old[10] ^= 1;
        await File('$output.001').writeAsBytes(old);
        await expectLater(service.read('$output.001'), throwsStateError);
      },
    );
    test(
      '7z continuous volumes round trip without changing source bytes',
      () async {
        final random = Random(19);
        final bytes = List<int>.generate(180000, (_) => random.nextInt(256));
        final source = await File(p.join(root.path, 'source.bin'))
            .writeAsBytes(bytes);
        final output = p.join(root.path, 'split.7z');
        await service.createWithOptions(output, [
          source.path,
        ], const ArchiveCreateOptions(volumeSize: 65536));
        expect(await File('$output.002').exists(), true);
        final doc = await service.read('$output.001');
        expect(doc.writable, false);
        final destination = await root.createTemp('out-');
        final path = await service.extract(
          doc,
          destination.path,
          roots: doc.entries,
        );
        expect(await File(path).readAsBytes(), bytes);
      },
    );
    test('native pause then cancel cleans up staged archive output', () async {
      final source = await File(p.join(root.path, 'source.txt'))
              .writeAsString('payload' * 1000),
          control = NativeOperationControl();
      control.pause();
      final output = p.join(root.path, 'cancelled.zip');
      final operation = NativeArchive.withControl(
        control,
        () => NativeArchive.create(output, [source.path], ['source.txt']),
      );
      final check = expectLater(
        operation,
        throwsA(isA<ArchiveOperationCancelled>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        await File(output).exists(),
        true,
      ); // Writer opened; its checkpoint blocks before the first entry.
      control.cancel();
      await check;
      expect(await File(output).exists(), false);
      control.dispose();
    });
    test('native resume completes a previously paused operation', () async {
      final file = await sample(), control = NativeOperationControl();
      control.pause();
      var complete = false;
      final operation = NativeArchive.withControl(
        control,
        () => NativeArchive.verify(file.path),
      ).then((_) => complete = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(complete, false);
      control.resume();
      await operation;
      expect(complete, true);
      control.dispose();
    });
  }, skip: Platform.environment['HIZIP_NATIVE_LIBRARY'] == null);
}
