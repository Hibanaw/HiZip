import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/models/archive_create_options.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/archive_security_dialogs.dart';
import 'package:hizip/ui/desktop_widgets.dart';

import 'finder_compression_widget_test.dart'
    show FinderDesktop, FinderCapabilities;

class CreationDesktop extends FinderDesktop {
  List<String> selection = [];
  int selections = 0;
  @override
  Future<List<String>> selectCompressionContents({
    bool foldersOnly = false,
  }) async {
    selections++;
    return selection;
  }
}

class CreationService extends FinderCapabilities {
  String? output;
  List<String>? sources;
  ArchiveCreateOptions? options;
  @override
  Future<void> createWithOptions(
    String output,
    List<String> files,
    ArchiveCreateOptions options,
  ) async {
    this.output = output;
    sources = List.of(files);
    this.options = options;
  }

  @override
  Future<ArchiveDocument> read(String path) async =>
      ArchiveDocument(path, const [], 'ZIP', true);
}

void main() {
  Future<dynamic> mount(
    WidgetTester tester,
    CreationDesktop desktop,
    CreationService service,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: desktopTheme(),
        builder: foruiBuilder,
        home: ArchiveWorkspace(
          desktop: desktop,
          service: service,
          enableNativeTransfers: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state(find.byType(ArchiveWorkspace));
  }

  testWidgets(
    'menu creation opens content and destination controls before picking',
    (tester) async {
      final desktop = CreationDesktop();
      final state = await mount(tester, desktop, CreationService());
      state.handleMenuCommand('create');
      await tester.pumpAndSettle();
      expect(desktop.selections, 0);
      expect(find.byType(ArchiveCreateDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('create-contents')), findsOneWidget);
      expect(find.byKey(const ValueKey('create-output-path')), findsOneWidget);
      expect(find.byKey(const ValueKey('create-format')), findsOneWidget);
      await tester.tap(find.text('创建').last);
      await tester.pumpAndSettle();
      expect(find.text('请选择要压缩的文件或文件夹。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'quick ZIP uses mixed selection and saves beside the source without options',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'hizip-quick-create-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/note.txt')
        ..writeAsStringSync('content');
      final folder = Directory('${directory.path}/folder')..createSync();
      // Preserve an existing archive by choosing the next free name.
      File(
        '${directory.path}/${directory.uri.pathSegments.where((part) => part.isNotEmpty).last}.zip',
      ).writeAsStringSync('keep');
      final desktop = CreationDesktop()..selection = [file.path, folder.path];
      final service = CreationService();
      final state = await mount(tester, desktop, service);
      await tester.runAsync(() async {
        state.finderCompressionQueue = Future<void>.value();
        await state.quickCreateZip();
      });
      await tester.pumpAndSettle();
      expect(desktop.selections, 1);
      expect(service.sources, [file.path, folder.path]);
      expect(File(service.output!).parent.path, directory.path);
      expect(service.output, endsWith(' (2).zip'));
      expect(service.options!.nestInFolder, isFalse);
      expect(service.options!.overwrite, isFalse);
      expect(desktop.writes, [directory.path]);
      expect(find.byType(ArchiveCreateDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'creation dialog combines contents, destination and compression options',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<String>? sources;
      String? destination;
      ArchiveCreateOptions? options;
      final screenshotKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: screenshotKey,
          child: MaterialApp(
            theme: desktopTheme(),
            builder: foruiBuilder,
            home: Builder(
              builder: (context) => TextButton(
                child: const Text('open'),
                onPressed: () async {
                  options = await showDialog<ArchiveCreateOptions>(
                    context: context,
                    builder: (_) => ArchiveCreateDialog(
                      format: 'zip',
                      formats: const {'zip': 'ZIP', '7z': '7z'},
                      aesAvailable: true,
                      initialLevel: 6,
                      selectContents: ({bool foldersOnly = false}) async => [
                        '/source/note.txt',
                        '/source/folder',
                      ],
                      suggestOutputPath: (paths, format) async =>
                          '/source/Archive.$format',
                      selectOutputPath: (path, format) async =>
                          '/destination/custom.$format',
                      onSelectionConfirmed: (paths, path) {
                        sources = paths;
                        destination = path;
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-select-contents')));
      await tester.pumpAndSettle();
      expect(find.text('/source/folder'), findsOneWidget);
      expect(
        tester
            .widget<FCheckbox>(
              find.byKey(const ValueKey('create-nested-folder')),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<DesktopTextField>(
              find.byKey(const ValueKey('create-output-path')),
            )
            .controller
            .text,
        '/source/Archive.zip',
      );
      await tester.tap(find.byKey(const ValueKey('create-select-output')));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(520, 600);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            screenshotKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final screenshot = await boundary.toImage();
        final data = await screenshot.toByteData(
          format: ui.ImageByteFormat.png,
        );
        await File('/tmp/hizip-create-dialog.png')
            .writeAsBytes(data!.buffer.asUint8List());
        screenshot.dispose();
      });
      tester.view.physicalSize = const Size(900, 900);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('create-format')));
      await tester.tap(find.byKey(const ValueKey('create-format')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7z').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DesktopTextField>(
              find.byKey(const ValueKey('create-output-path')),
            )
            .controller
            .text,
        '/destination/custom.7z',
      );
      await tester.tap(find.text('创建').last);
      await tester.pumpAndSettle();
      expect(sources, ['/source/note.txt', '/source/folder']);
      expect(destination, '/destination/custom.7z');
      expect(options!.format, '7z');
      expect(options!.nestInFolder, isTrue);
      expect(options!.overwrite, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
