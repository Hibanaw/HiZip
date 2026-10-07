import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

// Bound CPU/IO pressure from speculative previews and foreground operations.
const _parallelJobs = 2;
int _running = 0;
final _waiting = Queue<Completer<void>>();
Future<T> runArchiveWorker<T>(
  FutureOr<T> Function() task, {
  required String name,
}) async {
  if (_running < _parallelJobs) {
    _running++;
  } else {
    final slot = Completer<void>();
    _waiting.add(slot);
    await slot.future;
  }
  try {
    return await Isolate.run(task, debugName: name);
  } finally {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }
}
