import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_create_options.dart';
import 'package:hizip/models/finder_compression_request.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/finder_compression.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'Finder selection controls defaults and validates the native payload',
    () {
      for (final action in ['create', 'quickZip']) {
        for (final count in [1, 2, 3]) {
          final request = FinderCompressionRequest.fromPlatform({
            'action': action,
            'paths': List.generate(count, (index) => '/tmp/项目$index'),
          });
          expect(request.defaultNestInFolder, action == 'create' && count > 1);
        }
      }
      expect(
        FinderCompressionRequest.fromPlatform({
          'action': 'create',
          'paths': ['/tmp/a', '/tmp/a'],
        }).paths,
        ['/tmp/a'],
      );
      for (final payload in [
        null,
        {},
        {
          'action': 'delete',
          'paths': ['/tmp/a'],
        },
        {'action': 'create', 'paths': []},
        {
          'action': 'create',
          'paths': ['relative'],
        },
        {
          'action': 'create',
          'paths': ['/tmp/a\u0000'],
        },
        {
          'action': 'create',
          'paths': [1],
        },
      ]) {
        expect(
          () => FinderCompressionRequest.fromPlatform(payload),
          throwsFormatException,
        );
      }
    },
  );

  group(
    'Finder archive creation',
    () {
      late Directory root, selection;
      late ArchiveService service;
      setUp(() async {
        root = await Directory.systemTemp.createTemp('hizip-finder-');
        selection = await Directory(p.join(root.path, '选择')).create();
        service = ArchiveService(temporaryRoot: root.path);
      });
      tearDown(() async {
        await service.dispose();
        await root.delete(recursive: true);
      });

      test(
        'quick ZIP stays beside a single file and preserves existing outputs',
        () async {
          final source = await File(p.join(selection.path, '资料.txt'))
              .writeAsString('content');
          final existing = await File(p.join(selection.path, '资料.zip'))
              .writeAsString('existing');
          await Directory(p.join(selection.path, '资料 (2).zip')).create();
          final output = await createFinderQuickZip(service, [source.path]);
          expect(output, p.join(selection.path, '资料 (3).zip'));
          final archive = await service.read(output);
          expect(archive.entries.map((entry) => entry.path), ['资料.txt']);
          expect(
            await service.preview(archive, archive.entries.single),
            'content'.codeUnits,
          );
          expect(await existing.readAsString(), 'existing');
          expect(await source.readAsString(), 'content');
        },
      );

      test(
        'quick ZIP keeps a dotted folder name and adds no extra wrapper',
        () async {
          final folder = await Directory(p.join(selection.path, 'folder.v1'))
              .create();
          await File(p.join(folder.path, 'inside.txt')).writeAsString('inside');
          await Directory(p.join(folder.path, 'empty')).create();
          final output = await createFinderQuickZip(service, [folder.path]);
          expect(p.basename(output), 'folder.v1.zip');
          final archive = await service.read(output);
          expect(
            archive.entries.map((entry) => entry.path),
            containsAll([
              'folder.v1/',
              'folder.v1/inside.txt',
              'folder.v1/empty/',
            ]),
          );
          expect(
            archive.entries.any(
              (entry) => entry.path.startsWith('folder.v1/folder.v1/'),
            ),
            isFalse,
          );
        },
      );

      test('quick ZIP never nests multiple files or folders', () async {
        final file = await File(p.join(selection.path, 'a.txt'))
            .writeAsString('a');
        final folder = await Directory(p.join(selection.path, 'b')).create();
        await File(p.join(folder.path, 'c.txt')).writeAsString('c');
        final output = await createFinderQuickZip(service, [
          file.path,
          folder.path,
        ]);
        expect(output, p.join(selection.path, '选择.zip'));
        final archive = await service.read(output);
        expect(archive.entries.map((entry) => entry.path).toSet(), {
          'a.txt',
          'b/',
          'b/c.txt',
        });
      });

      test(
        'nesting uses the final archive name including compound formats',
        () async {
          final a = await File(p.join(selection.path, 'a.txt'))
              .writeAsString('a');
          final folder = await Directory(p.join(selection.path, 'folder'))
              .create();
          await File(p.join(folder.path, 'b.txt')).writeAsString('b');
          for (final format in ['zip', '7z', 'tar.gz']) {
            final output = p.join(selection.path, '新名称.$format');
            await service.createWithOptions(output, [
              a.path,
              folder.path,
            ], const ArchiveCreateOptions(nestInFolder: true));
            final archive = await service.read(output);
            expect(
              archive.entries
                  .where((entry) => !entry.directory)
                  .map((entry) => entry.path)
                  .toSet(),
              {'新名称/a.txt', '新名称/folder/b.txt'},
            );
            expect(archive.index.byNormalized['新名称']?.directory, isTrue);
          }
        },
      );

      test(
        'quick ZIP rejects a destination appearing after planning',
        () async {
          final file = await File(p.join(selection.path, 'a.txt'))
              .writeAsString('a');
          final planned = await availableFinderArchivePath([file.path], 'zip');
          await File(planned).writeAsString('arrived later');
          await expectLater(
            createFinderQuickZip(service, [file.path], output: planned),
            throwsStateError,
          );
          expect(await File(planned).readAsString(), 'arrived later');
        },
      );
    },
    skip: Platform.environment['HIZIP_NATIVE_LIBRARY'] == null
        ? 'Set HIZIP_NATIVE_LIBRARY to the compiled native engine'
        : false,
  );
}
