import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/finder_compression_request.dart';
import 'package:hizip/services/windows_shell_menu.dart';

void main() {
  modernMenuTests();
  test('registers a cascading HiZip verb for files and folders', () async {
    final calls = <List<String>>[];
    final menu = WindowsShellMenu(
      run: (args) async {
        calls.add(args);
        return ProcessResult(0, 0, '', '');
      },
    );
    await menu.install(
      executable: r'C:\Apps\HiZip\hizip.exe',
      title: 'HiZip',
      createLabel: '创建压缩包',
      quickZipLabel: '快速创建 ZIP',
    );
    expect(calls.every((call) => call.first == 'add'), isTrue);
    final keys = calls.map((call) => call[1]).toSet();
    for (final target in ['*', 'Directory']) {
      final root =
          r'HKCU\Software\Classes\'
          '$target'
          r'\shell\HiZip';
      expect(keys, contains(root.replaceAll(' ', '')));
    }
    final commands = calls
        .where((call) => call[1].endsWith(r'\command'))
        .map((call) => call[call.indexOf('/d') + 1])
        .toSet();
    expect(commands, {
      r'"C:\Apps\HiZip\hizip.exe" --hizip-compress=create "%1"',
      r'"C:\Apps\HiZip\hizip.exe" --hizip-compress=quickZip "%1"',
    });
    expect(
      calls.any((call) => call.contains('SubCommands') && call.last == '/f'),
      isTrue,
    );
  });

  test('removing an absent menu is not an error', () async {
    final menu = WindowsShellMenu(
      run: (args) async => ProcessResult(0, 1, '', 'not found'),
    );
    await menu.uninstall();
    expect(await menu.isInstalled(), isFalse);
  });

  test('Explorer requests accept drive and UNC paths', () {
    final request = FinderCompressionRequest.fromPlatform({
      'action': 'quickZip',
      'paths': [
        r'C:\Users\me\文件 1.txt',
        r'C:\Users\me\.\文件 1.txt',
        r'\\nas\share\a',
      ],
    });
    expect(request.paths, [r'C:\Users\me\文件 1.txt', r'\\nas\share\a']);
    expect(
      () => FinderCompressionRequest.fromPlatform({
        'action': 'create',
        'paths': [r'relative\a'],
      }),
      throwsFormatException,
    );
  });
}

void modernMenuTests() {
  test('registers the sparse package from the files next to the exe', () async {
    final scripts = <String>[];
    final menu = WindowsModernMenu(
      runPowerShell: (script) async {
        scripts.add(script);
        return ProcessResult(0, 0, '', '');
      },
    );
    await menu.register(r"C:\Apps\Hi'Zip\hizip.exe");
    await menu.unregister();
    expect(scripts[0], contains('Add-AppxPackage -Register'));
    expect(
      scripts[0],
      contains(r"'C:\Apps\Hi''Zip\shell_package\AppxManifest.xml'"),
    );
    expect(scripts[0], contains(r"-ExternalLocation 'C:\Apps\Hi''Zip'"));
    expect(scripts[1], contains('Remove-AppxPackage'));
    final failing = WindowsModernMenu(
      runPowerShell: (_) async => ProcessResult(0, 1, '', 'denied'),
    );
    expect(
      () => failing.register(r'C:\a\hizip.exe'),
      throwsA(isA<ProcessException>()),
    );
  });
}
