import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hizip/models/auxiliary_window_mode.dart';
import 'package:hizip/models/archive_create_options.dart';
import 'package:hizip/models/app_language.dart';
import 'package:hizip/main.dart';
import 'package:hizip/ui/archive_app.dart';
import 'package:hizip/ui/archive_security_dialogs.dart';
import 'package:hizip/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:hizip/services/app_settings.dart';
import 'package:hizip/services/archive_service.dart';
import 'package:nativeapi/nativeapi.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('HarmonyOS host uses public APIs and a single window', (_) async {
    expect(NativePlatform.isHarmonyOS, isTrue);
    final host = await NativePlatform.hostInfo();
    expect(host.capabilities, contains('documents'));
    expect(
      await NativeDocuments.hasSaveLocation('/ungranted/Archive.zip'),
      isFalse,
    );
    final settings = AppSettings.instance;
    settings.windowMode = AuxiliaryWindowMode.separate;
    expect(settings.windowMode, AuxiliaryWindowMode.inline);
    expect(settings.supportsSeparateWindows, isFalse);
    await NativeSettings().setString('hizip.integration', 'round-trip');
    expect(await NativeSettings().getString('hizip.integration'), 'round-trip');
    await NativeSettings().remove('hizip.integration');
    final icon = await NativePlatform.channel.invokeMethod<List<int>>(
      'fileIcon',
      {'path': 'example.zip', 'directory': false},
    );
    expect(icon, isNotEmpty);
    final apps = await NativePlatform.channel.invokeListMethod<Object?>(
      'applicationsForFile',
      {'path': 'example.txt'},
    );
    expect(apps, isNotNull);
  });

  testWidgets(
    'ZIP Unicode names, preview, rename and extraction on the device',
    (_) async {
      final root = await Directory(
        await NativePaths.temporaryDirectory(),
      ).createTemp('hizip-integration-');
      final service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
      try {
        final source = File(p.join(root.path, '源文件.txt'));
        await source.writeAsString('HarmonyOS archive round-trip');
        final archive = p.join(root.path, 'test.zip');
        await service.create(archive, [source.path]);
        var doc = await service.read(archive);
        expect(doc.writable, isTrue);
        expect(
          utf8.decode(await service.preview(doc, doc.entries.single)),
          'HarmonyOS archive round-trip',
        );
        doc = await service.renameEntry(doc, doc.entries.single, '改名.txt');
        expect(doc.entries.single.path, '改名.txt');
        final output = await service.extract(doc, root.path);
        expect(
          await File(p.join(output, '改名.txt')).readAsString(),
          'HarmonyOS archive round-trip',
        );
      } finally {
        await service.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets('System document output and automatic source writeback', (
    _,
  ) async {
    final outputRoot = (await NativeDocuments.downloadDirectory())!;
    final folder = (await NativeDocuments.location(outputRoot))!;
    expect(folder.displayPath, isNot(contains('/imports/')));
    expect(folder.uri, startsWith('file://'));
    expect(NativeDocuments.displayPath(outputRoot), folder.displayPath);
    final root = await Directory(
      await NativePaths.temporaryDirectory(),
    ).createTemp('hizip-source-test-');
    final service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
    try {
      final input = await File(
        p.join(root.path, '原始.txt'),
      ).writeAsString('source writeback');
      final archive = await NativeDocuments.directorySaveLocation(
        outputRoot,
        'hizip-source-${DateTime.now().microsecondsSinceEpoch}.zip',
      );
      expect(
        NativeDocuments.displayPath(archive),
        startsWith(folder.displayPath),
      );
      expect(
        NativeDocuments.displayPath(archive),
        isNot(contains('/imports/')),
      );
      await service.create(archive, [input.path]);
      expect(await File(archive).exists(), isTrue);
      await NativeDocuments.finishSave(archive);
      final alternative = await NativeDocuments.directorySaveLocation(
        outputRoot,
        p.basename(archive),
      );
      expect(alternative, isNot(archive));
      expect(p.basename(alternative), contains('(2)'));
      final saved = (await NativeDocuments.location(archive))!;
      expect(saved.uri, startsWith(folder.uri));
      final imported = await NativeDocuments.importUri(saved.uri);
      expect(imported.path, isNot(archive));
      expect(imported.displayPath, saved.displayPath);
      var doc = await service.read(imported.path);
      expect(doc.writable, isTrue);
      doc = await service.renameEntry(doc, doc.entries.single, '已更新.txt');
      final renamed = await NativeDocuments.importUri(saved.uri);
      expect((await service.read(renamed.path)).entries.single.path, '已更新.txt');
      doc = await service.writeComment(
        doc,
        'saved in the system source',
        original: '',
      );
      final commented = await NativeDocuments.importUri(saved.uri);
      expect(
        (await service.read(commented.path)).comment,
        'saved in the system source',
      );
      // A stale second working copy must not overwrite changes from the first.
      final stale = await service.read(renamed.path);
      final before = await File(renamed.path).readAsBytes();
      await expectLater(
        service.renameEntry(stale, stale.entries.single, 'stale.txt'),
        throwsA(anything),
      );
      expect(await File(renamed.path).readAsBytes(), before);
      expect(
        (await service.read(
          (await NativeDocuments.importUri(saved.uri)).path,
        )).comment,
        doc.comment,
      );
      final readOnly = await NativeDocuments.importUri(
        saved.uri,
        readOnly: true,
      );
      final locked = await service.read(readOnly.path);
      expect(locked.writable, isFalse);
      await expectLater(
        service.deleteEntries(locked, locked.entries),
        throwsA(anything),
      );
      // An editor update and an import/delete operation use the same source commit.
      final editable = await service.prepareExternal(doc, doc.entries.single);
      await File(editable.path).writeAsString('edited outside the archive');
      await service.save(editable);
      final edited = await service.read(
        (await NativeDocuments.importUri(saved.uri)).path,
      );
      expect(
        utf8.decode(await service.preview(edited, edited.entries.single)),
        'edited outside the archive',
      );
      final added = await service.importFiles(
        await service.read(imported.path),
        [input.path],
        '',
      );
      final deleted = await service.deleteEntries(added, [
        added.index.byPath['原始.txt']!,
      ]);
      expect(
        (await service.read(
          (await NativeDocuments.importUri(saved.uri)).path,
        )).entries.length,
        deleted.entries.length,
      );
      final copyPath = await NativeDocuments.directorySaveLocation(
        outputRoot,
        'hizip-copy-${DateTime.now().microsecondsSinceEpoch}.zip',
      );
      await service.create(copyPath, [input.path]);
      await NativeDocuments.finishSave(copyPath);
      final copyLocation = (await NativeDocuments.location(copyPath))!;
      await NativeDocuments.copyToUri(imported.path, copyLocation.uri);
      expect((await NativeDocuments.location(imported.path))!.uri, saved.uri);
      final savedCopy = await service.read(
        (await NativeDocuments.importUri(copyLocation.uri)).path,
      );
      expect(savedCopy.comment, (await service.read(imported.path)).comment);
      expect(
        utf8.decode(await service.preview(savedCopy, savedCopy.entries.single)),
        'edited outside the archive',
      );
      // Copying only a read-only file never silently converts it to a writable source.
      expect(
        (await NativeDocuments.location(readOnly.path))!.writable,
        isFalse,
      );
    } finally {
      await service.dispose();
      await root.delete(recursive: true);
    }
  });

  testWidgets(
    'System directory exports copy folders and reject existing targets',
    (_) async {
      final root = (await NativeDocuments.downloadDirectory())!;
      final publicRoot = (await NativeDocuments.location(root))!;
      final name = 'hizip-folder-${DateTime.now().microsecondsSinceEpoch}';
      final folder = await Directory(p.join(root, name)).create();
      await File(
        p.join(folder.path, 'inside.txt'),
      ).writeAsString('public directory export');
      final destination = await NativeDocuments.finishDirectory(
        root,
        folder.path,
      );
      expect(destination, p.join(publicRoot.displayPath, name));
      final imported = await NativeDocuments.importUri(
        '${publicRoot.uri}/$name/inside.txt',
      );
      expect(
        await File(imported.path).readAsString(),
        'public directory export',
      );
      final anotherRoot = (await NativeDocuments.downloadDirectory())!;
      final duplicate = await Directory(p.join(anotherRoot, name)).create();
      await File(
        p.join(duplicate.path, 'inside.txt'),
      ).writeAsString('must not overwrite');
      await expectLater(
        NativeDocuments.finishDirectory(anotherRoot, duplicate.path),
        throwsA(anything),
      );
      final preserved = await NativeDocuments.importUri(
        '${publicRoot.uri}/$name/inside.txt',
      );
      expect(
        await File(preserved.path).readAsString(),
        'public directory export',
      );
    },
  );

  testWidgets('ZIP AES-256 creates, rejects wrong passwords and decrypts', (
    _,
  ) async {
    final root = await Directory(
      await NativePaths.temporaryDirectory(),
    ).createTemp('hizip-aes-');
    final service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
    try {
      expect((await service.capabilities())['zipAES256'], isTrue);
      final source = File(p.join(root.path, 'input.txt'));
      await source.writeAsString('encrypted round-trip');
      final archive = p.join(root.path, 'encrypted.zip');
      await service.createWithOptions(
        archive,
        [source.path],
        const ArchiveCreateOptions(
          password: 'test-password',
          encryption: 'aes256',
        ),
      );
      await expectLater(
        service.readWithPassword(archive, 'wrong'),
        throwsStateError,
      );
      final doc = await service.readWithPassword(archive, 'test-password');
      expect(
        utf8.decode(await service.preview(doc, doc.entries.single)),
        'encrypted round-trip',
      );
    } finally {
      await service.dispose();
      await root.delete(recursive: true);
    }
  });

  for (final format in ['7z', 'tar.xz', 'tar.bz2', 'xz', 'bz2']) {
    testWidgets('$format creates and reads on HarmonyOS', (_) async {
      final root = await Directory(
        await NativePaths.temporaryDirectory(),
      ).createTemp('hizip-codec-');
      final service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
      try {
        final source = File(p.join(root.path, 'input.txt'));
        await source.writeAsString('codec round-trip');
        final archive = p.join(root.path, 'test.$format');
        await service.create(archive, [source.path]);
        final doc = await service.read(archive);
        expect(
          utf8.decode(await service.preview(doc, doc.entries.single)),
          'codec round-trip',
        );
      } finally {
        await service.dispose();
        await root.delete(recursive: true);
      }
    });
  }

  testWidgets('RAR5 solid encryption unlocks and previews on HarmonyOS', (
    _,
  ) async {
    final root = await Directory(
      await NativePaths.temporaryDirectory(),
    ).createTemp('hizip-rar-');
    final service = ArchiveService(temporaryRoot: p.join(root.path, 'cache'));
    try {
      final file = File(p.join(root.path, 'encrypted.rar'));
      await file.writeAsBytes(
        base64Decode(
          'UmFyIRoHAQAgtvoRCgEFBgQFAQGAgABhD8WeUgIDPLAABJIAIFVuWu6AQwAFYS50eHQwAQABD4AO+ltBRZAMdjBQiNnLDfQI7VR1p9MLvo+08ad28VAv4g84Lifed3gQH70kCgMCfCGEo4J82gE1pZSt+eqf2NsfSgASsQSTg/Dfo8jerfnnk0KSXvAe89E8IU+RSz6hkSnpWpIfguz8l01nUgIDPJAABJIAID37tWPAQwAFYi50eHQwAQADD4AO+ltBRZAMdjBQiNnLDfQZHnb1t0VBULbYAW3tdK7f4g84Lifed3gQH70kCgMCcmWYpoJ82gEjM46yUVAy4KNVZG4T5HLJHXwcClICAzyQAASSACD/J5yGwEMABWMudHh0MAEAAw+ADvpbQUWQDHYwUIjZyw30W2TcRNmMRpQCQNayPVdi1uIPOC4n3nd4EB+9JAoDAj5I6a6CfNoBiihfqHObfXFsRShGQFWdAkeP7D9SAgM8kAAEkgAgexd0w8BDAAVkLnR4dDABAAMPgA76W0FFkAx2MFCI2csN9GlzaIL1Pzt2pDbf1ZaghGviDzguJ953eBAfvSQKAwJ7xSn0j3zaATngcETEsrz5jjXk4OrZA7Add1ZRAwUEAA==',
        ),
      );
      await expectLater(
        service.readWithPassword(file.path, 'wrong'),
        throwsStateError,
      );
      final doc = await service.readWithPassword(file.path, 'password');
      expect(doc.writable, isFalse);
      expect(
        utf8.decode(await service.preview(doc, doc.entries.last)),
        'This is from d.txt',
      );
    } finally {
      await service.dispose();
      await root.delete(recursive: true);
    }
  });
  testWidgets('Create and settings dialogs stay inside the main window', (
    tester,
  ) async {
    Future<void> waitFor(Finder finder, {bool absent = false}) async {
      for (var attempt = 0; attempt < 50; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isEmpty == absent) return;
      }
      fail('The expected dialog state did not appear.');
    }

    AppSettings.instance.language = AppLanguage.simplifiedChinese;
    await tester.pumpWidget(const HiZipApp());
    await waitFor(find.byType(ArchiveWorkspace));
    final dynamic workspace = tester.state(find.byType(ArchiveWorkspace));
    unawaited(workspace.createArchive(chooseFormat: true) as Future<void>);
    await waitFor(find.byType(ArchiveCreateDialog));
    expect(find.byType(ArchiveCreateDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await waitFor(find.byType(ArchiveCreateDialog), absent: true);
    workspace.openSettings();
    await waitFor(find.byType(SettingsPage));
    await tester.tap(find.text('外观').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('辅助窗口显示方式'), findsNothing);
    expect(find.text('独立窗口显示'), findsNothing);
    Navigator.of(tester.element(find.byType(SettingsPage))).pop();
    await waitFor(find.byType(SettingsPage), absent: true);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 760);
    await tester.binding.setSurfaceSize(const Size(390, 760));
    await tester.pump();
    unawaited(workspace.createArchive(chooseFormat: true) as Future<void>);
    await waitFor(find.byKey(const ValueKey('auxiliary-fullscreen-dialog')));
    await tester.tap(find.text('取消'));
    await waitFor(find.byType(ArchiveCreateDialog), absent: true);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.binding.setSurfaceSize(null);
  });
}
