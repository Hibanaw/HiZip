import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/preview_limit.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:path/path.dart' as p;

import 'widget_test.dart' show TestDesktop;

class PreviewService extends ArchiveService {
  bool failure = false;
  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (failure) throw StateError('broken archive');
    throw const PreviewLimitExceeded();
  }
}

void main() {
  testWidgets(
    'oversize preview stays inline; real errors still show feedback',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = PreviewService();
      final settings = AppSettings(read: () async => null, write: (_) async {});
      addTearDown(settings.dispose);
      final doc = ArchiveDocument(
        '/sample.zip',
        const [
          ArchiveEntry(
            path: 'large.txt',
            size: 3 * 1024 * 1024,
            directory: false,
          ),
          ArchiveEntry(path: 'broken.txt', size: 10, directory: false),
        ],
        'ZIP',
        true,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          theme: desktopTheme(),
          home: ArchiveWorkspace(
            initialDocument: doc,
            service: service,
            desktop: TestDesktop(),
            settings: settings,
            enableNativeTransfers: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ArchiveWorkspace));
      await tester.tap(find.byKey(const ValueKey('file-large.txt')));
      await tester.pumpAndSettle();
      expect(find.text('文件超过预览限制，请打开文件查看完整内容。'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
      expect(find.text('操作失败'), findsNothing);
      expect(state.feedback.data, isNull);
      service.failure = true;
      await tester.tap(find.byKey(const ValueKey('file-broken.txt')));
      await tester.pumpAndSettle();
      expect(state.feedback.data.error, true);
      expect(state.feedback.data.detail, 'broken archive');
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'oversize previews do not prevent opening, export or extraction',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'hizip-preview-limit-',
      );
      final service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
      try {
        final text = File(p.join(root.path, 'large.txt'));
        await text.writeAsBytes(List.filled(3 * 1024 * 1024, 65));
        final image = File(p.join(root.path, 'large.png'));
        await image.writeAsBytes(List.filled(21 * 1024 * 1024, 0));
        final archive = p.join(root.path, 'sample.zip');
        await NativeArchive.create(
          archive,
          [text.path, image.path],
          ['large.txt', 'large.png'],
        );
        final doc = await service.read(archive);
        for (final entry in doc.entries) {
          await expectLater(
            service.preview(doc, entry),
            throwsA(isA<PreviewLimitExceeded>()),
          );
          final opened = await service.prepareExternal(doc, entry);
          expect(await File(opened.path).length(), entry.size);
        }
        // An underestimated index must produce the same preview fallback.
        await expectLater(
          service.preview(
            doc,
            const ArchiveEntry(path: 'large.txt', size: 1, directory: false),
          ),
          throwsA(isA<PreviewLimitExceeded>()),
        );
        // Exercise the former 4 GB aggregate guard without writing gigabytes:
        // the index estimates are huge, while native headers hold the real sizes.
        final oversizedIndex = ArchiveDocument(
          doc.path,
          [
            for (final entry in doc.entries)
              ArchiveEntry(
                path: entry.path,
                size: 5 * 1024 * 1024 * 1024,
                directory: false,
              ),
          ],
          doc.format,
          true,
        );
        final output = await service.extract(oversizedIndex, root.path);
        expect(
          await File(p.join(output, 'large.txt')).length(),
          await text.length(),
        );
        final exports = await service.exportEntries(
          oversizedIndex,
          oversizedIndex.entries,
        );
        expect(await File(exports.first).length(), await text.length());
      } finally {
        await service.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: Platform.environment['HIZIP_NATIVE_LIBRARY'] != null
        ? false
        : 'Set HIZIP_NATIVE_LIBRARY',
  );
}
