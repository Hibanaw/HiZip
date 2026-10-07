import 'package:nativeapi/nativeapi.dart';

/// Compatibility facade; native implementation is maintained in nativeapi.
class HarmonyBridge {
  static bool get supported => NativePlatform.isHarmonyOS;
  static const channel = NativePlatform.channel;
  static Future<String> temporaryDirectory() =>
      NativePaths.temporaryDirectory();
  static Future<bool> exportFile(String path) =>
      NativeDocuments.exportFile(path);
  static Future<void> openWithDefault(
    String path, {
    String? mimeType,
    bool writable = false,
  }) => NativeDocuments.openWithDefault(
    path,
    mimeType: mimeType,
    writable: writable,
  );
  static Future<String> finishDirectory(String root, String output) =>
      NativeDocuments.finishDirectory(root, output);
  static Future<void> finishSave(String path) =>
      NativeDocuments.finishSave(path);
}
