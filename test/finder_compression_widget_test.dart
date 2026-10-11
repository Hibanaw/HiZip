import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hizip/models/archive_create_options.dart';
import 'package:hizip/models/finder_compression_request.dart';
import 'package:hizip/services/desktop_integration.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/archive_security_dialogs.dart';
import 'package:hizip/ui/desktop_widgets.dart';

class FinderDesktop extends DesktopIntegration {
  Future<void> Function(FinderCompressionRequest)? compress;
  bool allowAccess = true;
  List<String> writes = const [];
  @override
  Future<bool> authorizeFileAccess({
    List<String> readPaths = const [],
    List<String> writeDirectories = const [],
  }) async {
    writes = writeDirectories;
    return allowAccess;
  }

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
    compress = compressFiles;
  }

  @override
  Future<List<String>> initializeMenus() async => [];
  @override
  Future<List<String>> initialArchivePaths() async => [];
}

class FinderCapabilities extends ArchiveService {
  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'writableFormats': ['zip', '7z', 'tar.gz'],
    'zipAES256': true,
  };
}

void main() {
  testWidgets(
    'cancelled Finder permission stops before naming or configuration',
    (tester) async {
      final desktop = FinderDesktop()..allowAccess = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: foruiBuilder,
          theme: desktopTheme(),
          home: ArchiveWorkspace(
            desktop: desktop,
            service: FinderCapabilities(),
            enableNativeTransfers: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final work = desktop.compress!(
        const FinderCompressionRequest(
          paths: ['/denied/source.txt'],
          quickZip: true,
        ),
      );
      await tester.pumpAndSettle();
      await work;
      expect(desktop.writes, ['/denied']);
      expect(find.byType(ArchiveCreateDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final count in [1, 2]) {
    testWidgets(
      'Finder $count items opens configuration with correct defaults',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final desktop = FinderDesktop();
        await tester.pumpWidget(
          MaterialApp(
            builder: foruiBuilder,
            theme: desktopTheme(),
            home: ArchiveWorkspace(
              desktop: desktop,
              service: FinderCapabilities(),
              enableNativeTransfers: false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        // No file picker is used: Finder's complete selection reaches the dialog.
        final completion = desktop.compress!(
          FinderCompressionRequest(
            paths: List.generate(count, (index) => '/tmp/selected$index.txt'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ArchiveCreateDialog), findsOneWidget);
        expect(find.byKey(const ValueKey('create-format')), findsOneWidget);
        expect(
          tester
              .widget<FCheckbox>(
                find.byKey(const ValueKey('create-nested-folder')),
              )
              .value,
          count > 1,
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await completion;
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('format changes clear encryption and retain nesting choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ArchiveCreateOptions? result;
    await tester.pumpWidget(
      MaterialApp(
        builder: foruiBuilder,
        theme: desktopTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<ArchiveCreateOptions>(
                context: context,
                builder: (_) => const ArchiveCreateDialog(
                  format: 'zip',
                  formats: {'zip': 'ZIP', '7z': '7z'},
                  aesAvailable: true,
                  initialLevel: 6,
                  initialNestInFolder: true,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('zip-encryption')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('create-password')),
      'secret',
    );
    await tester.tap(find.byKey(const ValueKey('create-format')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7z').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-password')), findsNothing);
    expect(find.text('此格式暂不支持加密压缩。'), findsOneWidget);
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(result?.format, '7z');
    expect(result?.nestInFolder, isTrue);
    expect(result?.password, isEmpty);
    expect(result?.encrypted, isFalse);
  });

  test(
    'platform callback preserves Finder selections alongside archive opening',
    () async {
      final desktop = FinderChannelDesktop();
      final selections = <FinderCompressionRequest>[];
      final opened = <String>[];
      desktop.listen(
        navigate: (_) {},
        compressFiles: (request) async => selections.add(request),
        openArchive: opened.add,
      );
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final call in [
        const MethodCall('compressFiles', {
          'action': 'create',
          'paths': ['/tmp/a', '/tmp/b'],
        }),
        const MethodCall('openArchive', '/tmp/existing.zip'),
        const MethodCall('compressFiles', {
          'action': 'quickZip',
          'paths': ['/tmp/中文 & #.txt'],
        }),
      ]) {
        await messenger.handlePlatformMessage(
          DesktopIntegration.channel.name,
          codec.encodeMethodCall(call),
          (_) {},
        );
      }
      expect(selections.map((request) => request.quickZip), [false, true]);
      expect(selections.first.paths, ['/tmp/a', '/tmp/b']);
      expect(selections.last.paths.single, '/tmp/中文 & #.txt');
      expect(opened, ['/tmp/existing.zip']);
      desktop.dispose();
    },
  );
}

class FinderChannelDesktop extends DesktopIntegration {
  @override
  bool get supportsQuickLook => true;
}
