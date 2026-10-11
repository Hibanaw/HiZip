import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/app_language.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';

final document = ArchiveDocument(
  '/sample.zip',
  const [ArchiveEntry(path: 'edited.txt', size: 4, directory: false)],
  'ZIP',
  true,
);

class ChangesService extends ArchiveService {
  bool reported = false, saved = false, discarded = false;
  final edited = OpenedArchiveFile(
    '/sample.zip',
    'edited.txt',
    '/tmp/edited.txt',
    '',
    '',
    FileStat.statSync('/tmp'),
  );
  @override
  Future<List<OpenedArchiveFile>> changes() async {
    if (reported) return [];
    reported = true;
    return [edited];
  }

  @override
  Future<void> save(OpenedArchiveFile file) async {
    saved = true;
  }

  @override
  Future<void> discard(OpenedArchiveFile file) async {
    discarded = true;
  }

  @override
  Future<ArchiveDocument> read(String path) async => document;
}

void main() {
  for (final layout in [
    (size: const Size(1200, 700), english: false),
    (size: const Size(1200, 700), english: true),
    (size: const Size(700, 700), english: true),
    (size: const Size(440, 360), english: false),
    (size: const Size(440, 360), english: true),
    (size: const Size(360, 640), english: true),
  ]) {
    for (final save in [true, false]) {
      final answer = layout.english
          ? (save ? 'Yes' : 'No')
          : (save ? '是' : '否');
      testWidgets(
        'floating modified-file prompt handles $answer at ${layout.size}',
        (tester) async {
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final service = ChangesService();
          final settings = AppSettings(
            read: () async => null,
            write: (_) async {},
          );
          settings.synchronizeLanguage(
            (layout.english
                    ? AppLanguage.english
                    : AppLanguage.simplifiedChinese)
                .name,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: desktopTheme(),
              builder: foruiBuilder,
              home: ArchiveWorkspace(
                initialDocument: document,
                service: service,
                settings: settings,
                enableNativeTransfers: false,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final statusBar = find.byKey(const ValueKey('workspace-status-bar'));
          final statusBounds = tester.getRect(statusBar);
          final file = find.byKey(const ValueKey('file-edited.txt'));
          final fileBounds = tester.getRect(file);
          expect(statusBounds.height, 30);
          expect(statusBounds.bottom, layout.size.height);
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(find.text(layout.english ? 'Yes' : '是'), findsOneWidget);
          expect(find.text(layout.english ? 'No' : '否'), findsOneWidget);
          expect(find.text('保留临时文件'), findsNothing);
          expect(
            find.textContaining(
              layout.english ? 'leaves the changes unsaved' : '未保存的内容将丢失',
            ),
            findsOneWidget,
          );
          final panel = find.byKey(const ValueKey('inline-task-actions'));
          final panelBounds = tester.getRect(panel);
          expect(tester.getRect(statusBar), statusBounds);
          expect(tester.getRect(file), fileBounds);
          if (layout.size.width >= 800) {
            expect(panelBounds.left, 12);
            expect(panelBounds.bottom, statusBounds.top - 8);
            expect(panelBounds.top, greaterThanOrEqualTo(12));
            expect(
              panelBounds.right,
              lessThanOrEqualTo(layout.size.width - 12),
            );
          } else {
            expect(panelBounds, Offset.zero & layout.size);
            expect(
              find.byKey(const ValueKey('auxiliary-fullscreen-dialog')),
              findsOneWidget,
            );
          }
          expect(find.text(answer).hitTestable(), findsOneWidget);
          await tester.tap(find.text(answer));
          await tester.pumpAndSettle();
          expect(service.saved, save);
          expect(service.discarded, !save);
          expect(panel, findsNothing);
          expect(tester.getRect(statusBar), statusBounds);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          settings.dispose();
        },
      );
    }
  }
}
