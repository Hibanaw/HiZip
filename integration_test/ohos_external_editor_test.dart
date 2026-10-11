import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:nativeapi/nativeapi.dart';
import 'package:path/path.dart' as p;

import 'ohos_archive_test.dart' show createTestDocx;

// Interactive device check: choose WPS, change the document, save, then return
// to HiZip. Unlike the archive suite, this exercises the receiving application's
// actual URI permission and save implementation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'System editor saves a sandbox DOCX back into the archive',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('沙箱文件保存测试\n请在 WPS 中修改文字、保存，然后返回 HiZip。')),
          ),
        ),
      );
      await tester.runAsync(() async {
        final lifecycle = _EditorLifecycle();
        WidgetsBinding.instance.addObserver(lifecycle);
        final root = await Directory(
          await NativePaths.temporaryDirectory(),
        ).createTemp('hizip-editor-check-');
        final service = ArchiveService(temporaryRoot: root.path);
        try {
          final source = await createTestDocx(
            root,
            '沙箱编辑验证.docx',
            'Change this text, save in WPS, then return to HiZip.',
          );
          final archive = p.join(root.path, 'office.zip');
          await service.create(archive, [source.path]);
          final doc = await service.read(archive);
          final opened = await service.prepareExternal(doc, doc.entries.single);
          final uri = (await NativePlatform.channel.invokeMethod<String>(
            'prepareExternalFile',
            {'path': opened.path, 'writable': true},
          ))!;
          expect(uri, startsWith('file://com.hibanaw.hizip/'));
          debugPrint('HIZIP_EDITOR_SMOKE_READY: $uri');
          await NativeDocuments.openWithDefault(opened.path, writable: true);
          final deadline = DateTime.now().add(const Duration(minutes: 3));
          var saved = false;
          while (DateTime.now().isBefore(deadline)) {
            if ((await service.changes()).contains(opened)) {
              saved = true;
            }
            if (saved && lifecycle.returned) break;
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          expect(saved, isTrue, reason: '没有检测到第三方编辑器保存的内容。');
          expect(lifecycle.returned, isTrue, reason: '保存后需要返回 HiZip 完成写回检查。');
          final edited = await File(opened.path).readAsBytes();
          await service.save(opened);
          final updated = await service.read(archive);
          expect(
            await service.preview(updated, updated.entries.single),
            edited,
          );
          await service.closeArchive(archive);
          expect(
            await File(Uri.decodeComponent(Uri.parse(uri).path)).exists(),
            isFalse,
          );
          debugPrint(
            'HIZIP_EDITOR_SMOKE_PASSED: save, ZIP writeback and cleanup',
          );
        } finally {
          WidgetsBinding.instance.removeObserver(lifecycle);
          await service.dispose();
          if (await root.exists()) await root.delete(recursive: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _EditorLifecycle extends WidgetsBindingObserver {
  bool left = false;
  bool returned = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      left = true;
      returned = false;
    } else if (state == AppLifecycleState.resumed && left) {
      returned = true;
    }
  }
}
