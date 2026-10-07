// Run with: tools/flutter-ohos build hap --debug -t integration_test/ohos_native_smoke.dart
// Starts the real application after exercising the device's FFI engine.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
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
    await report.writeAsString(jsonEncode({'success': true, 'checks': checks}));
  } catch (error, stack) {
    await report.writeAsString(
      jsonEncode({
        'success': false,
        'checks': checks,
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
}
