import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/task_feedback.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/task_feedback_controller.dart';
import 'package:hizip/ui/task_feedback_panel.dart';

void main() {
  testWidgets('obsolete preview does not open a delayed window', (
    tester,
  ) async {
    final controller = TaskFeedbackController();
    var current = true;
    final token = controller.begin('旧预览', current: () => current);
    current = false;
    await tester.pump(const Duration(milliseconds: 500));
    controller.result('旧预览完成', token: token);
    expect(controller.data, isNull);
    controller.dispose();
  });
  testWidgets('stale tasks cannot replace progress, results or confirmations', (
    tester,
  ) async {
    final controller = TaskFeedbackController();
    final old = controller.begin('旧任务');
    await tester.pump(const Duration(milliseconds: 50));
    final current = controller.begin('新任务');
    controller.result('旧结果', token: old);
    controller.finish(token: old);
    await tester.pump(const Duration(milliseconds: 499));
    expect(controller.data, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.data!.title, '新任务');
    controller.result('新结果', token: current);
    final answer = controller.ask(const TaskFeedback(title: '确认保存'));
    controller.result('迟到的结果', token: current);
    expect(controller.data!.title, '确认保存');
    controller.action('dismiss');
    expect(await answer, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.data, isNull);
    controller.dispose();
  });

  testWidgets(
    'background preparation shows only slow success and always shows errors',
    (tester) async {
      final controller = TaskFeedbackController();
      var token = controller.begin('预览', reportFastSuccess: false);
      controller.result('已就绪', token: token);
      controller.finish(token: token);
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.data, isNull);
      token = controller.begin('拖拽', reportFastSuccess: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.data!.running, isTrue);
      controller.result('已就绪', token: token);
      expect(controller.data!.detail, '已就绪');
      token = controller.begin('预览', reportFastSuccess: false);
      controller.result('失败原因', error: true, token: token);
      expect(controller.data!.error, isTrue);
      controller.dispose();
    },
  );
  testWidgets('progress is delayed, centered and replaced by the result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TaskFeedbackController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => Center(
              child: controller.data == null
                  ? const SizedBox.shrink()
                  : TaskFeedbackPanel(
                      data: controller.data!,
                      onAction: controller.action,
                    ),
            ),
          ),
        ),
      ),
    );
    controller.begin('正在解压');
    await tester.pump(const Duration(milliseconds: 499));
    expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    controller.update(
      '正在解压',
      detail: 'sample.zip',
      progress: .5,
      fileProgress: .25,
      currentFile: 'large.bin',
    );
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.byKey(const ValueKey('file-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('overall-progress')), findsOneWidget);
    final center = tester.getCenter(
      find.byKey(const ValueKey('task-feedback')),
    );
    expect(center, const Offset(500, 350));
    expect(
      tester.getSize(find.byKey(const ValueKey('task-feedback'))),
      const Size(440, 216),
    );
    controller.result('已解压到 /tmp/output');
    await tester.pump();
    expect(find.text('50%'), findsNothing);
    expect(find.text('已解压到 /tmp/output'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('task-feedback'))),
      const Size(440, 216),
    );
    expect(
      tester.getCenter(find.text('已解压到 /tmp/output')).dx,
      closeTo(500, 1),
    );
    expect(tester.getCenter(find.text('关闭')).dx, closeTo(500, 1));
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
  });

  test('dismissal resolves save confirmation without saving', () async {
    final controller = TaskFeedbackController();
    final reply = controller.ask(
      const TaskFeedback(
        title: '文件已修改',
        actions: {'keep': '保留临时文件', 'save': '保存回压缩包'},
      ),
    );
    controller.action('dismiss');
    expect(await reply, isNull);
    expect(controller.data, isNull);
    controller.dispose();
  });

  testWidgets('short operations never leave a pending progress timer', (
    tester,
  ) async {
    final controller = TaskFeedbackController();
    controller.begin('正在读取');
    controller.finish();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.data!.running, isFalse);
    expect(controller.data!.detail, '操作已完成');
    controller.dispose();
  });

  testWidgets(
    'fast actions show results and slow file opening shows progress',
    (tester) async {
      final controller = TaskFeedbackController();
      controller.begin('正在解压');
      controller.update(
        '正在解压',
        progress: .5,
        fileProgress: .75,
        currentFile: 'a',
      );
      await tester.pump(const Duration(milliseconds: 499));
      controller.result('完成');
      controller.finish();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.data!.detail, '完成');
      expect(controller.data!.running, isFalse);
      controller.begin('打开文件');
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.data!.running, isTrue);
      controller.result('已打开');
      controller.finish();
      expect(controller.data!.detail, '已打开');
      controller.dispose();
    },
  );

  testWidgets('delayed extraction displays the latest pending progress', (
    tester,
  ) async {
    final controller = TaskFeedbackController();
    controller.begin('正在解压');
    controller.update(
      '正在解压',
      progress: .3,
      fileProgress: .6,
      currentFile: 'a.bin',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.data!.progress, .3);
    expect(controller.data!.fileProgress, .6);
    expect(
      TaskFeedback.fromJson(controller.data!.toJson()).currentFile,
      'a.bin',
    );
    controller.dispose();
  });

  testWidgets('dual progress fits the compact task window', (tester) async {
    tester.view.physicalSize = const Size(480, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: Scaffold(
          body: Center(
            child: TaskFeedbackPanel(
              inWindow: true,
              data: const TaskFeedback(
                title: '正在解压',
                running: true,
                detail: '2 / 10 个文件 · sample.zip',
                currentFile: '资料/large.bin',
                progress: .2,
                fileProgress: .4,
                actions: {},
              ),
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('overall-progress'))).dy,
      lessThan(240),
    );
  });
}
