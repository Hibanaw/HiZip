import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativeapi/nativeapi.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/archive_service.dart';
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

      Future<OpenedArchiveFile> preparedFile() async {
        final directory = await Directory.systemTemp.createTemp('hizip-open-');
        addTearDown(() => directory.delete(recursive: true));
        final file = await File(
          '${directory.path}/notes.txt',
        ).writeAsString('HiZip');
        return OpenedArchiveFile(
          '/sandbox/archive.zip',
          'notes.txt',
          file.path,
          'file-hash',
          'archive-hash',
          await file.stat(),
        );
      }

      for (final writable in [false, true]) {
        test(
          'archive opening launches the viewer with writable=$writable',
          () async {
            respond((call) async => null);
            final prepared = await preparedFile();
            final service = _PreparedArchiveService(prepared);
            const entry = ArchiveEntry(
              path: 'notes.txt',
              size: 5,
              directory: false,
            );
            final doc = ArchiveDocument(
              prepared.archive,
              [entry],
              'zip',
              writable,
            );
            expect(await service.open(doc, entry), same(prepared));
            expect(calls.single.method, 'openWithDefault');
            expect(calls.single.arguments, {
              'path': prepared.path,
              'mimeType': null,
              'writable': writable,
            });
          },
        );
      }

      test(
        'archive opening reports launch failures without exporting',
        () async {
          respond(
            (call) async => throw PlatformException(code: 'nativeapi_16000019'),
          );
          final prepared = await preparedFile();
          final service = _PreparedArchiveService(prepared);
          const entry = ArchiveEntry(
            path: 'notes.txt',
            size: 5,
            directory: false,
          );
          final doc = ArchiveDocument(prepared.archive, [entry], 'zip', true);
          await expectLater(
            service.open(doc, entry),
            throwsA(
              isA<PlatformException>().having(
                (error) => error.code,
                'code',
                'nativeapi_16000019',
              ),
            ),
          );
          expect(calls.map((call) => call.method), ['openWithDefault']);
        },
      );

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

      test(
        'system picker retains real location and forwards its URI as the initial directory',
        () async {
          const root = '/data/storage/el2/base/files/imports/selected';
          const uri = 'file://docs/storage/Users/currentUser/Documents';
          respond((call) async {
            if (call.method == 'directoryLocation') {
              return {
                'workingPath': root,
                'uri': uri,
                'displayPath': '/storage/Users/currentUser/Documents',
                'writable': true,
              };
            }
            return {
              'workingPath': '$root/archive.zip',
              'uri': '$uri/archive.zip',
              'displayPath': '/storage/Users/currentUser/Documents/archive.zip',
              'writable': true,
            };
          });
          expect(await getDirectoryPath(), root);
          final selected = await NativeDocuments.pickDirectoryLocation(
            initialDirectory: root,
          );
          expect(selected!.workingPath, root);
          expect(selected.uri, uri);
          expect((calls.last.arguments as Map)['initialDirectory'], uri);
          expect(
            NativeDocuments.displayPath(root),
            '/storage/Users/currentUser/Documents',
          );
          final saved = await getSaveLocation(
            suggestedName: 'archive.zip',
            initialDirectory: root,
          );
          expect(saved!.path, '$root/archive.zip');
          expect(
            NativeDocuments.displayPath(saved.path),
            '/storage/Users/currentUser/Documents/archive.zip',
          );
          expect((calls.last.arguments as Map)['initialDirectory'], uri);
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

class _PreparedArchiveService extends ArchiveService {
  _PreparedArchiveService(this.prepared);

  final OpenedArchiveFile prepared;

  @override
  Future<OpenedArchiveFile> prepareExternal(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) async => prepared;
}
