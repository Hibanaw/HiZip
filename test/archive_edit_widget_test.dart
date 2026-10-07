import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';

import 'finder_layout_test.dart' as fixtures;

class EditingService extends fixtures.FinderService {
  int deletes = 0;
  String? createdPath;
  @override
  Future<ArchiveDocument> createEntry(
    ArchiveDocument doc,
    String folder,
    String name, {
    bool directory = false,
  }) async {
    createdPath = folder.isEmpty ? name : '$folder/$name';
    return ArchiveDocument(
      doc.path,
      [
        ...doc.entries,
        ArchiveEntry(path: createdPath!, size: 0, directory: directory),
      ],
      doc.format,
      true,
    );
  }

  @override
  Future<ArchiveDocument> deleteEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) async {
    deletes++;
    return ArchiveDocument(
      doc.path,
      doc.entries
          .where(
            (e) =>
                !entries.any((selected) => selected.normalized == e.normalized),
          )
          .toList(),
      doc.format,
      true,
    );
  }
}

void main() {
  testWidgets('create in the chosen directory, cancel and confirm deletion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = EditingService();
    final settings = AppSettings(read: () async => null, write: (_) async {});
    addTearDown(settings.dispose);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          DesktopIntegration.channel,
          (call) async =>
              call.method == 'promptEntryName' ? 'New folder' : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DesktopIntegration.channel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        theme: desktopTheme(),
        home: ArchiveWorkspace(
          service: service,
          desktop: fixtures.FinderDesktop(),
          settings: settings,
          initialDocument: fixtures.document,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('file-docs')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建文件夹…'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('inline-entry-name')),
      'New folder',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(service.createdPath, 'docs/New folder');
    expect(find.byKey(const ValueKey('file-docs/New folder')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('file-docs/New folder')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.deletes, 0);
    await tester.tap(
      find.byKey(const ValueKey('file-docs/New folder')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(service.deletes, 1);
    expect(find.byKey(const ValueKey('file-docs/New folder')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
