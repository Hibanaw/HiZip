import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/archive_service_io.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:path/path.dart' as p;

void main() {
  final enabled = Platform.environment['HIZIP_NATIVE_LIBRARY'] != null;
  late Directory root;
  late ArchiveService service;
  Future<ArchiveDocument> archive(String name) async {
    final source = File(p.join(root.path, '$name.txt'));
    await source.writeAsString('original $name');
    final path = p.join(root.path, '$name.zip');
    await NativeArchive.create(path, [source.path], ['$name.txt']);
    return service.read(path);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hizip-cache-test-');
    service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
  });
  tearDown(() async {
    await service.dispose();
    await root.delete(recursive: true);
  });

  test('closing drains pending cache jobs and isolates other archives and real outputs', () async {
    final a = await archive('a'), b = await archive('b');
    final other = await service.prepareExternal(b, b.entries.single);
    final preview = service.preview(a, a.entries.single);
    final export = service.exportEntries(a, a.entries);
    final prepared = service.prepareExternal(a, a.entries.single);
    final extracted = await service.extract(a, root.path);
    await service.closeArchive(a.path);
    expect(String.fromCharCodes(await preview), 'original a');
    expect(await File((await export).single).exists(), false);
    expect(await File((await prepared).path).exists(), false);
    expect(await File(other.path).exists(), true);
    expect(await File(p.join(extracted, 'a.txt')).readAsString(), 'original a');
    final reopened = await service.prepareExternal(a, a.entries.single);
    expect(await File(reopened.path).exists(), true);
    expect(reopened.path, isNot((await prepared).path));
    final session = await service.session;
    await service.dispose();
    expect(await session.exists(), false);
    expect(await File(a.path).exists(), true);
    expect(await File(p.join(extracted, 'a.txt')).exists(), true);
  }, skip: !enabled);

  test('published clipboard exports survive switching and release with the clipboard', () async {
    final doc = await archive('clipboard');
    final paths = await service.exportEntries(doc, doc.entries);
    await service.retainClipboardExports(paths);
    await service.closeArchive(doc.path);
    expect(await File(paths.single).readAsString(), 'original clipboard');
    await service.updateClipboardExports(paths);
    expect(await File(paths.single).exists(), true);
    await service.updateClipboardExports(const []);
    expect(await File(paths.single).exists(), false);
    expect(await (await service.session).list().isEmpty, true);
    final concurrent = await service.exportEntries(doc, doc.entries);
    await service.retainClipboardExports(concurrent);
    await Future.wait([
      service.closeArchive(doc.path),
      service.updateClipboardExports(const []),
    ]);
    expect(await File(concurrent.single).exists(), false);
    expect(await (await service.session).list().isEmpty, true);
  }, skip: !enabled);

  test(
    'closing preserves unsaved edits and explicitly retained files only',
    () async {
      final a = await archive('dirty'), b = await archive('kept');
      final dirty = await service.prepareExternal(a, a.entries.single);
      await File(dirty.path).writeAsString('unsaved edits');
      final kept = await service.prepareExternal(b, b.entries.single);
      await File(kept.path).writeAsString('retained edits');
      await service.retain(kept);
      final exports = await service.exportEntries(a, a.entries);
      await service.closeArchive(a.path);
      await service.closeArchive(b.path);
      expect(await File(dirty.path).readAsString(), 'unsaved edits');
      expect(await File(kept.path).readAsString(), 'retained edits');
      expect(await File(exports.single).exists(), false);
      expect(await service.changes(), isEmpty);
      await service.dispose();
      expect(await File(dirty.path).exists(), true);
      expect(await File(kept.path).exists(), true);
    },
    skip: !enabled,
  );

  test(
    'declined changes stay available until closing then are deleted',
    () async {
      final doc = await archive('declined');
      final file = await service.prepareExternal(doc, doc.entries.single);
      await File(file.path).writeAsString('declined edits');
      await service.discard(file);
      expect(await File(file.path).readAsString(), 'declined edits');
      await File(file.path).writeAsString('more unsaved edits');
      await service.closeArchive(doc.path);
      expect(await File(file.path).exists(), false);
      expect(
        String.fromCharCodes(
          await service.preview(
            await service.read(doc.path),
            doc.entries.single,
          ),
        ),
        'original declined',
      );
    },
    skip: !enabled,
  );

  test('saved edits and backups are removed when the archive closes', () async {
    final doc = await archive('saved');
    final opened = await service.prepareExternal(doc, doc.entries.single);
    await File(opened.path).writeAsString('saved edits');
    await service.save(opened);
    final session = await service.session;
    expect(
      (await session.list(recursive: true).toList()).any(
        (file) => p.basename(file.path).startsWith('backup-'),
      ),
      true,
    );
    await service.closeArchive(doc.path);
    expect(await File(opened.path).exists(), false);
    expect(await session.list().isEmpty, true);
    expect(
      String.fromCharCodes(
        await service.preview(await service.read(doc.path), doc.entries.single),
      ),
      'saved edits',
    );
  }, skip: !enabled);

  test(
    'failed temporary extraction removes its partially created directory',
    () async {
      final doc = await archive('failed');
      await File(doc.path).writeAsString('invalid archive');
      await expectLater(
        service.preview(doc, doc.entries.single),
        throwsA(anything),
      );
      final session = await service.session;
      expect(
        (await session.list(recursive: true).toList()).where(
          (file) => p.basename(file.path).startsWith('file-'),
        ),
        isEmpty,
      );
      await service.dispose();
      expect(await session.exists(), false);
    },
    skip: !enabled,
  );
}
