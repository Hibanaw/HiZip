import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_properties.dart';
import 'package:hizip/models/auxiliary_window_mode.dart';
import 'package:hizip/models/task_feedback.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/services/task_windows.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/inline_properties_dialog.dart';
import 'package:hizip/ui/settings_page.dart';
import 'package:hizip/ui/task_feedback_controller.dart';

void main() {
  testWidgets('closing inline properties preserves native menu callbacks', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      DesktopIntegration.channel,
      (_) async => null,
    );
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(DesktopIntegration.channel, null),
    );
    final settings = AppSettings()..windowMode = AuxiliaryWindowMode.inline;
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          settings: settings,
          enableNativeTransfers: false,
          initialDocument: ArchiveDocument(
            '/sample.zip',
            const [],
            'ZIP',
            true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> command(String name) async {
      await messenger.handlePlatformMessage(
        DesktopIntegration.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('fileCommand', name),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await command('archiveProperties');
    expect(
      find.byKey(const ValueKey('inline-properties-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await command('archiveProperties');
    expect(
      find.byKey(const ValueKey('inline-properties-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await command('settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'saved mode overrides build default; invalid values use build default',
    () async {
      const buildValue = String.fromEnvironment(
        'HIZIP_WINDOW_MODE',
        defaultValue: 'separate',
      );
      final expected = buildValue == 'inline'
          ? AuxiliaryWindowMode.inline
          : AuxiliaryWindowMode.separate;
      String? stored;
      AppSettings create() => AppSettings(
        read: () async => null,
        readWindowMode: () async => stored,
        writeWindowMode: (value) async => stored = value,
      );
      final settings = create();
      expect(settings.windowMode, expected);
      await settings.load();
      expect(settings.windowMode, expected);
      final opposite = expected == AuxiliaryWindowMode.inline
          ? AuxiliaryWindowMode.separate
          : AuxiliaryWindowMode.inline;
      await settings.setWindowMode(opposite);
      expect(stored, opposite.name);
      final restored = create();
      await restored.load();
      expect(restored.windowMode, opposite);
      stored = 'invalid';
      await restored.load();
      expect(restored.windowMode, expected);
      settings.dispose();
      restored.dispose();
    },
  );

  test('failed mode save retains the previous mode', () async {
    final settings = AppSettings(
      writeWindowMode: (_) async => throw StateError('disk'),
    );
    final original = settings.windowMode;
    await settings.setWindowMode(
      original == AuxiliaryWindowMode.inline
          ? AuxiliaryWindowMode.separate
          : AuxiliaryWindowMode.inline,
    );
    expect(settings.windowMode, original);
    expect(settings.error, isNotNull);
    expect(settings.saving, false);
    settings.dispose();
  });

  testWidgets('appearance picker saves both display modes', (tester) async {
    String? stored;
    final settings = AppSettings(
      writeWindowMode: (value) async => stored = value,
    )..windowMode = AuxiliaryWindowMode.separate;
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: SettingsPage(settings: settings),
      ),
    );
    final picker = find.byKey(const ValueKey('window-mode-select'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('画面内显示').last);
    await tester.pumpAndSettle();
    expect(stored, 'inline');
    expect(settings.separateWindows, false);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('独立窗口显示').last);
    await tester.pumpAndSettle();
    expect(stored, 'separate');
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('inline mode avoids engines; active feedback switches modes', (
    tester,
  ) async {
    const host = MethodChannel('mixin.one/desktop_multi_window');
    const messages = MethodChannel('mixin.one/desktop_multi_window/channels');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    final windows = <Map<String, String>>[];
    messenger.setMockMethodCallHandler(host, (call) async {
      calls.add(call);
      if (call.method == 'getWindowDefinition') {
        return {'windowId': 'main', 'windowArgument': ''};
      }
      if (call.method == 'getAllWindows') {
        return [
          {'windowId': 'main', 'windowArgument': ''},
          ...windows,
        ];
      }
      if (call.method == 'createWindow') {
        final args = jsonDecode(call.arguments['arguments'] as String) as Map;
        final id = '${args['type']}-${windows.length}';
        windows.add({
          'windowId': id,
          'windowArgument': call.arguments['arguments'] as String,
        });
        return id;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(messages, (_) async => true);
    addTearDown(() {
      messenger.setMockMethodCallHandler(host, null);
      messenger.setMockMethodCallHandler(messages, null);
    });
    await initializeTaskWindows();
    final settings = AppSettings(writeWindowMode: (_) async {})
      ..windowMode = AuxiliaryWindowMode.inline;
    final properties = PropertiesWindowTransport(settings: settings);
    final feedback = TaskFeedbackController(settings: settings);
    expect(await showSettingsWindow(settings), false);
    expect(
      await properties.show({'path': '/sample.zip'}, (_, _) async => {}),
      false,
    );
    final answer = feedback.ask(
      const TaskFeedback(title: '确认', actions: {'save': '保存'}),
    );
    await tester.pumpAndSettle();
    expect(feedback.nativeVisible, false);
    expect(windows, isEmpty);
    await settings.setWindowMode(AuxiliaryWindowMode.separate);
    await tester.pumpAndSettle();
    expect(feedback.nativeVisible, true);
    expect(windows, hasLength(1));
    expect(calls.any((call) => call.method == 'window_show'), true);
    await settings.setWindowMode(AuxiliaryWindowMode.inline);
    await tester.pumpAndSettle();
    expect(feedback.nativeVisible, false);
    expect(feedback.data!.title, '确认');
    expect(feedback.reply!.isCompleted, false);
    expect(calls.any((call) => call.method == 'window_hide'), true);
    feedback.action('save');
    expect(await answer, 'save');
    await settings.setWindowMode(AuxiliaryWindowMode.separate);
    final shown = calls.where((call) => call.method == 'window_show').length;
    final token = feedback.begin('正在创建压缩包', progressDelay: Duration.zero);
    await tester.pump(const Duration(milliseconds: 1));
    expect(feedback.data!.running, isTrue);
    expect(feedback.nativeVisible, isFalse);
    feedback.result('压缩包已创建', token: token);
    await tester.pump();
    expect(feedback.nativeVisible, isFalse);
    feedback.result('失败原因', error: true);
    await tester.pump();
    expect(feedback.nativeVisible, isFalse);
    expect(calls.where((call) => call.method == 'window_show').length, shown);
    expect(windows, hasLength(1));
    expect(auxiliaryModalDepth.value, 0);
    feedback.dispose();
    properties.dispose();
    await tester.pump();
    settings.dispose();
  });

  testWidgets('inline properties retains a failed comment draft on close', (
    tester,
  ) async {
    final settings = AppSettings()..windowMode = AuxiliaryWindowMode.inline;
    final data = archivePropertiesSnapshot(
      ArchiveDocument(
        '/sample.zip',
        const [],
        'ZIP',
        true,
        comment: 'Original',
      ),
      '',
      const [],
    );
    var fail = true;
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => InlinePropertiesDialog(
                settings: settings,
                data: data,
                onAction: (action, values) async {
                  expect(action, 'saveComment');
                  if (fail) throw StateError('保存失败');
                  saved = values['text'] as String;
                  return {...data, 'comment': saved};
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final edit = find.byKey(const ValueKey('archive-comment-edit'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('archive-comment-input'));
    await tester.enterText(input, 'Changed');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('inline-properties-dialog')),
      findsOneWidget,
    );
    expect(find.text('Changed'), findsOneWidget);
    fail = false;
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(saved, 'Changed');
    expect(
      find.byKey(const ValueKey('inline-properties-dialog')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
