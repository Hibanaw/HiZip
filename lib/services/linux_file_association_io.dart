import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/archive_formats.dart';

const _desktopFileName = 'com.hibanaw.hizip.desktop';

String _desktopExec(String executable) {
  final escaped = executable
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('`', r'\`')
      .replaceAll(r'$', r'\$');
  return '"$escaped"';
}

String _desktopEntry() =>
    '''[Desktop Entry]
Type=Application
Name=HiZip
Comment=Archive manager
Exec=${_desktopExec(Platform.resolvedExecutable)} %F
TryExec=${Platform.resolvedExecutable}
Terminal=false
Categories=Utility;Archiving;
MimeType=${readableArchiveMimeTypes.map((type) => '$type;').join()}
StartupWMClass=com.hibanaw.hizip
''';

Future<File> _installDesktopEntry() async {
  final environment = Platform.environment;
  final dataHome = environment['XDG_DATA_HOME']?.isNotEmpty == true
      ? environment['XDG_DATA_HOME']!
      : p.join(environment['HOME'] ?? '', '.local', 'share');
  if (dataHome.isEmpty) {
    throw StateError('无法确定 Linux 用户数据目录');
  }
  final applications = Directory(p.join(dataHome, 'applications'));
  await applications.create(recursive: true);
  final desktopFile = File(p.join(applications.path, _desktopFileName));
  await desktopFile.writeAsString(_desktopEntry());
  return desktopFile;
}

Future<int> setDefaultArchiveHandler() async {
  if (!Platform.isLinux) {
    throw UnsupportedError('Linux 文件关联仅支持 Linux 桌面端');
  }
  await _installDesktopEntry();
  var updated = 0;
  Object? firstError;
  for (final mimeType in readableArchiveMimeTypes) {
    try {
      final result = await Process.run('xdg-mime', [
        'default',
        _desktopFileName,
        mimeType,
      ]);
      if (result.exitCode == 0) {
        updated++;
      } else {
        firstError ??= StateError(
          'xdg-mime 设置 $mimeType 失败：${result.stderr}'.trim(),
        );
      }
    } on ProcessException catch (error) {
      firstError ??= error;
    }
  }
  if (updated == 0 && firstError != null) throw firstError;
  return updated;
}

Future<List<String>> initialArchivePaths() async {
  if (!Platform.isLinux) return const [];
  return Platform.executableArguments
      .where(
        (argument) =>
            argument.isNotEmpty &&
            argument != '--' &&
            !argument.startsWith('-') &&
            File(argument).existsSync() &&
            isReadableArchivePath(argument),
      )
      .toList();
}
