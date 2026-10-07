import 'package:flutter/widgets.dart';

import '../models/task_feedback.dart';
import 'app_settings.dart';

Future<Widget?> initializeTaskWindows() async => null;
Future<bool> showSettingsWindow(AppSettings settings) async => false;

class TaskWindowTransport {
  bool get supported => false;
  Future<bool> show(TaskFeedback data, ValueChanged<String> onAction) async =>
      false;
  Future<void> hide() async {}
  void dispose() {}
}
