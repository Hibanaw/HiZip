import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' as paths;
import 'package:shared_preferences/shared_preferences.dart';

/// Host services maintained by HiZip, independent of the generated desktop FFI.
abstract final class NativePlatform {
  static bool get isHarmonyOS =>
      !kIsWeb && defaultTargetPlatform.name == 'ohos';
  static const channel = MethodChannel('nativeapi/hizip');

  /// Runtime information and capabilities, without unique device identifiers.
  static Future<NativeHostInfo> hostInfo() async {
    _requireHarmonyOS();
    final data = await channel.invokeMapMethod<String, Object?>('hostInfo');
    return NativeHostInfo.fromMap(data!);
  }

  static void _requireHarmonyOS() {
    if (!isHarmonyOS) {
      throw UnsupportedError('This host API requires HarmonyOS.');
    }
  }
}

class NativeHostInfo {
  const NativeHostInfo({
    required this.deviceType,
    required this.apiVersion,
    required this.capabilities,
  });
  factory NativeHostInfo.fromMap(Map<String, Object?> data) => NativeHostInfo(
    deviceType: data['deviceType']! as String,
    apiVersion: (data['apiVersion']! as num).toInt(),
    capabilities: Set.unmodifiable(
      (data['capabilities']! as List).cast<String>(),
    ),
  );
  final String deviceType;
  final int apiVersion;
  final Set<String> capabilities;
}

abstract final class NativePaths {
  static Future<String> temporaryDirectory() async => NativePlatform.isHarmonyOS
      ? (await NativePlatform.channel.invokeMethod<String>(
          'temporaryDirectory',
        ))!
      : (await paths.getTemporaryDirectory()).path;
}

/// Pickers return sandbox copies on HarmonyOS. Export explicitly after edits.
abstract final class NativeDocuments {
  static Future<List<files.XFile>> openFiles({
    List<files.XTypeGroup> acceptedTypeGroups = const [],
  }) async {
    if (!NativePlatform.isHarmonyOS) {
      return files.openFiles(acceptedTypeGroups: acceptedTypeGroups);
    }
    final selected = await NativePlatform.channel
        .invokeListMethod<String>('openFiles', {
          'extensions': acceptedTypeGroups
              .expand((g) => g.extensions ?? <String>[])
              .toList(),
        });
    return (selected ?? []).map(files.XFile.new).toList();
  }

  static Future<files.FileSaveLocation?> getSaveLocation({
    String? suggestedName,
    List<files.XTypeGroup> acceptedTypeGroups = const [],
  }) async {
    if (!NativePlatform.isHarmonyOS) {
      return files.getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: acceptedTypeGroups,
      );
    }
    final path = await NativePlatform.channel.invokeMethod<String>(
      'saveLocation',
      {'name': suggestedName ?? 'Archive.zip'},
    );
    return path == null ? null : files.FileSaveLocation(path);
  }

  static Future<String?> getDirectoryPath({String? confirmButtonText}) {
    if (!NativePlatform.isHarmonyOS) {
      return files.getDirectoryPath(confirmButtonText: confirmButtonText);
    }
    return NativePlatform.channel.invokeMethod<String>('directoryLocation');
  }

  static Future<void> finishSave(String path) => NativePlatform.isHarmonyOS
      ? NativePlatform.channel.invokeMethod<void>('finishSave', {'path': path})
      : Future.value();

  static Future<String> finishDirectory(String root, String output) async {
    if (!NativePlatform.isHarmonyOS) return output;
    return (await NativePlatform.channel.invokeMethod<String>(
      'finishDirectory',
      {'root': root, 'path': output},
    ))!;
  }

  /// Returns false when the user cancels the document save picker.
  static Future<bool> exportFile(String path) async {
    NativePlatform._requireHarmonyOS();
    return (await NativePlatform.channel.invokeMethod<bool>('exportFile', {
          'path': path,
        })) ??
        false;
  }
}

class NativeSettings {
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();
  Future<String?> getString(String key) => NativePlatform.isHarmonyOS
      ? NativePlatform.channel.invokeMethod<String>('getPreference', {
          'key': key,
        })
      : _preferences.getString(key);
  Future<int?> getInt(String key) async => NativePlatform.isHarmonyOS
      ? int.tryParse(await getString(key) ?? '')
      : _preferences.getInt(key);
  Future<void> setString(String key, String value) => NativePlatform.isHarmonyOS
      ? NativePlatform.channel.invokeMethod<void>('setPreference', {
          'key': key,
          'value': value,
        })
      : _preferences.setString(key, value);
  Future<void> setInt(String key, int value) => NativePlatform.isHarmonyOS
      ? setString(key, value.toString())
      : _preferences.setInt(key, value);
  Future<void> remove(String key) => NativePlatform.isHarmonyOS
      ? NativePlatform.channel.invokeMethod<void>('removePreference', {
          'key': key,
        })
      : _preferences.remove(key);
}

class NativeHostWindowState {
  const NativeHostWindowState({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.status,
  });
  factory NativeHostWindowState.fromMap(Map<String, Object?> data) =>
      NativeHostWindowState(
        x: (data['x']! as num).toDouble(),
        y: (data['y']! as num).toDouble(),
        width: (data['width']! as num).toDouble(),
        height: (data['height']! as num).toDouble(),
        status: (data['status']! as num).toInt(),
      );

  /// Bounds in physical pixels; status uses HarmonyOS WindowStatusType values.
  final double x, y, width, height;
  final int status;
  bool get isMaximized => status == 2;
}

/// Async HarmonyOS main-window APIs. Desktop APIs remain Window/WindowManager.
abstract final class NativeHostWindow {
  static Future<NativeHostWindowState> state() async {
    NativePlatform._requireHarmonyOS();
    return NativeHostWindowState.fromMap(
      (await NativePlatform.channel.invokeMapMethod<String, Object?>(
        'windowState',
      ))!,
    );
  }

  static Future<void> configure({
    String? title,
    double? minWidth,
    double? minHeight,
  }) {
    NativePlatform._requireHarmonyOS();
    if ((minWidth != null && (!minWidth.isFinite || minWidth <= 0)) ||
        (minHeight != null && (!minHeight.isFinite || minHeight <= 0))) {
      throw ArgumentError(
        'Window minimum dimensions must be finite and positive.',
      );
    }
    return NativePlatform.channel.invokeMethod<void>('configureWindow', {
      'title': title,
      'minWidth': minWidth,
      'minHeight': minHeight,
    });
  }

  static Future<void> _command(String method) {
    NativePlatform._requireHarmonyOS();
    return NativePlatform.channel.invokeMethod<void>(method);
  }

  static Future<void> minimize() => _command('minimizeWindow');
  static Future<void> maximize() => _command('maximizeWindow');
  static Future<void> restore() => _command('restoreWindow');
  static Future<void> close() => _command('closeWindow');
  static Future<void> startMoving() => _command('startMovingWindow');
}
