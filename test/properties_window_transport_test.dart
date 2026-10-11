import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/task_windows.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/models/auxiliary_window_mode.dart';

void main() {
  testWidgets('properties create and reuse a separate desktop engine', (
    tester,
  ) async {
    const host = MethodChannel('mixin.one/desktop_multi_window');
    const messages = MethodChannel('mixin.one/desktop_multi_window/channels');
    final hostCalls = <MethodCall>[];
    final messageCalls = <MethodCall>[];
    var created = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(host, (call) async {
      hostCalls.add(call);
      if (call.method == 'getWindowDefinition') {
        return {'windowId': 'main', 'windowArgument': ''};
      }
      if (call.method == 'getAllWindows') {
        return [
          {'windowId': 'main', 'windowArgument': ''},
          if (created) {'windowId': 'property-1', 'windowArgument': ''},
        ];
      }
      if (call.method == 'createWindow') {
        created = true;
        return 'property-1';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(messages, (call) async {
      messageCalls.add(call);
      return true;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(host, null);
      messenger.setMockMethodCallHandler(messages, null);
    });
    expect(await initializeTaskWindows(), isNull);
    final settings = AppSettings()..windowMode = AuxiliaryWindowMode.separate;
    addTearDown(settings.dispose);
    final transport = PropertiesWindowTransport(settings: settings);
    final data = {'path': '/sample.zip', 'comment': 'Original'};
    expect(await transport.show(data, (_, _) async => data), isTrue);
    final configuration =
        hostCalls.singleWhere((call) => call.method == 'createWindow').arguments
            as Map;
    final arguments = jsonDecode(configuration['arguments'] as String) as Map;
    expect(configuration['hiddenAtLaunch'], isTrue);
    expect(arguments['type'], 'properties');
    expect(arguments['parent'], 'main');
    expect(arguments['data']['path'], '/sample.zip');
    expect(
      messageCalls.any(
        (call) =>
            call.method == 'invokeMethod' &&
            call.arguments['channel'] ==
                'mixin.one/window_controller/property-1' &&
            call.arguments['method'] == 'update',
      ),
      isTrue,
    );
    expect(
      await transport.show({
        ...data,
        'comment': 'Updated',
      }, (_, _) async => data),
      isTrue,
    );
    expect(hostCalls.where((call) => call.method == 'createWindow').length, 1);
    expect(hostCalls.where((call) => call.method == 'window_show').length, 2);
    transport.dispose();
    await tester.pump();
    expect(hostCalls.any((call) => call.method == 'window_hide'), isTrue);
  });
}
