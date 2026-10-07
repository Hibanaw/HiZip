// Run with: tools/flutter-ohos build hap --debug -t integration_test/ohos_native_smoke.dart
// Starts the real application after exercising the device's FFI engine.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:hizip/main.dart' as app;
import 'package:hizip/services/archive_service.dart';
import 'package:hizip/services/harmony_bridge.dart';
import 'package:hizip/services/settings_storage.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:nativeapi/nativeapi.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cache = await HarmonyBridge.temporaryDirectory();
  final report = File(p.join(cache, 'hizip-device-smoke.json'));
  final root = await Directory(cache).createTemp('hizip-device-check-');
  final service = ArchiveService(temporaryRoot: root.path);
  final checks = <String>[];
  final skipped = <String>[];
  try {
    final source = File(p.join(root.path, '源文件.txt'));
    await source.writeAsString('HarmonyOS · HiZip');
    final archive = p.join(root.path, 'device.zip');
    await NativeArchive.create(archive, [source.path], ['目录/源文件.txt']);
    checks.add('create ZIP');
    final doc = await service.read(archive);
    if (doc.entries.single.path != '目录/源文件.txt') {
      throw StateError('UTF-8 archive names changed.');
    }
    checks.add('read UTF-8 names');
    final preview = await service.preview(doc, doc.entries.single);
    if (utf8.decode(preview) != 'HarmonyOS · HiZip') {
      throw StateError('Preview bytes changed.');
    }
    checks.add('preview via worker isolate');
    final output = await service.extract(doc, root.path);
    if (await File(p.join(output, '目录/源文件.txt')).readAsString() !=
        'HarmonyOS · HiZip') {
      throw StateError('Extracted bytes changed.');
    }
    checks.add('extract ZIP');
    final updated = await service.createEntry(doc, '', '新目录', directory: true);
    if (!updated.entries.any((entry) => entry.normalized == '新目录')) {
      throw StateError('Archive update lost new directory.');
    }
    checks.add('update ZIP');
    final settings = SettingsStorage();
    await settings.setString('test.deviceSmoke', 'ok');
    if (await settings.getString('test.deviceSmoke') != 'ok') {
      throw StateError('Preferences did not persist.');
    }
    checks.add('native preferences');
    await settings.remove('test.deviceSmoke');
    if (await settings.getString('test.deviceSmoke') != null) {
      throw StateError('Preferences were not removed.');
    }
    checks.add('native preference removal');
    final host = await NativePlatform.hostInfo();
    if (host.apiVersion < 18 || !host.capabilities.contains('documents')) {
      throw StateError('Native host capabilities are missing.');
    }
    checks.add('native host capabilities');
    final hostWindow = await NativeHostWindow.state();
    if (hostWindow.width <= 0 || hostWindow.height <= 0) {
      throw StateError('Native window bounds are invalid.');
    }
    checks.add('native window bounds');
    final support = await NativePaths.applicationSupportDirectory();
    if (!await Directory(support).exists() || support == cache) {
      throw StateError('Native support directory is invalid.');
    }
    checks.add('native support directory');
    final windowEvent = await NativeHostWindow.changes.first.timeout(
      const Duration(seconds: 5),
    );
    if (windowEvent.width <= 0 || windowEvent.height <= 0) {
      throw StateError('Native window event bounds are invalid.');
    }
    checks.add('native window event subscription');
    await expectNativeRejection(
      () => NativePlatform.channel.invokeMethod<void>('resizeWindow', {
        'width': -1,
        'height': 600,
      }),
    );
    checks.add('native window dimension validation');
    await expectNativeRejection(
      () => NativeDocuments.exportFile('/etc/passwd'),
    );
    checks.add('native export sandbox validation');
    await expectNativeRejection(
      () => NativeDocuments.exportFile('$cache/../files/outside.txt'),
    );
    checks.add('native export path traversal validation');
    Link? alias;
    try {
      alias = await Link(
        p.join(root.path, 'source-link.txt'),
      ).create(source.path);
    } on FileSystemException catch (error) {
      if (![1, 13, 38].contains(error.osError?.errorCode)) rethrow;
      skipped.add('native export symlink validation: ${error.osError}');
    }
    if (alias != null) {
      await expectNativeRejection(
        () => NativeDocuments.exportFile(alias!.path),
      );
      checks.add('native export symlink validation');
    }
    await expectNativeRejection(
      () => NativePlatform.channel.invokeMethod<String>('openFile', {
        'extensions': ['zip|.*'],
      }),
    );
    checks.add('native file filter validation');
    await report.writeAsString(
      jsonEncode({'success': true, 'checks': checks, 'skipped': skipped}),
    );
  } catch (error, stack) {
    await report.writeAsString(
      jsonEncode({
        'success': false,
        'checks': checks,
        'skipped': skipped,
        'error': '$error',
        'stack': '$stack',
      }),
    );
  } finally {
    // Read through HiLog when the device restricts hdc sandbox file access.
    debugPrint('HIZIP_DEVICE_SMOKE ${await report.readAsString()}');
    await service.dispose();
    await root.delete(recursive: true);
  }
  await app.main();
  if (const bool.fromEnvironment('HIZIP_SMOKE_OPEN_DEFAULT')) {
    await checkDefaultOpening(cache);
  }
}

Future<void> checkDefaultOpening(String cache) async {
  final report = File(p.join(cache, 'hizip-default-open-smoke.json'));
  final root = await Directory(cache).createTemp('hizip-default-open-');
  final checks = <String>[];
  try {
    await expectNativeRejection(
      () => NativeDocuments.openWithDefault('/etc/passwd'),
    );
    checks.add('default open sandbox validation');
    await expectNativeRejection(
      () => NativeDocuments.openWithDefault('$cache/../files/outside.txt'),
    );
    checks.add('default open path traversal validation');
    await expectNativeRejection(
      () => NativeDocuments.openWithDefault(root.path),
    );
    checks.add('default open regular file validation');
    final source = await File(
      p.join(root.path, 'HiZip默认应用打开测试.txt'),
    ).writeAsString('HiZip 默认应用打开测试\nHarmonyOS · 文件已解压到应用缓存。');
    await expectNativeRejection(
      () => NativeDocuments.openWithDefault(source.path, mimeType: 'invalid'),
    );
    checks.add('default open MIME validation');
    await expectNativeRejection(
      () => NativePlatform.channel.invokeMethod<void>('openWithDefault', {
        'path': source.path,
        'writable': 'invalid',
      }),
    );
    checks.add('default open access mode validation');
    final archive = p.join(root.path, 'default-open.zip');
    await NativeArchive.create(
      archive,
      [source.path],
      [p.basename(source.path)],
    );
    final service = ArchiveService(temporaryRoot: root.path);
    final doc = await service.read(archive);
    await Future<void>.delayed(const Duration(seconds: 2));
    final opened = await service.open(doc, doc.entries.single);
    checks.add('archive default viewer launch');
    await report.writeAsString(
      jsonEncode({'success': true, 'checks': checks, 'path': opened.path}),
    );
  } catch (error, stack) {
    await report.writeAsString(
      jsonEncode({
        'success': false,
        'checks': checks,
        'error': '$error',
        'stack': '$stack',
      }),
    );
  }
  debugPrint('HIZIP_DEFAULT_OPEN ${await report.readAsString()}');
}

Future<void> expectNativeRejection(Future<Object?> Function() action) async {
  try {
    await action();
  } on PlatformException catch (error) {
    if (error.code == 'nativeapi_failure') return;
    rethrow;
  }
  throw StateError('The native host accepted invalid input.');
}
