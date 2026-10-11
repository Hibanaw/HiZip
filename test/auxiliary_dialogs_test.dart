import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_create_options.dart';
import 'package:hizip/models/auxiliary_window_mode.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/task_windows.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/archive_security_dialogs.dart';
import 'package:hizip/ui/desktop_widgets.dart';

import 'archive_creation_flow_test.dart' show CreationDesktop, CreationService;

void main() {
  const host = MethodChannel('mixin.one/desktop_multi_window');
  const messages = MethodChannel('mixin.one/desktop_multi_window/channels');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> hostCalls, messageCalls;
  late List<Map<String, String>> windows;
  late AppSettings settings;

  setUp(() async {
    hostCalls = [];
    messageCalls = [];
    windows = [];
    settings = AppSettings(writeBrowsing: (_) async {})
      ..windowMode = AuxiliaryWindowMode.separate;
    messenger.setMockMethodCallHandler(host, (call) async {
      hostCalls.add(call);
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
        final id = 'dialog-${windows.length}';
        windows.add({
          'windowId': id,
          'windowArgument': call.arguments['arguments'] as String,
        });
        return id;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(messages, (call) async {
      messageCalls.add(call);
      return true;
    });
    await initializeTaskWindows();
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(host, null);
    messenger.setMockMethodCallHandler(messages, null);
    settings.dispose();
  });

  Map request() =>
      messageCalls
              .lastWhere(
                (call) =>
                    call.method == 'invokeMethod' &&
                    call.arguments['method'] == 'open',
              )
              .arguments['arguments']
          as Map;
  Future<void> reply(Map request, Map<String, dynamic>? result) async {
    final handled = Completer<void>();
    await messenger.handlePlatformMessage(
      messages.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('methodCall', {
          'channel': 'mixin.one/window_controller/main',
          'method': 'dialogResult',
          'arguments': {'id': request['id'], 'result': result},
        }),
      ),
      (data) {
        expect(const StandardMethodCodec().decodeEnvelope(data!), isTrue);
        handled.complete();
      },
    );
    await handled.future;
  }

  Future<dynamic> mount(
    WidgetTester tester,
    CreationService service,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          service: service,
          desktop: CreationDesktop(),
          settings: settings,
          enableNativeTransfers: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state(find.byType(ArchiveWorkspace));
  }

  testWidgets(
    'separate creation locks the main window, returns options and reuses its engine',
    (tester) async {
      final service = CreationService();
      final dynamic state = await mount(tester, service, const Size(1200, 900));
      state.handleMenuCommand('create');
      await tester.pumpAndSettle();
      expect(auxiliaryModalDepth.value, 1);
      expect(find.byType(ArchiveCreateDialog), findsNothing);
      expect(jsonDecode(windows.single['windowArgument']!)['type'], 'dialog');
      expect(request()['kind'], 'create');
      expect(request()['data']['formats'], contains('zip'));
      expect(
        messageCalls.any(
          (call) =>
              call.arguments is Map && call.arguments['method'] == 'beginModal',
        ),
        isTrue,
      );
      state.handleMenuCommand('grid');
      expect(state.grid, isFalse);
      state.handleMenuCommand('create');
      expect(windows, hasLength(1));
      await reply(request(), null);
      await tester.pumpAndSettle();
      expect(auxiliaryModalDepth.value, 0);
      expect(service.output, isNull);
      state.handleMenuCommand('create');
      await tester.pumpAndSettle();
      expect(windows, hasLength(1));
      await reply(request(), {
        'paths': ['/tmp/source.txt'],
        'output': '/tmp/result.zip',
        'options': const ArchiveCreateOptions(
          compressionLevel: 3,
          comment: 'comment',
          overwrite: false,
        ).toJson(),
      });
      await tester.pumpAndSettle();
      expect(service.output, '/tmp/result.zip');
      expect(service.sources, ['/tmp/source.txt']);
      expect(service.options!.compressionLevel, 3);
      expect(service.options!.comment, 'comment');
      expect(service.options!.overwrite, isFalse);
      expect(auxiliaryModalDepth.value, 0);
      expect(
        hostCalls.where((call) => call.method == 'createWindow'),
        hasLength(1),
      );
      expect(
        messageCalls.any(
          (call) =>
              call.arguments is Map && call.arguments['method'] == 'endModal',
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'compact creation fills the screen even with separate windows selected',
    (tester) async {
      final dynamic state = await mount(
        tester,
        CreationService(),
        const Size(440, 700),
      );
      state.handleMenuCommand('create');
      await tester.pumpAndSettle();
      expect(windows, isEmpty);
      expect(auxiliaryModalDepth.value, 0);
      expect(find.byType(ArchiveCreateDialog), findsOneWidget);
      expect(
        tester.getRect(
          find.byKey(const ValueKey('auxiliary-fullscreen-dialog')),
        ),
        const Rect.fromLTWH(0, 0, 440, 700),
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveCreateDialog), findsNothing);
      state.handleMenuCommand('create');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveCreateDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed window creation releases the main window and falls back inline',
    (tester) async {
      final dynamic state = await mount(
        tester,
        CreationService(),
        const Size(1200, 900),
      );
      messenger.setMockMethodCallHandler(host, (call) async {
        if (call.method == 'getWindowDefinition') {
          return {'windowId': 'main', 'windowArgument': ''};
        }
        if (call.method == 'getAllWindows') {
          return [
            {'windowId': 'main', 'windowArgument': ''},
          ];
        }
        if (call.method == 'createWindow') {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      });
      state.handleMenuCommand('create');
      await tester.pumpAndSettle();
      expect(auxiliaryModalDepth.value, 0);
      expect(find.byType(ArchiveCreateDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ArchiveCreateDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
