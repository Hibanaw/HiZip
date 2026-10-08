import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';

import 'archive_tabs_test.dart' show TabsService, TabsDesktop, first, second;

class SlowService extends TabsService {
  Completer<ArchiveDocument>? reading;
  Completer<OpenedArchiveFile>? opening;
  Completer<List<String>>? exporting;
  @override
  Future<ArchiveDocument> read(String path) =>
      reading?.future ?? super.read(path);
  @override
  Future<OpenedArchiveFile> open(ArchiveDocument doc, ArchiveEntry entry) =>
      opening!.future;
  @override
  Future<List<String>> exportEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) => exporting!.future;
}

class DragDesktop extends TabsDesktop {
  bool started = false;
  VoidCallback? didStart, didEnd;
  @override
  void listen({
    required void Function(int) navigate,
    Future<void> Function()? prepareClose,
    void Function(String)? command,
    void Function(String)? openArchive,
    VoidCallback? clearRecent,
    VoidCallback? dragEnded,
    VoidCallback? dragStarted,
  }) {
    didStart = dragStarted;
    didEnd = dragEnded;
    super.listen(
      navigate: navigate,
      prepareClose: prepareClose,
      command: command,
      openArchive: openArchive,
      clearRecent: clearRecent,
      dragEnded: dragEnded,
      dragStarted: dragStarted,
    );
  }

  @override
  Future<void> startFileDrag(List<String> paths, {bool movable = false}) async {
    started = true;
    didStart?.call();
  }
}

void main() {
  Future<dynamic> mount(
    WidgetTester tester,
    SlowService service,
    DragDesktop desktop,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DesktopIntegration.channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopIntegration.channel,
        null,
      ),
    );
    final settings = AppSettings(read: () async => null, write: (_) async {});
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          initialDocument: first,
          service: service,
          desktop: desktop,
          settings: settings,
          enableNativeTransfers: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state(find.byType(ArchiveWorkspace));
  }

  Future<void> progress(WidgetTester tester, String title) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('archive-status'))).data,
      contains(title),
    );
  }

  for (final fails in [false, true]) {
    testWidgets(
      'opening an archive shows progress then ${fails ? "failure" : "success"}',
      (tester) async {
        final service = SlowService()..reading = Completer<ArchiveDocument>();
        final desktop = DragDesktop();
        final state = await mount(tester, service, desktop);
        final operation = state.loadArchive(second.path) as Future<void>;
        await progress(tester, '正在打开压缩包');
        if (fails) {
          service.reading!.completeError(StateError('input is truncated'));
        } else {
          service.reading!.complete(second);
        }
        await operation;
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
        expect(
          find.text(fails ? 'input is truncated' : '已打开压缩包：second.zip'),
          findsOneWidget,
        );
        if (!fails) {
          await tester.pump(const Duration(seconds: 3));
          await tester.pump();
          expect(find.text('已打开压缩包：second.zip'), findsNothing);
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('archive-status')))
                .data,
            contains('个项目'),
          );
        }
        expect(find.byKey(const ValueKey('overall-progress')), findsNothing);
        expect(state.document.path, fails ? first.path : second.path);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'external file opening shows status progress and result without a popup',
    (tester) async {
      final service = SlowService()..opening = Completer<OpenedArchiveFile>();
      final state = await mount(tester, service, DragDesktop());
      final entry = first.entries.last;
      final operation = state.openEntry(entry) as Future<void>;
      await progress(tester, '正在打开文件');
      service.opening!.complete(
        OpenedArchiveFile(
          first.path,
          entry.path,
          '/tmp/edit.txt',
          '',
          '',
          FileStat.statSync('/tmp'),
        ),
      );
      await operation;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
      expect(find.textContaining('修改检测已开启'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'queue button shows waiting close and runs it after file opening',
    (tester) async {
      final service = SlowService()..opening = Completer<OpenedArchiveFile>();
      final state = await mount(tester, service, DragDesktop());
      final entry = first.entries.last;
      final opening = state.openEntry(entry) as Future<void>;
      await progress(tester, '正在打开文件');
      final closing = state.closeTab(first.path) as Future<void>;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('task-queue-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('archive-task-queue')), findsOneWidget);
      expect(find.text('等待中'), findsOneWidget);
      expect(find.textContaining('正在关闭压缩包'), findsOneWidget);
      expect(service.closed, isEmpty);
      service.opening!.complete(
        OpenedArchiveFile(
          first.path,
          entry.path,
          '/tmp/edit.txt',
          '',
          '',
          FileStat.statSync('/tmp'),
        ),
      );
      await opening;
      await closing;
      await tester.pumpAndSettle();
      expect(service.closed, [first.path]);
      expect(find.text('队列为空'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('task-queue-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('archive-task-queue')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final succeeded in [true, false]) {
    testWidgets(
      'drag result waits for the native session and reports $succeeded',
      (tester) async {
        final service = SlowService()..exporting = Completer<List<String>>();
        final desktop = DragDesktop();
        final state = await mount(tester, service, desktop);
        final operation =
            state.startMacDrag(first.entries.last) as Future<void>;
        await progress(tester, '正在准备拖拽文件');
        service.exporting!.complete(['/tmp/root.txt']);
        await operation;
        await tester.pumpAndSettle();
        expect(desktop.started, isTrue);
        expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
        desktop.lastDragSucceeded = succeeded;
        desktop.didEnd!();
        await tester.pumpAndSettle();
        expect(find.text(succeeded ? '拖拽完成：1 个项目' : '拖拽已取消'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('drag preparation reports progress and export failures', (
    tester,
  ) async {
    final service = SlowService()..exporting = Completer<List<String>>();
    final desktop = DragDesktop();
    final state = await mount(tester, service, desktop);
    final operation = state.startMacDrag(first.entries.last) as Future<void>;
    await progress(tester, '正在准备拖拽文件');
    service.exporting!.completeError(
      StateError('unable to extract drag files'),
    );
    await operation;
    await tester.pumpAndSettle();
    expect(find.textContaining('unable to extract drag files'), findsOneWidget);
    expect(desktop.started, isFalse);
    expect(find.byKey(const ValueKey('overall-progress')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
