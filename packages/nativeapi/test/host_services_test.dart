import 'package:file_selector/file_selector.dart' as files;
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
      test(
        'default opening invokes the viewer with read-only access',
        () async {
          respond((_) => null);
          await NativeDocuments.openWithDefault('/sandbox/cache/notes.txt');
          expect(calls.single.method, 'openWithDefault');
          expect(calls.single.arguments, {
            'path': '/sandbox/cache/notes.txt',
            'mimeType': null,
            'writable': false,
          });
        },
      );
      test('default opening forwards MIME type and editing access', () async {
        respond((_) => null);
        await NativeDocuments.openWithDefault(
          '/sandbox/cache/report.pdf',
          mimeType: 'application/pdf',
          writable: true,
        );
        expect(calls.single.method, 'openWithDefault');
        expect(calls.single.arguments, {
          'path': '/sandbox/cache/report.pdf',
          'mimeType': 'application/pdf',
          'writable': true,
        });
      });
      test('default opening propagates missing viewer errors', () async {
        respond((_) => throw PlatformException(code: 'nativeapi_16000019'));
        await expectLater(
          NativeDocuments.openWithDefault('/sandbox/cache/file.unknown'),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'nativeapi_16000019',
            ),
          ),
        );
        expect(calls.map((call) => call.method), ['openWithDefault']);
      });
      test('window chrome hides the native decoration', () async {
        respond((_) => null);
        await NativeHostWindow.setDecorVisible(false);
        expect(calls.single.method, 'setWindowDecorVisible');
        expect(calls.single.arguments, {'visible': false});
      });
      test('native window buttons use the requested toolbar height', () async {
        respond((_) => null);
        await NativeHostWindow.setDecorVisible(false, height: 49);
        expect(calls.single.arguments, {'visible': false, 'height': 49});
        for (final height in [36, 113]) {
          expect(
            () => NativeHostWindow.setDecorVisible(false, height: height),
            throwsArgumentError,
          );
        }
        expect(calls, hasLength(1));
      });
      test('document picker forwards accepted extensions', () async {
        respond((call) {
          expect(call.method, 'saveLocation');
          expect(call.arguments, {
            'name': 'Archive.zip',
            'extensions': ['zip', '7z'],
          });
          return null;
        });
        await NativeDocuments.getSaveLocation(
          acceptedTypeGroups: const [
            files.XTypeGroup(extensions: ['zip', '7z']),
          ],
        );
      });
      test(
        'single file picker preserves cancellation and sandbox paths',
        () async {
          respond((call) {
            expect(call.method, 'openFile');
            expect(call.arguments, {
              'extensions': ['zip'],
            });
            return '/sandbox/imports/archive.zip';
          });
          final selected = await NativeDocuments.openFile(
            acceptedTypeGroups: const [
              files.XTypeGroup(extensions: ['zip']),
            ],
          );
          expect(selected?.path, '/sandbox/imports/archive.zip');
          respond((_) => null);
          expect(await NativeDocuments.openFile(), isNull);
        },
      );
      test(
        'directory import returns a copy separately from export staging',
        () async {
          respond(
            (call) => switch (call.method) {
              'openDirectory' => '/sandbox/imports/source',
              'directoryLocation' => '/sandbox/imports/staging',
              _ => throw StateError('Unexpected method ${call.method}'),
            },
          );
          expect(
            await NativeDocuments.openDirectory(),
            '/sandbox/imports/source',
          );
          expect(
            await NativeDocuments.getDirectoryPath(),
            '/sandbox/imports/staging',
          );
          expect(calls.every((call) => call.arguments == null), isTrue);
        },
      );
      test(
        'support and cache directories use separate native methods',
        () async {
          respond(
            (call) => switch (call.method) {
              'applicationSupportDirectory' => '/sandbox/files',
              'temporaryDirectory' => '/sandbox/cache',
              _ => throw StateError('Unexpected method ${call.method}'),
            },
          );
          expect(
            await NativePaths.applicationSupportDirectory(),
            '/sandbox/files',
          );
          expect(await NativePaths.temporaryDirectory(), '/sandbox/cache');
        },
      );
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
          (_) => {
            'x': 12,
            'y': 23,
            'width': 1024,
            'height': 768,
            'status': 2,
            'decorVisible': false,
            'titleButtons': {
              'right': 20,
              'top': 10,
              'width': 112,
              'height': 28,
            },
          },
        );
        final state = await NativeHostWindow.state();
        expect(state.x, 12);
        expect(state.y, 23);
        expect(state.width, 1024);
        expect(state.height, 768);
        expect(state.isMaximized, isTrue);
        expect(state.decorVisible, isFalse);
        expect(state.titleButtons.right, 20);
        expect(state.titleButtons.top, 10);
        expect(state.titleButtons.width, 112);
        expect(state.titleButtons.height, 28);
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
          expect(
            () => NativeHostWindow.configure(minWidth: 900, maxWidth: 800),
            throwsArgumentError,
          );
          expect(() => NativeHostWindow.resize(0, 600), throwsArgumentError);
          expect(() => NativeHostWindow.resize(800, -1), throwsArgumentError);
          expect(
            () => NativeHostWindow.moveTo(2147483648, 0),
            throwsArgumentError,
          );
          expect(calls, isEmpty);
        },
      );
      test('all window mode getters use HarmonyOS status values', () {
        final states = [
          for (var status = 0; status <= 5; status++)
            NativeHostWindowState(
              x: 0,
              y: 0,
              width: 800,
              height: 600,
              status: status,
            ),
        ];
        expect(states.where((state) => state.isFullScreen).single.status, 1);
        expect(states.where((state) => state.isMaximized).single.status, 2);
        expect(states.where((state) => state.isMinimized).single.status, 3);
        expect(states.where((state) => state.isFloating).single.status, 4);
        expect(states.where((state) => state.isSplitScreen).single.status, 5);
      });
      test(
        'window stream broadcasts native changes and releases on cancel',
        () async {
          const name = 'nativeapi/hizip/windowState';
          const eventChannel = MethodChannel(name);
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          final streamCommands = <String>[];
          messenger.setMockMethodCallHandler(eventChannel, (call) async {
            streamCommands.add(call.method);
            return null;
          });
          addTearDown(
            () => messenger.setMockMethodCallHandler(eventChannel, null),
          );
          final firstStates = <NativeHostWindowState>[];
          final secondStates = <NativeHostWindowState>[];
          final first = NativeHostWindow.changes.listen(firstStates.add);
          final second = NativeHostWindow.changes.listen(secondStates.add);
          await Future<void>.delayed(Duration.zero);
          expect(streamCommands, ['listen']);
          for (final status in [4, 2]) {
            await messenger.handlePlatformMessage(
              name,
              const StandardMethodCodec().encodeSuccessEnvelope({
                'x': -12,
                'y': 23,
                'width': 1024,
                'height': 768,
                'status': status,
              }),
              (_) {},
            );
            await Future<void>.delayed(Duration.zero);
          }
          expect(firstStates.map((state) => state.status), [4, 2]);
          expect(secondStates.map((state) => state.status), [4, 2]);
          expect(firstStates.first.x, -12);
          await first.cancel();
          await Future<void>.delayed(Duration.zero);
          expect(streamCommands, ['listen']);
          await second.cancel();
          await Future<void>.delayed(Duration.zero);
          expect(streamCommands, ['listen', 'cancel']);
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
    expect(() => NativeHostWindow.moveTo(0, 0), throwsUnsupportedError);
    expect(() => NativeHostWindow.resize(800, 600), throwsUnsupportedError);
    expect(
      () => NativeHostWindow.setDecorVisible(false),
      throwsUnsupportedError,
    );
    expect(() => NativeHostWindow.changes, throwsUnsupportedError);
    expect(calls, isEmpty);
  });

  test('default opening requires HarmonyOS before invoking the channel', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    respond((_) => null);
    expect(
      () => NativeDocuments.openWithDefault('/sandbox/cache/notes.txt'),
      throwsUnsupportedError,
    );
    expect(calls, isEmpty);
  });
}
