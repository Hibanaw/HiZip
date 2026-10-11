import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/finder_compression_request.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/desktop_widgets.dart';
import 'package:hizip/ui/file_item_surface.dart';

final first = ArchiveDocument(
  '/first.zip',
  const [
    ArchiveEntry(path: 'docs/first.txt', size: 5, directory: false),
    ArchiveEntry(path: 'root.txt', size: 5, directory: false),
  ],
  'ZIP',
  true,
);
final second = ArchiveDocument(
  '/second.zip',
  const [ArchiveEntry(path: 'docs/second.txt', size: 5, directory: false)],
  'ZIP',
  true,
);

class TabsService extends ArchiveService {
  final reads = <String>[];
  final closed = <String>[];
  final documents = {first.path: first, second.path: second};
  @override
  Future<ArchiveDocument> read(String path) async {
    reads.add(path);
    return documents[path] ?? (throw StateError('invalid archive'));
  }

  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async =>
      Uint8List.fromList('sample'.codeUnits);
  @override
  Future<void> closeArchive(String path) async {
    closed.add(path);
  }
}

class TabsDesktop extends DesktopIntegration {
  void Function(String)? open;
  void Function(String)? command;
  @override
  bool get supportsQuickLook => true;
  @override
  void listen({
    required void Function(int) navigate,
    Future<void> Function()? prepareClose,
    void Function(String)? command,
    void Function(String)? openArchive,
    Future<void> Function(FinderCompressionRequest)? compressFiles,
    VoidCallback? clearRecent,
    VoidCallback? dragEnded,
    VoidCallback? dragStarted,
  }) {
    open = openArchive;
    this.command = command;
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    TabsService service,
    TabsDesktop desktop,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          DesktopIntegration.channel,
          (_) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DesktopIntegration.channel, null),
    );
    final settings = AppSettings(read: () async => null, write: (_) async {});
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          initialDocument: first,
          settings: settings,
          service: service,
          desktop: desktop,
          enableNativeTransfers: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  Finder tab(String path) => find.byKey(ValueKey('archive-tab-$path'));
  Finder root(String path) => find.byKey(ValueKey('archive-root-$path'));
  Finder pathLabel(String label) => find.descendant(
    of: find.byKey(const ValueKey('path-navigation')),
    matching: find.text(label),
  );

  testWidgets(
    'tabs retain browsing state and only closing releases their cache',
    (tester) async {
      final service = TabsService();
      final desktop = TabsDesktop();
      await mount(tester, service, desktop);
      expect(find.byKey(const ValueKey('archive-tabs')), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('tree-docs')),
          matching: find.text('docs'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file-docs/first.txt')));
      await tester.pumpAndSettle();
      desktop.open!(second.path);
      await settle(tester);
      expect(tab(first.path), findsOneWidget);
      expect(tab(second.path), findsOneWidget);
      expect(root(first.path), findsOneWidget);
      expect(root(second.path), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('archive-tabs'))).dx,
        greaterThan(
          tester.getCenter(find.byKey(const ValueKey('sidebar-resizer'))).dx,
        ),
      );
      expect(service.closed, isEmpty);
      expect(find.byTooltip('本次打开'), findsNothing);
      final top = tester.getRect(
        find.byKey(const ValueKey('workspace-top-bar')),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('archive-tabs'))).dy,
        top.bottom,
      );
      await tester.tap(
        find.descendant(of: tab(first.path), matching: find.text('first.zip')),
      );
      await settle(tester);
      expect(pathLabel('docs'), findsOneWidget);
      expect(
        tester
            .widget<FileItemSurface>(
              find.byKey(const ValueKey('file-docs/first.txt')),
            )
            .selected,
        true,
      );
      expect(service.reads, [second.path]);
      desktop.command!('closeArchive');
      await settle(tester);
      expect(service.closed, [first.path]);
      expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
      expect(root(first.path), findsNothing);
      expect(root(second.path), findsOneWidget);
      expect(pathLabel('second.zip'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settle(tester);
      expect(service.closed, [first.path, second.path]);
      expect(find.byKey(const ValueKey('task-feedback')), findsNothing);
      expect(find.byKey(const ValueKey('path-navigation')), findsNothing);
      expect(find.byKey(const ValueKey('archive-tabs')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'sidebar roots and folders activate their tabs, duplicate opens reuse tabs',
    (tester) async {
      final service = TabsService();
      final desktop = TabsDesktop();
      await mount(tester, service, desktop);
      desktop.open!(second.path);
      await settle(tester);
      await tester.tap(
        find.descendant(of: root(first.path), matching: find.text('first.zip')),
      );
      await settle(tester);
      expect(pathLabel('first.zip'), findsOneWidget);
      expect(pathLabel('docs'), findsNothing);
      await tester.tap(find.byKey(ValueKey('tree-${second.path}-docs')));
      await settle(tester);
      expect(pathLabel('second.zip'), findsOneWidget);
      expect(pathLabel('docs'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('file-docs/second.txt')),
        findsOneWidget,
      );
      desktop.open!(first.path);
      await settle(tester);
      expect(service.reads, [second.path]);
      expect(service.closed, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'queued opens preserve other tabs on failure and inactive close',
    (tester) async {
      final service = TabsService();
      final desktop = TabsDesktop();
      final third = ArchiveDocument('/third.zip', const [], 'ZIP', true);
      service.documents[third.path] = third;
      await mount(tester, service, desktop);
      desktop.open!(second.path);
      desktop.open!(third.path);
      await settle(tester);
      expect(tab(first.path), findsOneWidget);
      expect(tab(second.path), findsOneWidget);
      expect(tab(third.path), findsOneWidget);
      desktop.open!('/bad.zip');
      await settle(tester);
      expect(pathLabel('third.zip'), findsOneWidget);
      expect(service.closed, isEmpty);
      await tester.tap(
        find.descendant(
          of: tab(first.path),
          matching: find.byType(DesktopIconButton),
        ),
      );
      await settle(tester);
      expect(service.closed, [first.path]);
      expect(pathLabel('third.zip'), findsOneWidget);
      tester.view.physicalSize = const Size(360, 640);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
