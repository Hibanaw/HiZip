import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
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
  for (final answer in ['是', '否']) {
    testWidgets('modified-file prompt offers yes/no and handles $answer', (
      tester,
    ) async {
      final service = ChangesService();
      final settings = AppSettings(read: () async => null, write: (_) async {});
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
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('是'), findsOneWidget);
      expect(find.text('否'), findsOneWidget);
      expect(find.text('保留临时文件'), findsNothing);
      expect(find.textContaining('未保存的内容将丢失'), findsOneWidget);
      await tester.tap(find.text(answer));
      await tester.pumpAndSettle();
      expect(service.saved, answer == '是');
      expect(service.discarded, answer == '否');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    });
  }
}
