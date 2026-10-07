import 'package:hizip/ui/desktop_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/services/file_transfer_clipboard.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/file_item_surface.dart';

class TransferService extends ArchiveService {
  List<ArchiveEntry> exported = [];
  List<String> imported = [];
  String? destination;
  @override
  Future<List<String>> exportEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) async {
    exported = entries;
    return entries.map((e) => '/tmp/${e.name}').toList();
  }

  @override
  Future<ArchiveDocument> importFiles(
    ArchiveDocument doc,
    List<String> sources,
    String folder, {
    List<ArchiveEntry> moving = const [],
    String? expectedArchiveHash,
  }) async {
    imported = sources;
    destination = folder;
    return doc;
  }
}

class TransferClipboard extends FileTransferClipboard {
  List<String> paths = [];
  @override
  Future<void> writeFiles(List<String> paths) async {
    this.paths = paths;
  }

  @override
  Future<List<String>> readFiles() async => paths;
}

class TransferDesktop extends DesktopIntegration {
  @override
  bool get supportsQuickLook => false;
}

void main() {
  testWidgets(
    'multi selection copies file URLs and pastes into current directory',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = TransferService(), clipboard = TransferClipboard();
      final doc = ArchiveDocument(
        '/sample.zip',
        const [
          ArchiveEntry(path: 'empty/', size: 0, directory: true),
          ArchiveEntry(path: 'one.bin', size: 4, directory: false),
          ArchiveEntry(path: 'two.bin', size: 4, directory: false),
        ],
        'ZIP',
        true,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          home: ArchiveWorkspace(
            enableNativeTransfers: false,
            service: service,
            desktop: TransferDesktop(),
            clipboard: clipboard,
            initialDocument: doc,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file-one.bin')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(clipboard.paths, ['/tmp/empty', '/tmp/one.bin', '/tmp/two.bin']);
      expect(service.exported.length, 3);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('tree-empty')),
          matching: find.text('empty'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(service.imported, clipboard.paths);
      expect(service.destination, 'empty');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'drag crosses the threshold once and cancels double click activation',
    (tester) async {
      var drags = 0, opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          home: Center(
            child: SizedBox(
              width: 200,
              height: 40,
              child: FileItemSurface(
                name: 'file',
                selected: false,
                onSelect: () {},
                onActivate: () => opens++,
                onDragStart: () => drags++,
                child: const Text('file'),
              ),
            ),
          ),
        ),
      );
      final point = tester.getCenter(find.byType(FileItemSurface));
      final gesture = await tester.startGesture(point);
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(30, 0));
      await gesture.up();
      expect(drags, 1);
      expect(opens, 0);
    },
  );
}
