import 'dart:io';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

void main() {
  final enabled = Platform.environment['HIZIP_NATIVE_LIBRARY'] != null;
  test(
    'Dart FFI creates, browses, extracts and rewrites an actual ZIP',
    () async {
      final root = await Directory.systemTemp.createTemp('hizip-ffi-test-');
      try {
        final source = File(p.join(root.path, '源文件.txt'));
        await source.writeAsString('first version');
        final archive = p.join(root.path, 'archive.zip');
        await NativeArchive.create(archive, [source.path], ['folder/源文件.txt']);
        final service = ArchiveService(
          temporaryRoot: p.join(root.path, 'new-cache'),
        );
        final doc = await service.read(archive);
        expect(doc.writable, true);
        expect(doc.entries.single.path, 'folder/源文件.txt');
        expect(
          String.fromCharCodes(await service.preview(doc, doc.entries.single)),
          'first version',
        );
        final callbackState = ReceivePort();
        final progress = <(int, int)>[];
        late final String output;
        try {
          output = await service.extract(
            doc,
            root.path,
            progress: (done, total) {
              // This unsendable port must stay on the UI/caller isolate.
              callbackState.hashCode;
              progress.add((done, total));
            },
          );
        } finally {
          callbackState.close();
        }
        expect(progress.last.$1, progress.last.$2);
        expect(
          await File(p.join(output, 'folder', '源文件.txt')).readAsString(),
          'first version',
        );
        final originalHash = (await sha256.bind(File(archive).openRead()).first)
            .toString();
        final watch = OpenedArchiveFile(
          archive,
          doc.entries.single.path,
          source.path,
          (await sha256.bind(source.openRead()).first).toString(),
          originalHash,
          await source.stat(),
        );
        await source.writeAsString('updated version');
        final updated = p.join(root.path, 'updated.zip');
        await NativeArchive.replace(
          archive,
          doc.entries.single.path,
          source.path,
          updated,
        );
        final extracted = p.join(root.path, 'updated.txt');
        await NativeArchive.extract(
          updated,
          doc.entries.single.path,
          extracted,
        );
        expect(await File(extracted).readAsString(), 'updated version');
        await service.save(watch);
        final after = p.join(root.path, 'after-save.txt');
        await NativeArchive.extract(archive, watch.entry, after);
        expect(await File(after).readAsString(), 'updated version');
        expect(
          (await Directory(
            p.join(root.path, 'new-cache'),
          ).list(recursive: true).toList()).any(
            (e) => p.basename(e.path).startsWith('backup-'),
          ),
          true,
        );
        await File(archive).writeAsString('external edit');
        await expectLater(service.save(watch), throwsStateError);
        expect(await File(archive).readAsString(), 'external edit');
        await service.dispose();
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: enabled
        ? false
        : 'Set HIZIP_NATIVE_LIBRARY to the compiled native engine',
  );
}
