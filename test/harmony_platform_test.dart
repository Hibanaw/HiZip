import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/harmony_bridge.dart';
import 'package:hizip/services/platform_files.dart';
import 'package:hizip/services/settings_storage.dart';
import 'package:hizip/services/file_transfer_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platforms = TargetPlatform.values.where((p) => p.name == 'ohos');
  group(
    'HarmonyOS file and settings bridge',
    () {
      final calls = <MethodCall>[];
      setUp(() {
        debugDefaultTargetPlatformOverride = platforms.single;
        calls.clear();
      });
      tearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(HarmonyBridge.channel, null);
      });
      void respond(Future<Object?> Function(MethodCall) handler) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(HarmonyBridge.channel, (call) async {
              calls.add(call);
              return handler(call);
            });
      }

      test(
        'picker returns sandbox paths without converting document URIs',
        () async {
          respond(
            (call) async => ['/data/storage/el2/base/files/imports/a.zip'],
          );
          final files = await openFiles(
            acceptedTypeGroups: const [
              XTypeGroup(extensions: ['zip']),
            ],
          );
          expect(
            files.single.path,
            '/data/storage/el2/base/files/imports/a.zip',
          );
          expect(calls.single.method, 'openFiles');
          expect(calls.single.arguments, {
            'extensions': ['zip'],
          });
        },
      );

      test('cancelled save does not create or export an archive', () async {
        respond((call) async => null);
        expect(await getSaveLocation(suggestedName: 'Archive.zip'), isNull);
        expect(calls.map((call) => call.method), ['saveLocation']);
      });

      test('directory export requires the selected staging root', () async {
        respond((call) async => 'file://docs/storage/exported');
        expect(
          await HarmonyBridge.finishDirectory(
            '/sandbox/root',
            '/sandbox/root/a',
          ),
          'file://docs/storage/exported',
        );
        expect(calls.single.arguments, {
          'root': '/sandbox/root',
          'path': '/sandbox/root/a',
        });
      });

      test(
        'settings use native persistent storage, including integer values',
        () async {
          final saved = <String, String>{};
          respond((call) async {
            final args = Map<String, Object?>.from(call.arguments as Map);
            final key = args['key']! as String;
            if (call.method == 'setPreference') {
              saved[key] = args['value']! as String;
            }
            return call.method == 'getPreference' ? saved[key] : null;
          });
          final storage = SettingsStorage();
          expect(await storage.getInt('workers'), isNull);
          await storage.setInt('workers', 4);
          expect(await storage.getInt('workers'), 4);
          await storage.setString('theme', 'dark');
          expect(await storage.getString('theme'), 'dark');
        },
      );

      test(
        'file clipboard fails explicitly without initializing desktop plugins',
        () async {
          expect(FileTransferClipboard().readFiles(), throwsUnsupportedError);
          expect(
            FileTransferClipboard().writeFiles(['a.zip']),
            throwsUnsupportedError,
          );
        },
      );
    },
    skip: platforms.isEmpty ? 'Requires the HarmonyOS Flutter SDK.' : false,
  );
}
