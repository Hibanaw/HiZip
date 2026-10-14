import 'dart:io';

import 'package:path/path.dart' as p;

/// Per-user Explorer context menu: one HiZip entry with a submenu for
/// "Create Archive…" and "Quick Create ZIP", the Windows counterpart of the
/// macOS Finder extension. It only writes HKCU\Software\Classes, so no
/// administrator rights are needed. Windows 11 lists classic verbs under
/// "Show more options".
class WindowsShellMenu {
  const WindowsShellMenu({this.run = _runReg});

  /// Runs `reg.exe` with [args]; replaceable in tests.
  final Future<ProcessResult> Function(List<String> args) run;

  static const _targets = ['*', 'Directory'];
  static const _root = r'HKCU\Software\Classes';
  static const _entry = 'HiZip';
  static const flag = '--hizip-compress';

  static Future<ProcessResult> _runReg(List<String> args) =>
      Process.run('reg', args);

  static String command(String executable, String action) =>
      '"$executable" $flag=$action "%1"';

  String _key(String target, [String sub = '']) =>
      '$_root\\$target\\shell\\$_entry$sub';

  Future<void> _add(String key, {String? name, required String value}) async {
    final result = await run([
      'add',
      key,
      if (name == null) '/ve' else ...['/v', name],
      '/t',
      'REG_SZ',
      '/d',
      value,
      '/f',
    ]);
    if (result.exitCode != 0) {
      throw ProcessException('reg', ['add', key], '${result.stderr}'.trim());
    }
  }

  Future<bool> isInstalled() async {
    for (final target in _targets) {
      final result = await run(['query', _key(target)]);
      if (result.exitCode != 0) return false;
    }
    return true;
  }

  Future<void> install({
    required String executable,
    required String title,
    required String createLabel,
    required String quickZipLabel,
  }) async {
    for (final target in _targets) {
      final root = _key(target);
      await _add(root, name: 'MUIVerb', value: title);
      await _add(root, name: 'Icon', value: '"$executable",0');
      // An empty SubCommands value makes the verb a cascading menu whose
      // items live under its own "shell" key.
      await _add(root, name: 'SubCommands', value: '');
      for (final (id, label, action) in [
        ('1create', createLabel, 'create'),
        ('2quickZip', quickZipLabel, 'quickZip'),
      ]) {
        final item = _key(target, '\\shell\\$id');
        await _add(item, value: label);
        await _add('$item\\command', value: command(executable, action));
      }
    }
  }

  Future<void> uninstall() async {
    for (final target in _targets) {
      final result = await run(['delete', _key(target), '/f']);
      // Exit code 1 also means the key was already gone.
      if (result.exitCode != 0 && await isInstalledTarget(target)) {
        throw ProcessException('reg', [
          'delete',
          _key(target),
        ], '${result.stderr}'.trim());
      }
    }
  }

  Future<bool> isInstalledTarget(String target) async =>
      (await run(['query', _key(target)])).exitCode == 0;
}

/// The Windows 11 context menu: an IExplorerCommand in `hizip_shell.dll`
/// that Explorer loads through a sparse package, registered per user from the
/// loose files next to the executable. Needs Windows 11 and Developer Mode
/// (or a signed package); callers fall back to [WindowsShellMenu] otherwise.
class WindowsModernMenu {
  const WindowsModernMenu({this.runPowerShell = _run});

  /// Runs a PowerShell command; replaceable in tests.
  final Future<ProcessResult> Function(String script) runPowerShell;

  static const packageName = 'com.hibanaw.hizip.ContextMenu';

  static Future<ProcessResult> _run(String script) => Process.run(
    'powershell',
    ['-NoProfile', '-NonInteractive', '-Command', script],
  );

  static String _quote(String value) => "'${value.replaceAll("'", "''")}'";

  /// True when the build ships the handler and its package manifest.
  static bool isBundled(String executable) {
    final directory = p.dirname(executable);
    return File(p.join(directory, 'hizip_shell.dll')).existsSync() &&
        File(p.join(directory, 'shell_package', 'AppxManifest.xml'))
            .existsSync();
  }

  Future<void> register(String executable) async {
    final directory = p.dirname(executable);
    final manifest = p.join(directory, 'shell_package', 'AppxManifest.xml');
    final result = await runPowerShell(
      "\$ErrorActionPreference = 'Stop'; Add-AppxPackage -Register "
      '${_quote(manifest)} '
      '-ExternalLocation ${_quote(directory)}',
    );
    if (result.exitCode != 0) {
      throw ProcessException('powershell', const [], '${result.stderr}'.trim());
    }
  }

  Future<void> unregister() async {
    final result = await runPowerShell(
      "\$ErrorActionPreference = 'Stop'; "
      'Get-AppxPackage ${_quote(packageName)} | Remove-AppxPackage',
    );
    if (result.exitCode != 0) {
      throw ProcessException('powershell', const [], '${result.stderr}'.trim());
    }
  }
}
