import 'harmony_bridge.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// File URLs, rather than text paths, preserve native file-manager semantics.
class FileTransferClipboard {
  Future<void> writeFiles(List<String> paths) async {
    if (HarmonyBridge.supported) {
      throw UnsupportedError('鸿蒙文件传输请使用保存副本或解压导出。');
    }
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) throw UnsupportedError('当前平台不支持文件剪贴板。');
    await clipboard.write(
      paths.map(
        (path) =>
            DataWriterItem(suggestedName: Uri.file(path).pathSegments.last)
              ..add(Formats.fileUri(Uri.file(path))),
      ),
    );
  }

  Future<List<String>> readFiles() async {
    if (HarmonyBridge.supported) {
      throw UnsupportedError('鸿蒙文件传输请使用保存副本或解压导出。');
    }
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) throw UnsupportedError('当前平台不支持文件剪贴板。');
    final reader = await clipboard.read();
    final paths = <String>[];
    for (final item in reader.items) {
      final uri = await item.readValue(Formats.fileUri);
      if (uri != null && uri.scheme == 'file') paths.add(uri.toFilePath());
    }
    return paths;
  }
}
