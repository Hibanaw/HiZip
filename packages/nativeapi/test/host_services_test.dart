import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativeapi/nativeapi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final harmony = TargetPlatform.values.where((p) => p.name == 'ohos');
  final calls = <MethodCall>[];
  void respond(Object? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativePlatform.channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(() => calls.clear());
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativePlatform.channel, null);
  });

  group(
    'HarmonyOS host services',
    () {
      setUp(() => debugDefaultTargetPlatformOverride = harmony.single);
      test('cancelled document export returns false', () async {
        respond((_) => false);
        expect(await NativeDocuments.exportFile('/sandbox/a.zip'), isFalse);
      });
      test('host capabilities contain no unique device identifiers', () async {
        respond(
          (_) => {
            'deviceType': '2in1',
            'apiVersion': 24,
            'capabilities': ['documents', 'windowControl'],
          },
        );
        final info = await NativePlatform.hostInfo();
        expect(info.deviceType, '2in1');
        expect(info.apiVersion, 24);
        expect(info.capabilities, contains('windowControl'));
        expect(calls.single.arguments, isNull);
      });
      test('window bounds preserve physical coordinates and status', () async {
        respond(
          (_) => {'x': 12, 'y': 23, 'width': 1024, 'height': 768, 'status': 2},
        );
        final state = await NativeHostWindow.state();
        expect(state.x, 12);
        expect(state.y, 23);
        expect(state.width, 1024);
        expect(state.height, 768);
        expect(state.isMaximized, isTrue);
      });
      test(
        'invalid window sizes are rejected before reaching native code',
        () async {
          respond((_) => null);
          expect(
            () => NativeHostWindow.configure(minWidth: -1),
            throwsArgumentError,
          );
          expect(
            () => NativeHostWindow.configure(minHeight: double.nan),
            throwsArgumentError,
          );
          expect(calls, isEmpty);
        },
      );
      test('preference removal targets only the requested key', () async {
        final saved = <String, String>{'keep': 'one', 'remove': 'two'};
        respond((call) {
          final key = (call.arguments as Map)['key'] as String;
          if (call.method == 'removePreference') saved.remove(key);
          return call.method == 'getPreference' ? saved[key] : null;
        });
        final settings = NativeSettings();
        await settings.remove('remove');
        expect(await settings.getString('remove'), isNull);
        expect(await settings.getString('keep'), 'one');
      });
      test('window commands propagate native capability errors', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativePlatform.channel, (_) async {
              throw PlatformException(
                code: 'nativeapi_801',
                message: 'Unsupported mode',
              );
            });
        await expectLater(
          NativeHostWindow.maximize(),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'nativeapi_801',
            ),
          ),
        );
      });
    },
    skip: harmony.isEmpty ? 'Requires the HarmonyOS Flutter SDK.' : false,
  );

  test('HarmonyOS-only window calls fail before invoking desktop channels', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    respond((_) => null);
    expect(NativeHostWindow.minimize, throwsUnsupportedError);
    expect(calls, isEmpty);
  });
}
