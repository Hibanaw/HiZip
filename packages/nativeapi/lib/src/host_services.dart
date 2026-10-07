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

  static Future<String> applicationSupportDirectory() async =>
      NativePlatform.isHarmonyOS
      ? (await NativePlatform.channel.invokeMethod<String>(
          'applicationSupportDirectory',
        ))!
      : (await paths.getApplicationSupportDirectory()).path;
}

/// Pickers return sandbox copies on HarmonyOS. Export explicitly after edits.
abstract final class NativeDocuments {
  static Future<files.XFile?> openFile({
    List<files.XTypeGroup> acceptedTypeGroups = const [],
  }) async {
    if (!NativePlatform.isHarmonyOS) {
      return files.openFile(acceptedTypeGroups: acceptedTypeGroups);
    }
    final path = await NativePlatform.channel.invokeMethod<String>('openFile', {
      'extensions': acceptedTypeGroups
          .expand((group) => group.extensions ?? <String>[])
          .toList(),
    });
    return path == null ? null : files.XFile(path);
  }

  /// Imports a selected directory to the sandbox on HarmonyOS.
  /// Other hosts return the selected directory's original path.
  static Future<String?> openDirectory() => NativePlatform.isHarmonyOS
      ? NativePlatform.channel.invokeMethod<String>('openDirectory')
      : files.getDirectoryPath();

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
    final path = await NativePlatform.channel
        .invokeMethod<String>('saveLocation', {
          'name': suggestedName ?? 'Archive.zip',
          'extensions': acceptedTypeGroups
              .expand((g) => g.extensions ?? <String>[])
              .toList(),
        });
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

  static Future<void> openWithDefault(
    String path, {
    String? mimeType,
    bool writable = false,
  }) {
    NativePlatform._requireHarmonyOS();
    return NativePlatform.channel.invokeMethod<void>('openWithDefault', {
      'path': path,
      'mimeType': mimeType,
      'writable': writable,
    });
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

class NativeTitleButtonRect {
  const NativeTitleButtonRect({
    this.right = 0,
    this.top = 0,
    this.width = 0,
    this.height = 0,
  });

  factory NativeTitleButtonRect.fromMap(Map<String, Object?> data) =>
      NativeTitleButtonRect(
        right: (data['right'] as num?)?.toDouble() ?? 0,
        top: (data['top'] as num?)?.toDouble() ?? 0,
        width: (data['width'] as num?)?.toDouble() ?? 0,
        height: (data['height'] as num?)?.toDouble() ?? 0,
      );

  final double right, top, width, height;
}

class NativeHostWindowState {
  const NativeHostWindowState({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.status,
    this.decorVisible = true,
    this.titleButtons = const NativeTitleButtonRect(),
  });
  factory NativeHostWindowState.fromMap(Map<String, Object?> data) =>
      NativeHostWindowState(
        x: (data['x']! as num).toDouble(),
        y: (data['y']! as num).toDouble(),
        width: (data['width']! as num).toDouble(),
        height: (data['height']! as num).toDouble(),
        status: (data['status']! as num).toInt(),
        decorVisible: data['decorVisible'] as bool? ?? true,
        titleButtons: NativeTitleButtonRect.fromMap(
          Map<String, Object?>.from(data['titleButtons'] as Map? ?? const {}),
        ),
      );

  /// Bounds in physical pixels; status uses HarmonyOS WindowStatusType values.
  final double x, y, width, height;
  final int status;
  final bool decorVisible;
  final NativeTitleButtonRect titleButtons;
  bool get isFullScreen => status == 1;
  bool get isMaximized => status == 2;
  bool get isMinimized => status == 3;
  bool get isFloating => status == 4;
  bool get isSplitScreen => status == 5;
}

/// Async HarmonyOS main-window APIs. Desktop APIs remain Window/WindowManager.
abstract final class NativeHostWindow {
  static const _closeChannel = MethodChannel('nativeapi/hizip/windowClose');
  static Future<void>? _preparingClose;
  static const _events = EventChannel('nativeapi/hizip/windowState');
  static final _changes = _events.receiveBroadcastStream().map(
    (event) =>
        NativeHostWindowState.fromMap(Map<String, Object?>.from(event as Map)),
  );

  /// Emits the current bounds and mode on listen and subsequent host changes.
  static Stream<NativeHostWindowState> get changes {
    NativePlatform._requireHarmonyOS();
    return _changes;
  }

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
    double? maxWidth,
    double? maxHeight,
  }) {
    NativePlatform._requireHarmonyOS();
    for (final dimension in [minWidth, minHeight, maxWidth, maxHeight]) {
      if (dimension != null &&
          (!dimension.isFinite || dimension <= 0 || dimension > 2147483647)) {
        throw ArgumentError(
          'Window dimensions must be finite, positive and at most 2147483647.',
        );
      }
    }
    if ((minWidth != null && maxWidth != null && minWidth > maxWidth) ||
        (minHeight != null && maxHeight != null && minHeight > maxHeight)) {
      throw ArgumentError(
        'Window minimum dimensions must not exceed maximum dimensions.',
      );
    }
    return NativePlatform.channel.invokeMethod<void>('configureWindow', {
      'title': title,
      'minWidth': minWidth,
      'minHeight': minHeight,
      'maxWidth': maxWidth,
      'maxHeight': maxHeight,
    });
  }

  static Future<void> setDecorVisible(bool visible, {int? height}) {
    NativePlatform._requireHarmonyOS();
    if (height != null && (height < 37 || height > 112)) {
      throw ArgumentError.value(height, 'height', 'Must be 37–112 vp.');
    }
    return NativePlatform.channel.invokeMethod<void>('setWindowDecorVisible', {
      'visible': visible,
      'height': ?height,
    });
  }

  static void setClosePreparation(Future<void> Function()? prepare) {
    NativePlatform._requireHarmonyOS();
    _closeChannel.setMethodCallHandler(
      prepare == null
          ? null
          : (call) async {
              if (call.method != 'prepareWindowClose') {
                throw MissingPluginException();
              }
              try {
                await (_preparingClose ??= Future<void>.sync(prepare));
                return true;
              } finally {
                _preparingClose = null;
              }
            },
    );
  }

  /// Requests a position in physical pixels. The host may clamp it to screen.
  static Future<void> moveTo(int x, int y) {
    NativePlatform._requireHarmonyOS();
    if (x < -2147483648 ||
        x > 2147483647 ||
        y < -2147483648 ||
        y > 2147483647) {
      throw ArgumentError('Window coordinates must be signed 32-bit integers.');
    }
    return NativePlatform.channel.invokeMethod<void>('moveWindow', {
      'x': x,
      'y': y,
    });
  }

  /// Requests a size in physical pixels, subject to system window limits.
  static Future<void> resize(int width, int height) {
    NativePlatform._requireHarmonyOS();
    if (width <= 0 ||
        width > 2147483647 ||
        height <= 0 ||
        height > 2147483647) {
      throw ArgumentError(
        'Window dimensions must be positive 32-bit integers.',
      );
    }
    return NativePlatform.channel.invokeMethod<void>('resizeWindow', {
      'width': width,
      'height': height,
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
