import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/archive_create_options.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/archive_task_queue.dart';
import 'package:hizip/services/queued_archive_service.dart';
import 'package:hizip_native/hizip_native.dart';

class RecordingService extends ArchiveService {
  final calls = <String>[];
  final doc = ArchiveDocument('/archives/example.zip', [], 'ZIP', true);
  @override
  Future<ArchiveDocument> read(String path) async {
    calls.add('read');
    return doc;
  }

  @override
  Future<void> createWithOptions(
    String output,
    List<String> files,
    ArchiveCreateOptions options,
  ) async {
    calls.add('create');
  }

  @override
  Future<ArchiveDocument> renameEntry(
    ArchiveDocument doc,
    ArchiveEntry entry,
    String name,
  ) async {
    calls.add('rename');
    return doc;
  }

  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async {
    calls.add('preview');
    return Uint8List(0);
  }

  @override
  Future<List<ArchiveEntry>> caseConflicts(
    ArchiveDocument doc,
    String destination, {
    ArchiveEntry? entry,
    List<ArchiveEntry>? roots,
  }) async {
    calls.add('conflicts');
    return [];
  }
}

void main() {
  late RecordingService delegate;
  late ArchiveTaskQueue queue;
  late QueuedArchiveService service;
  final grants = <({List<String> reads, List<String> writes})>[];
  setUp(() {
    delegate = RecordingService();
    queue = ArchiveTaskQueue();
    grants.clear();
    service = QueuedArchiveService(
      delegate,
      queue,
      authorize: ({required readPaths, required writeDirectories}) async {
        // Authorization happens before delegate I/O.
        grants.add((reads: readPaths, writes: writeDirectories));
        return true;
      },
    );
  });
  tearDown(() async {
    await service.dispose();
  });
  const entry = ArchiveEntry(path: 'file.txt', size: 0, directory: false);

  test(
    'creation authorizes every source and the sibling staging directory',
    () async {
      await service.createWithOptions('/output/new.zip', [
        '/sources/a',
        '/sources/b',
      ], const ArchiveCreateOptions());
      expect(grants.single.reads, ['/sources/a', '/sources/b']);
      expect(grants.single.writes, ['/output']);
      expect(delegate.calls, ['create']);
    },
  );

  test(
    'volume reads authorize siblings, ordinary reads only the archive',
    () async {
      await service.read('/archives/ordinary.zip');
      await service.read('/volumes/data.zip.001');
      await service.read('/volumes/data.part02.rar');
      await service.read('/volumes/data.r00');
      await service.read('/volumes/legacy.rar');
      expect(grants[0].reads, ['/archives/ordinary.zip']);
      expect(grants[1].reads, ['/volumes']);
      expect(
        grants.skip(2).every((grant) => grant.reads.single == '/volumes'),
        true,
      );
      expect(grants.every((grant) => grant.writes.isEmpty), isTrue);
    },
  );

  test('RAR preview authorizes all sibling volumes', () async {
    final doc = ArchiveDocument('/volumes/data.part01.rar', [], 'RAR 5', false);
    await service.preview(doc, entry);
    expect(grants.single.reads, ['/volumes']);
    expect(grants.single.writes, isEmpty);
  });

  test(
    'preview uses the native archive; edits need its original parent',
    () async {
      final doc = ArchiveDocument(
        '/archives/data.zip.001',
        [],
        'ZIP',
        true,
        nativePath: '/container/assembled.zip',
      );
      await service.preview(doc, entry);
      await service.renameEntry(doc, entry, 'renamed.txt');
      expect(grants[0].reads, ['/container/assembled.zip']);
      expect(grants[0].writes, isEmpty);
      expect(grants[1].writes, ['/archives']);
    },
  );

  test('case collision probe authorizes the extraction destination', () async {
    await service.caseConflicts(delegate.doc, '/destination');
    expect(grants.single.writes, ['/destination']);
  });

  test(
    'permission cancellation prevents I/O and is not a failed task',
    () async {
      service = QueuedArchiveService(
        delegate,
        queue,
        authorize: ({required readPaths, required writeDirectories}) async =>
            false,
      );
      await expectLater(
        service.read('/denied/data.zip'),
        throwsA(isA<ArchiveTaskCancelled>()),
      );
      await expectLater(
        service.createWithOptions('/denied/new.zip', [
          '/source',
        ], const ArchiveCreateOptions()),
        throwsA(isA<ArchiveTaskCancelled>()),
      );
      expect(delegate.calls, isEmpty);
      expect(queue.tasks, isEmpty);
    },
  );

  test('cancellation during permission prompt prevents later I/O', () async {
    final reply = Completer<bool>(), requested = Completer<void>();
    service = QueuedArchiveService(
      delegate,
      queue,
      authorize: ({required readPaths, required writeDirectories}) {
        requested.complete();
        return reply.future;
      },
    );
    final work = service.read('/archives/data.zip');
    final check = expectLater(work, throwsA(isA<ArchiveOperationCancelled>()));
    await requested.future;
    queue.cancel(queue.tasks.single);
    reply.complete(true);
    await check;
    expect(delegate.calls, isEmpty);
    expect(queue.tasks, isEmpty);
  });
}
