import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/task_feedback.dart';
import '../services/task_windows.dart';

class TaskFeedbackController extends ChangeNotifier {
  TaskFeedbackController({
    this.useNativeWindows = true,
    this.progressDelay = const Duration(milliseconds: 500),
  });
  final bool useNativeWindows;
  final Duration progressDelay;
  final transport = TaskWindowTransport();
  TaskFeedback? data;
  bool nativeVisible = false, finished = false, disposed = false;
  Timer? delay;
  Completer<String?>? reply;
  bool sending = false, dirty = false;
  TaskFeedback? pending;
  bool progressEnabled = true;
  int generation = 0;
  bool reportFastSuccess = true, progressPresented = false;
  int begin(
    String title, {
    String detail = '',
    bool showProgress = true,
    bool reportFastSuccess = true,
    bool Function()? current,
  }) {
    action('dismiss');
    final token = generation;
    finished = false;
    this.reportFastSuccess = reportFastSuccess;
    progressPresented = false;
    progressEnabled = showProgress;
    pending = TaskFeedback(
      title: title,
      detail: detail,
      running: true,
      actions: const {},
    );
    delay?.cancel();
    if (!showProgress) return token;
    delay = Timer(progressDelay, () {
      if (!finished && !disposed && token == generation) {
        if (current?.call() == false) {
          action('dismiss');
          return;
        }
        progressPresented = true;
        present(pending!);
      }
    });
    return token;
  }

  void update(
    String title, {
    String detail = '',
    double? progress,
    double? fileProgress,
    String currentFile = '',
    int? token,
  }) {
    if (finished ||
        !progressEnabled ||
        (token != null && token != generation)) {
      return;
    }
    pending = TaskFeedback(
      title: title,
      detail: detail,
      running: true,
      progress: progress,
      fileProgress: fileProgress,
      currentFile: currentFile,
      actions: const {},
    );
    if (data?.running == true) present(pending!);
  }

  void result(String text, {bool error = false, int? token}) {
    if (disposed || (token != null && token != generation)) return;
    delay?.cancel();
    finished = true;
    if (!error && token != null && !reportFastSuccess && !progressPresented) {
      return;
    }
    present(
      TaskFeedback(title: error ? '操作失败' : '操作完成', detail: text, error: error),
    );
  }

  void finish({int? token}) {
    if (disposed || (token != null && token != generation)) return;
    delay?.cancel();
    if (!finished) result('操作已完成', token: token);
    finished = true;
  }

  Future<String?> ask(TaskFeedback question) {
    generation++;
    delay?.cancel();
    reply = Completer<String?>();
    present(question);
    return reply!.future;
  }

  void present(TaskFeedback next) {
    if (disposed) return;
    data = next;
    nativeVisible = useNativeWindows && transport.supported;
    notifyListeners();
    if (nativeVisible) {
      dirty = true;
      unawaited(send());
    }
  }

  Future<void> send() async {
    if (sending) return;
    sending = true;
    try {
      while (dirty && !disposed && data != null) {
        dirty = false;
        final shown = await transport.show(data!, action);
        if (disposed || data == null) {
          await transport.hide();
          break;
        }
        if (nativeVisible != shown) {
          nativeVisible = shown;
          notifyListeners();
        }
      }
    } catch (_) {
      if (!disposed) {
        nativeVisible = false;
        notifyListeners();
      }
    } finally {
      sending = false;
    }
  }

  void action(String value) {
    if (disposed) return;
    generation++;
    delay?.cancel();
    if (reply?.isCompleted == false) {
      reply!.complete(value == 'dismiss' ? null : value);
    }
    reply = null;
    data = null;
    nativeVisible = false;
    unawaited(transport.hide());
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    delay?.cancel();
    if (reply?.isCompleted == false) reply!.complete(null);
    transport.dispose();
    super.dispose();
  }
}
