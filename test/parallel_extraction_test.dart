import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/extraction_plan.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'ZIP schedules balanced bounded workers; solid and small archives use one',
    () {
      final entries = [
        for (final size in [16, 8, 4, 4, 4, 4])
          ArchiveEntry(
            path: '$size-${Object().hashCode}',
            size: size * 1024 * 1024,
            directory: false,
          ),
      ];
      final batches = planExtraction(
        entries,
        format: 'ZIP 2.0',
        processors: 16,
      );
      expect(batches.length, 4);
      expect(batches.expand((b) => b).toSet(), {0, 1, 2, 3, 4, 5});
      expect(
        batches.map((b) => b.fold<int>(0, (s, i) => s + entries[i].size)),
        everyElement(lessThanOrEqualTo(16 * 1024 * 1024)),
      );
      for (final format in ['7-Zip', 'RAR', 'POSIX tar']) {
        expect(
          planExtraction(entries, format: format, processors: 16).length,
          1,
        );
      }
      expect(planExtraction(entries, format: 'ZIP', processors: 1).length, 1);
      expect(
        planExtraction(
          [const ArchiveEntry(path: 'tiny', size: 20, directory: false)],
          format: 'ZIP',
          processors: 16,
        ).length,
        1,
      );
    },
  );

  test('parallel ZIP extraction preserves files, empty folders, and monotonic progress', () async {
    final root = await Directory.systemTemp.createTemp('hizip-parallel-test-');
    final service = ArchiveService(maxExtractionWorkers: 4);
    try {
      final sources = <String>[], names = <String>[];
      for (var i = 0; i < 24; i++) {
        final file = File(p.join(root.path, 'source-$i'));
        await file.writeAsString('payload-$i\n' * 3000);
        sources.add(file.path);
        names.add('资料/$i.txt');
      }
      final empty = await Directory(p.join(root.path, 'empty')).create();
      sources.add(empty.path);
      names.add('empty/');
      final archive = p.join(root.path, 'sample.zip');
      await NativeArchive.create(archive, sources, names);
      final doc = await service.read(archive);
      final progress = <int>[];
      final output = await service.extract(
        doc,
        root.path,
        progress: (done, total) {
          expect(total, 24);
          progress.add(done);
        },
      );
      for (var i = 0; i < 24; i++) {
        expect(
          await File(p.join(output, '资料', '$i.txt')).readAsString(),
          await File(sources[i]).readAsString(),
        );
      }
      expect(await Directory(p.join(output, 'empty')).exists(), true);
      expect(progress.last, 24);
      expect(progress, orderedEquals([...progress]..sort()));
      // One worker fails after a successful file; all other workers must stop
      // before the enclosing output directory is removed.
      final invalid = ArchiveDocument(
        archive,
        [
          ...doc.entries,
          const ArchiveEntry(path: 'missing.txt', size: 1, directory: false),
        ],
        'ZIP',
        true,
      );
      await expectLater(service.extract(invalid, root.path), throwsStateError);
      expect(
        await Directory(root.path)
            .list()
            .where(
              (e) => e is Directory && p.basename(e.path).startsWith('sample'),
            )
            .length,
        1,
      );
    } finally {
      await service.dispose();
      await root.delete(recursive: true);
    }
  }, skip: Platform.environment['HIZIP_NATIVE_LIBRARY'] == null);
}
