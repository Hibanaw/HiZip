import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/archive_service_io.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late ArchiveService service;
  late ArchiveDocument doc;
  Directory dest(String name) =>
      Directory(p.join(root.path, name))..createSync();
  List<String> names(Directory d) =>
      d.listSync().map((e) => p.basename(e.path)).toList()..sort();
  ArchiveEntry entry(String path) => doc.entries.firstWhere(
    (e) => e.normalized == path,
    orElse: () => ArchiveEntry(path: path, size: 0, directory: true),
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hizip-layout-');
    service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
    final src = Directory(p.join(root.path, 'src'))..createSync();
    for (final f in ['docs/sub/a.txt', 'docs/b.txt', 'x/y/c.txt']) {
      File(p.join(src.path, f))
        ..createSync(recursive: true)
        ..writeAsStringSync(f);
    }
    final archive = p.join(root.path, 'pkg.tar.gz');
    final made = await Process.run('tar', [
      'czf',
      archive,
      '-C',
      src.path,
      'docs',
      'x',
    ]);
    expect(made.exitCode, 0);
    doc = await service.read(archive);
  });
  tearDown(() async {
    await service.dispose();
    await root.delete(recursive: true);
  });

  test(
    'whole archive goes in a folder named after it, without suffixes',
    () async {
      final out = dest('out');
      final first = await service.extract(doc, out.path);
      expect(p.basename(first), 'pkg');
      expect(File(p.join(first, 'docs', 'b.txt')).existsSync(), isTrue);
      final second = await service.extract(doc, out.path);
      expect(p.basename(second), 'pkg 2');
      expect(names(out), ['pkg', 'pkg 2']);
    },
  );

  test('a selected file lands directly in the destination', () async {
    final out = dest('out');
    final path = await service.extract(
      doc,
      out.path,
      roots: [entry('docs/sub/a.txt')],
    );
    expect(path, p.join(out.path, 'a.txt'));
    expect(names(out), ['a.txt']);
  });

  test('a selected folder keeps only its own name and contents', () async {
    final out = dest('out');
    final path = await service.extract(doc, out.path, roots: [entry('docs')]);
    expect(path, p.join(out.path, 'docs'));
    expect(
      File(p.join(path, 'sub', 'a.txt')).readAsStringSync(),
      'docs/sub/a.txt',
    );
    expect(File(p.join(path, 'b.txt')).existsSync(), isTrue);
    expect(names(out), ['docs']);
  });

  test(
    'a nested folder lands under its own name without parent folders',
    () async {
      final out = dest('out');
      final path = await service.extract(
        doc,
        out.path,
        roots: [entry('docs/sub')],
      );
      expect(path, p.join(out.path, 'sub'));
      expect(names(out), ['sub']);
      expect(File(p.join(path, 'a.txt')).readAsStringSync(), 'docs/sub/a.txt');
    },
  );

  test(
    'several selections are placed side by side and never overwrite',
    () async {
      final out = dest('out');
      File(p.join(out.path, 'a.txt')).writeAsStringSync('mine');
      final path = await service.extract(
        doc,
        out.path,
        roots: [entry('docs/sub/a.txt'), entry('x/y/c.txt')],
      );
      expect(path, out.path);
      expect(names(out), ['a 2.txt', 'a.txt', 'c.txt']);
      expect(File(p.join(out.path, 'a.txt')).readAsStringSync(), 'mine');
    },
  );

  test('a failed selection extraction removes only what it created', () async {
    final out = dest('out');
    File(p.join(out.path, 'keep.txt')).writeAsStringSync('keep');
    final bad = ArchiveDocument(
      doc.path,
      [
        ...doc.entries,
        const ArchiveEntry(path: 'missing.txt', size: 1, directory: false),
      ],
      doc.format,
      true,
    );
    await expectLater(
      service.extract(
        bad,
        out.path,
        roots: [
          const ArchiveEntry(path: 'missing.txt', size: 1, directory: false),
        ],
      ),
      throwsA(anything),
    );
    expect(names(out), ['keep.txt']);
  });
}
