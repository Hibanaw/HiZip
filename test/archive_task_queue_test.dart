import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/archive_task_queue.dart';

void main() {
  test('same archive is FIFO, other archives can proceed', () async {
    final queue = ArchiveTaskQueue();
    final gate = Completer<void>();
    final events = <String>[];
    final first = queue.run('a.zip', 'extract', () async {
      events.add('a-start');
      await gate.future;
      events.add('a-end');
    });
    final second = queue.run('a.zip', 'save', () async => events.add('a-save'));
    final other = queue.run(
      'b.zip',
      'preview',
      () async => events.add('b-preview'),
    );
    await other;
    expect(events, ['a-start', 'b-preview']);
    expect(
      queue.tasks
          .where((task) => task.archive == 'a.zip')
          .map((task) => task.running),
      [true, false],
    );
    gate.complete();
    await Future.wait([first, second]);
    expect(events, ['a-start', 'b-preview', 'a-end', 'a-save']);
    expect(queue.tasks, isEmpty);
    queue.dispose();
  });

  test(
    'failure releases the archive and nested operations do not deadlock',
    () async {
      final queue = ArchiveTaskQueue();
      final failed = queue.run<void>(
        'a.zip',
        'broken',
        () async => throw StateError('broken'),
      );
      final check = expectLater(failed, throwsStateError);
      final next = queue.run('a.zip', 'save and refresh', () async {
        return queue.run('a.zip', 'refresh', () async => 42);
      });
      expect(await next, 42);
      await check;
      expect(queue.tasks, isEmpty);
      queue.dispose();
    },
  );

  test('shutdown drains queued work and rejects new submissions', () async {
    final queue = ArchiveTaskQueue();
    final gate = Completer<void>();
    final first = queue.run('a.zip', 'active', () => gate.future);
    var completed = false;
    final second = queue.run('a.zip', 'queued', () async => completed = true);
    var stopped = false;
    final stopping = queue.stop().then((_) => stopped = true);
    await expectLater(
      queue.run('a.zip', 'late', () async {}),
      throwsStateError,
    );
    expect(stopped, isFalse);
    gate.complete();
    await Future.wait([first, second, stopping]);
    expect(completed, isTrue);
    expect(stopped, isTrue);
    queue.dispose();
  });

  test(
    'unawaited nested work retains the archive lock until it finishes',
    () async {
      final queue = ArchiveTaskQueue();
      final gate = Completer<void>();
      final parent = queue.run('a.zip', 'prepare', () async {
        unawaited(
          queue.run('a.zip', 'export', () async {
            await gate.future;
            await queue.run('a.zip', 'retain export', () async {});
          }),
        );
      });
      var started = false;
      final next = queue.run('a.zip', 'close', () async => started = true);
      await Future<void>.delayed(Duration.zero);
      expect(started, isFalse);
      gate.complete();
      await Future.wait([parent, next]);
      expect(started, isTrue);
      queue.dispose();
    },
  );

  test('queued tasks can be cancelled before they start', () async {
    final queue = ArchiveTaskQueue();
    final gate = Completer<void>();
    final first = queue.run('a.zip', 'active', () => gate.future);
    var ran = false;
    final second = queue.run('a.zip', 'queued', () async => ran = true);
    final task = queue.tasks.last;
    queue.cancel(task);
    expect(task.cancelled, isTrue);
    gate.complete();
    await first;
    await expectLater(second, throwsA(isA<ArchiveTaskCancelled>()));
    expect(ran, isFalse);
    expect(queue.tasks, isEmpty);
    queue.dispose();
  });
}
