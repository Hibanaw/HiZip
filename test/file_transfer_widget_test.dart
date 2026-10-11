import 'dart:io';

import 'package:hizip/ui/desktop_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/services/file_transfer_clipboard.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/file_item_surface.dart';
import 'package:hizip/ui/file_context_menu.dart';

class TransferService extends ArchiveService {
  List<ArchiveEntry> exported = [];
  int exportCalls = 0, openCalls = 0;

  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'writableFormats': ['zip'],
    'zipAES256': false,
  };

  @override
  Future<OpenedArchiveFile> open(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) async {
    openCalls++;
    return OpenedArchiveFile(
      doc.path,
      entry.path,
      '/tmp/${entry.name}',
      '',
      '',
      FileStat.statSync('/tmp/hizip-missing-test-file'),
    );
  }

  List<String> imported = [];
  String? destination;
  @override
  Future<List<String>> exportEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) async {
    exportCalls++;
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
    List<ArchiveEntry> commentSources = const [],
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

class DragDesktop extends TransferDesktop {
  int starts = 0, prepared = 0;
  @override
  bool get supportsQuickLook => true;
  @override
  Future<DefaultApplication?> defaultApplication(String name) async => null;
  @override
  Future<void> prepareFileDrag(
    List<String> paths, {
    required bool movable,
    required List<double> frame,
  }) async {
    if (paths.isNotEmpty) prepared++;
  }

  @override
  Future<void> startFileDrag(
    List<String> paths, {
    required bool movable,
  }) async {
    starts++;
  }
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
    'clicking and opening do not export for drag; actual drag exports once',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopIntegration.channel,
        (call) async {
          if (call.method == 'quickLookVisible') return false;
          if (call.method == 'configureMenus') return <String>[];
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          DesktopIntegration.channel,
          null,
        ),
      );
      final service = TransferService(), desktop = DragDesktop();
      final doc = ArchiveDocument(
        '/sample.zip',
        const [
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
            service: service,
            desktop: desktop,
            initialDocument: doc,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file-one.bin')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('file-two.bin')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.exportCalls, 0);
      expect(desktop.prepared, 0);
      await tester.tap(find.byKey(const ValueKey('file-two.bin')));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const ValueKey('file-two.bin')));
      await tester.pumpAndSettle();
      expect(service.openCalls, 1);
      expect(service.exportCalls, 0);
      expect(desktop.starts, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('file-one.bin'))),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.exportCalls, 0);
      await gesture.moveBy(const Offset(3, 0));
      await tester.pump();
      expect(service.exportCalls, 0);
      await gesture.moveBy(const Offset(60, 0));
      await tester.pumpAndSettle();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(service.exportCalls, 1);
      expect(desktop.starts, 1);
      await gesture.up();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await service.dispose();
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

  testWidgets('touch long press opens context menu on release', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FileContextMenu(
          onOpen: () => opened++,
          child: const SizedBox(width: 120, height: 40),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FileContextMenu)),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 550));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(opened, 0);
  });

  testWidgets('touch hold past drag threshold invokes drag callback', (
    tester,
  ) async {
    var starts = 0, updates = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FileContextMenu(
          onTouchDragStart: () => starts++,
          onTouchDragUpdate: (_) => updates++,
          child: const SizedBox(width: 120, height: 40),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FileContextMenu)),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(const Duration(milliseconds: 950));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    expect(starts, 1);
    expect(updates, greaterThan(0));
  });

  testWidgets('mouse drag still passes through the touch menu layer', (
    tester,
  ) async {
    var drags = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: FileContextMenu(
          child: FileItemSurface(
            name: 'file',
            selected: false,
            onSelect: () {},
            onActivate: () {},
            onDragStart: () => drags++,
            child: const SizedBox(width: 120, height: 40),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FileItemSurface)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    expect(drags, 1);
  });
}
