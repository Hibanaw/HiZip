import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hizip_native/hizip_native.dart';

class ArchiveTask {
  ArchiveTask(this.archive, this.title);
  final String archive, title;
  bool running = false, cancelled = false, failed = false;
  Object? error;
  final control = NativeOperationControl();
  Future<void> Function()? retry;
  bool get paused => !failed && control.state == 1;
  bool get canControl => !failed && !cancelled && control.state < 2;
}

class ArchiveTaskCancelled implements Exception {
  const ArchiveTaskCancelled();
}

class _TaskScope {
  _TaskScope(this.queue, this.archive);
  final ArchiveTaskQueue queue;
  final String archive;
  bool active = true;
  final children = <Future<void>>{};
}

/// FIFO per archive. A compound operation keeps its lock across nested calls.
class ArchiveTaskQueue extends ChangeNotifier {
  static final _zoneKey = Object();
  final _tails = <String, Future<void>>{};
  final _tasks = <ArchiveTask>[];
  bool _disposed = false, _accepting = true;
  List<ArchiveTask> get tasks => List.unmodifiable(_tasks);

  void cancel(ArchiveTask task) {
    if (!_tasks.contains(task) || !task.canControl) return;
    task.cancelled = true;
    task.control.cancel();
    _notify();
  }

  void pause(ArchiveTask task) {
    if (!_tasks.contains(task) || !task.canControl) return;
    task.control.pause();
    _notify();
  }

  void resume(ArchiveTask task) {
    if (!_tasks.contains(task) || !task.canControl) return;
    task.control.resume();
    _notify();
  }

  Future<void> retry(ArchiveTask task) async {
    if (!_accepting ||
        !task.failed ||
        task.retry == null ||
        !_tasks.remove(task)) {
      return;
    }
    _notify();
    try {
      await task.retry!();
    } catch (_) {
      /* New failure remains reviewable. */
    }
  }

  void dismiss(ArchiveTask task) {
    if (task.failed) {
      _tasks.remove(task);
      _notify();
    }
  }

  Future<T> run<T>(
    String archive,
    String title,
    Future<T> Function() work, {
    Future<void>? after,
    bool retryable = false,
  }) {
    final scope = Zone.current[_zoneKey] as _TaskScope?;
    if (scope != null &&
        scope.active &&
        scope.queue == this &&
        scope.archive == archive) {
      final result = Future<T>.sync(work);
      final child = result.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      scope.children.add(child);
      unawaited(child.then((_) => scope.children.remove(child)));
      return result;
    }
    if (!_accepting) return Future.error(StateError('事件队列已关闭'));
    final task = ArchiveTask(archive, title);
    if (retryable) {
      task.retry = () async {
        await run(archive, title, work, after: after, retryable: true);
      };
    }
    _tasks.add(task);
    _notify();
    final previous = _tails[archive] ?? Future<void>.value();
    final result = previous.then((_) async {
      if (after != null) {
        try {
          await after;
        } catch (_) {
          // A failed preceding event must not block the next event.
        }
      }
      if (task.cancelled) {
        _tasks.remove(task);
        _notify();
        task.control.dispose();
        throw const ArchiveTaskCancelled();
      }
      task.running = true;
      _notify();
      final scope = _TaskScope(this, archive);
      try {
        return await NativeArchive.withControl(
          task.control,
          () => runZoned(() async {
            await NativeArchive.checkpoint();
            return await work();
          }, zoneValues: {_zoneKey: scope}),
        );
      } catch (error) {
        if (error is! ArchiveOperationCancelled &&
            error is! ArchiveTaskCancelled &&
            !task.cancelled &&
            retryable &&
            task.control.state != 3) {
          task.failed = true;
          task.error = error;
        }
        rethrow;
      } finally {
        while (scope.children.isNotEmpty) {
          await Future.wait(scope.children.toList());
        }
        scope.active = false;
        task.running = false;
        if (!task.failed) _tasks.remove(task);
        task.control.dispose();
        final failures = _tasks.where((item) => item.failed).toList();
        for (final old in failures.take((failures.length - 10).clamp(0, 10))) {
          _tasks.remove(old);
        }
        _notify();
      }
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[archive] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[archive], tail)) _tails.remove(archive);
      }),
    );
    return result;
  }

  Future<void> drain() async {
    while (_tails.isNotEmpty) {
      await Future.wait(_tails.values.toList());
    }
  }

  Future<void> stop() async {
    _accepting = false;
    for (final task in _tasks) {
      if (task.paused) task.control.resume();
    }
    await drain();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _accepting = false;
    super.dispose();
  }
}
