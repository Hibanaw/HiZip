import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/window_chrome.dart';
import 'package:nativeapi/nativeapi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platforms = TargetPlatform.values.where(
    (platform) => platform.name == 'ohos',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const events = MethodChannel('nativeapi/hizip/windowState');
  const closeChannel = MethodChannel('nativeapi/hizip/windowClose');
  final calls = <MethodCall>[];
  final order = <String>[];

  group(
    'HarmonyOS window chrome',
    () {
      setUp(() {
        debugDefaultTargetPlatformOverride = platforms.single;
        calls.clear();
        order.clear();
        messenger.setMockMethodCallHandler(NativePlatform.channel, (
          call,
        ) async {
          calls.add(call);
          order.add(call.method);
          return switch (call.method) {
            'hostInfo' => {
              'deviceType': '2in1',
              'apiVersion': 24,
              'capabilities': ['windowControl'],
            },
            'windowState' => {
              'x': 0,
              'y': 0,
              'width': 1280,
              'height': 800,
              'status': 4,
              'decorVisible': false,
              'titleButtons': {
                'right': 20,
                'top': 10,
                'width': 112,
                'height': 28,
              },
            },
            _ => null,
          };
        });
        messenger.setMockMethodCallHandler(events, (_) async => null);
      });
      tearDown(() {
        debugDefaultTargetPlatformOverride = platforms.single;
        setWindowClosePreparation(null);
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(NativePlatform.channel, null);
        messenger.setMockMethodCallHandler(events, null);
      });

      testWidgets(
        'native controls reserve their geometry and prepare before closing',
        (tester) async {
          await tester.runAsync(initializeWindowChrome);
          expect(calls.map((call) => call.method), [
            'hostInfo',
            'configureWindow',
            'setWindowDecorVisible',
            'windowState',
          ]);
          expect(calls[2].arguments, {'visible': false, 'height': 49});
          await tester.pumpWidget(
            MaterialApp(
              theme: desktopTheme(),
              builder: foruiBuilder,
              home: Scaffold(body: Center(child: windowTrailingControls())),
            ),
          );
          await tester.pump();
          expect(find.byTooltip('最小化'), findsNothing);
          expect(find.byTooltip('最大化'), findsNothing);
          expect(find.byTooltip('关闭'), findsNothing);
          const space = ValueKey('harmony-system-controls-space');
          expect(tester.getSize(find.byKey(space)).width, 132);
          await tester.runAsync(
            () => messenger.handlePlatformMessage(
              events.name,
              const StandardMethodCodec().encodeSuccessEnvelope({
                'x': 0,
                'y': 0,
                'width': 1280,
                'height': 800,
                'status': 2,
                'decorVisible': false,
                'titleButtons': {'right': 0, 'top': 0, 'width': 0, 'height': 0},
              }),
              (_) {},
            ),
          );
          await tester.pump();
          expect(tester.getSize(find.byKey(space)).width, 0);
          setWindowClosePreparation(() async => order.add('prepareClose'));
          ByteData? reply;
          await tester.runAsync(
            () => messenger.handlePlatformMessage(
              closeChannel.name,
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('prepareWindowClose'),
              ),
              (value) => reply = value,
            ),
          );
          expect(const StandardMethodCodec().decodeEnvelope(reply!), isTrue);
          expect(order.last, 'prepareClose');
          expect(calls.any((call) => call.method == 'closeWindow'), isFalse);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets('failed decoration setup leaves system controls in place', (
        tester,
      ) async {
        messenger.setMockMethodCallHandler(NativePlatform.channel, (
          call,
        ) async {
          if (call.method == 'hostInfo') {
            return {
              'deviceType': '2in1',
              'apiVersion': 24,
              'capabilities': ['windowControl'],
            };
          }
          if (call.method == 'setWindowDecorVisible') {
            throw PlatformException(
              code: 'nativeapi_801',
              message: 'Unsupported mode',
            );
          }
          return null;
        });
        await tester.runAsync(initializeWindowChrome);
        await tester.pumpWidget(MaterialApp(home: windowTrailingControls()));
        expect(find.byTooltip('最小化'), findsNothing);
        expect(find.byTooltip('关闭'), findsNothing);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('failed close preparation reports an error to the host', (
        tester,
      ) async {
        setWindowClosePreparation(
          () async => throw StateError('Cleanup failed'),
        );
        ByteData? reply;
        await tester.runAsync(
          () => messenger.handlePlatformMessage(
            closeChannel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('prepareWindowClose'),
            ),
            (value) => reply = value,
          ),
        );
        expect(
          () => const StandardMethodCodec().decodeEnvelope(reply!),
          throwsA(isA<PlatformException>()),
        );
        debugDefaultTargetPlatformOverride = null;
      });
    },
    skip: platforms.isEmpty ? 'Requires the HarmonyOS Flutter SDK.' : false,
  );
}
