import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:path/path.dart' as p;

void main() {
  final enabled = Platform.environment['HIZIP_NATIVE_LIBRARY'] != null;
  test(
    'file transfers preserve contents, folders, names and transactional ZIP updates',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hizip-transfer-test-',
      );
      try {
        final service = ArchiveService(
          temporaryRoot: p.join(root.path, 'cache'),
        );
        final source = File(p.join(root.path, 'note.txt'))
          ..writeAsStringSync('original');
        final zip = p.join(root.path, 'sample.zip');
        await NativeArchive.create(zip, [source.path], ['folder/note.txt']);
        var doc = await service.read(zip);
        final initial = await File(zip).readAsBytes();
        final imported = Directory(p.join(root.path, '资料'))..createSync();
        File(p.join(imported.path, '中文.txt')).writeAsStringSync('中文内容');
        Directory(p.join(imported.path, '空目录')).createSync();
        doc = await service.importFiles(doc, [imported.path, source.path], '');
        expect(
          doc.entries.map((e) => e.normalized),
          containsAll([
            'folder/note.txt',
            '资料',
            '资料/中文.txt',
            '资料/空目录',
            'note.txt',
          ]),
        );
        doc = await service.importFiles(doc, [source.path], '');
        expect(doc.entries.map((e) => e.path), contains('note 2.txt'));
        doc = await service.transferEntries(
          doc,
          [doc.entries.firstWhere((e) => e.path == 'folder/note.txt')],
          '',
          move: false,
        );
        expect(doc.entries.map((e) => e.path), contains('note 3.txt'));
        final implicit = ArchiveEntry(path: 'folder', size: 0, directory: true);
        doc = await service.transferEntries(doc, [implicit], '资料', move: true);
        expect(
          doc.entries.map((e) => e.normalized),
          containsAll(['资料/folder', '资料/folder/note.txt']),
        );
        expect(doc.entries.any((e) => e.path == 'folder/note.txt'), false);
        final exports = await service.exportEntries(doc, [
          doc.entries.firstWhere((e) => e.normalized == '资料'),
        ]);
        expect(
          await File(p.join(exports.single, '中文.txt')).readAsString(),
          '中文内容',
        );
        expect(
          await File(p.join(exports.single, 'folder/note.txt')).readAsString(),
          'original',
        );
        expect(await Directory(p.join(exports.single, '空目录')).exists(), true);
        final before = await File(zip).readAsBytes();
        await expectLater(
          service.transferEntries(
            doc,
            [doc.entries.firstWhere((e) => e.normalized == '资料')],
            '资料/folder',
            move: true,
          ),
          throwsStateError,
        );
        await expectLater(
          service.importFiles(doc, [source.path], 'note.txt/child'),
          throwsStateError,
        );
        final link = Link(p.join(root.path, 'link'));
        await link.create(source.path);
        await expectLater(
          service.importFiles(doc, [link.path], ''),
          throwsStateError,
        );
        expect(await File(zip).readAsBytes(), before);
        final backups = await Directory(p.join(root.path, 'cache'))
            .list(recursive: true)
            .where((e) => p.basename(e.path).startsWith('backup-'))
            .toList();
        backups.sort((a, b) => a.path.compareTo(b.path));
        expect(backups.length, 4);
        expect(await File(backups.first.path).readAsBytes(), initial);
        final createZip = p.join(root.path, 'folder.zip');
        await service.create(createZip, [imported.path]);
        expect(
          (await service.read(createZip)).entries.map((e) => e.normalized),
          contains('资料/空目录'),
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: enabled ? false : 'Set HIZIP_NATIVE_LIBRARY',
  );
}
