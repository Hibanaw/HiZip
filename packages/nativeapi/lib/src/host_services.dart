import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
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

/// A system selection and its private engine working copy are distinct locations.
class NativeDocumentLocation {
  const NativeDocumentLocation({
    required this.workingPath,
    required this.uri,
    required this.displayPath,
    required this.writable,
  });
  factory NativeDocumentLocation.fromMap(Map<Object?, Object?> data) =>
      NativeDocumentLocation(
        workingPath: (data['workingPath'] ?? data['path'])! as String,
        uri: data['uri']! as String,
        displayPath: data['displayPath']! as String,
        writable: data['writable'] == true,
      );
  final String workingPath, uri, displayPath;

  /// Compatibility name for engine callers; use displayPath in the UI.
  String get path => workingPath;
  final bool writable;
}

/// Picker grants stay with the source URI; edits are written back after validation.
abstract final class NativeDocuments {
  static final _locations = <String, NativeDocumentLocation>{};
  static String? _remember(Object? value) {
    if (value == null || value is String) return value as String?;
    final location = NativeDocumentLocation.fromMap(
      Map<Object?, Object?>.from(value as Map),
    );
    _locations[location.path] = location;
    return location.path;
  }

  static List<String> _rememberAll(List<Object?>? values) =>
      (values ?? []).map(_remember).whereType<String>().toList();

  static String displayPath(String path) {
    if (!NativePlatform.isHarmonyOS) return path;
    final exact = _locations[path];
    if (exact != null) return exact.displayPath;
    final ancestors =
        _locations.values
            .where((location) => p.isWithin(location.path, path))
            .toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));
    if (ancestors.isNotEmpty) {
      final root = ancestors.first;
      return p.join(root.displayPath, p.relative(path, from: root.path));
    }
    for (final location in _locations.values) {
      if (p.dirname(location.path) == p.dirname(path)) {
        return p.join(p.dirname(location.displayPath), p.basename(path));
      }
    }
    return path.contains('/imports/') ? p.basename(path) : path;
  }

  static String? _initialUri(String? directory) {
    if (directory == null || directory.isEmpty) return null;
    if (directory.startsWith('file://')) return directory;
    final exact = _locations[directory];
    if (exact != null) return exact.uri;
    for (final location in _locations.values) {
      if (p.dirname(location.path) == directory) {
        return location.uri.substring(0, location.uri.lastIndexOf('/'));
      }
    }
    return null;
  }

  static Future<NativeDocumentLocation?> location(String path) async {
    if (!NativePlatform.isHarmonyOS) return null;
    final data = await NativePlatform.channel.invokeMapMethod<Object?, Object?>(
      'documentLocation',
      {'path': path},
    );
    if (data == null) return null;
    _remember(data);
    return _locations[path];
  }

  static Future<NativeDocumentLocation> importUri(
    String uri, {
    bool readOnly = false,
  }) async {
    NativePlatform._requireHarmonyOS();
    final data = await NativePlatform.channel.invokeMapMethod<Object?, Object?>(
      'importDocument',
      {'uri': uri, 'readOnly': readOnly},
    );
    final path = _remember(data)!;
    return _locations[path]!;
  }

  static Future<String?> downloadDirectory() async {
    NativePlatform._requireHarmonyOS();
    return _remember(
      await NativePlatform.channel.invokeMethod<Object?>(
        'downloadDirectoryLocation',
      ),
    );
  }

  static Future<void> prepareWrite(String path) => NativePlatform.channel
      .invokeMethod<void>('prepareDocumentWrite', {'path': path});
  static Future<void> finishWrite(String path) => NativePlatform.channel
      .invokeMethod<void>('finishDocumentWrite', {'path': path});
  static Future<void> abortWrite(String path) => NativePlatform.channel
      .invokeMethod<void>('abortDocumentWrite', {'path': path});

  static void listenForOpenFiles(Future<void> Function(List<String>)? receive) {
    if (!NativePlatform.isHarmonyOS) return;
    Future<void> drain() async {
      final paths = _rememberAll(
        await NativePlatform.channel.invokeListMethod<Object?>(
          'pendingOpenFiles',
        ),
      );
      if (paths.isNotEmpty) await receive?.call(paths);
    }

    NativePlatform.channel.setMethodCallHandler(
      receive == null
          ? null
          : (call) async {
              if (call.method == 'openFilesChanged') await drain();
            },
    );
    if (receive != null) drain();
  }

  static Future<files.XFile?> openFile({
    List<files.XTypeGroup> acceptedTypeGroups = const [],
  }) async {
    if (!NativePlatform.isHarmonyOS) {
      return files.openFile(acceptedTypeGroups: acceptedTypeGroups);
    }
    final path = _remember(
      await NativePlatform.channel.invokeMethod<Object?>('openFile', {
        'extensions': acceptedTypeGroups
            .expand((group) => group.extensions ?? <String>[])
            .toList(),
      }),
    );
    return path == null ? null : files.XFile(path);
  }

  /// Imports a selected directory to the sandbox on HarmonyOS.
  /// Other hosts return the selected directory's original path.
  static Future<String?> openDirectory() async => NativePlatform.isHarmonyOS
      ? _remember(
          await NativePlatform.channel.invokeMethod<Object?>('openDirectory'),
        )
      : files.getDirectoryPath();

  static Future<List<String>> openContents() async {
    NativePlatform._requireHarmonyOS();
    return _rememberAll(
      await NativePlatform.channel.invokeListMethod<Object?>('openContents'),
    );
  }

  static Future<List<files.XFile>> openFiles({
    List<files.XTypeGroup> acceptedTypeGroups = const [],
  }) async {
    if (!NativePlatform.isHarmonyOS) {
      return files.openFiles(acceptedTypeGroups: acceptedTypeGroups);
    }
    final selected = await NativePlatform.channel
        .invokeListMethod<Object?>('openFiles', {
          'extensions': acceptedTypeGroups
              .expand((g) => g.extensions ?? <String>[])
              .toList(),
        });
    return _rememberAll(selected).map(files.XFile.new).toList();
  }

  static Future<files.FileSaveLocation?> getSaveLocation({
    String? suggestedName,
    String? initialDirectory,
    List<files.XTypeGroup> acceptedTypeGroups = const [],
  }) async {
    if (!NativePlatform.isHarmonyOS) {
      return files.getSaveLocation(
        suggestedName: suggestedName,
        initialDirectory: initialDirectory,
        acceptedTypeGroups: acceptedTypeGroups,
      );
    }
    final path = _remember(
      await NativePlatform.channel.invokeMethod<Object?>('saveLocation', {
        'name': suggestedName ?? 'Archive.zip',
        'initialDirectory': _initialUri(initialDirectory),
        'extensions': acceptedTypeGroups
            .expand((g) => g.extensions ?? <String>[])
            .toList(),
      }),
    );
    return path == null ? null : files.FileSaveLocation(path);
  }

  /// The actual system selection, including URI and display path.
  static Future<NativeDocumentLocation?> pickDirectoryLocation({
    String? initialDirectory,
  }) async {
    NativePlatform._requireHarmonyOS();
    final path = _remember(
      await NativePlatform.channel.invokeMethod<Object?>('directoryLocation', {
        'initialDirectory': _initialUri(initialDirectory),
      }),
    );
    return path == null ? null : _locations[path];
  }

  /// Engine compatibility helper. On HarmonyOS this returns a private working
  /// path, never the user-visible system directory; use pickDirectoryLocation
  /// or displayPath for the system selection.
  static Future<String?> getDirectoryPath({
    String? confirmButtonText,
    String? initialDirectory,
  }) async {
    if (!NativePlatform.isHarmonyOS) {
      return files.getDirectoryPath(
        confirmButtonText: confirmButtonText,
        initialDirectory: initialDirectory,
      );
    }
    return (await pickDirectoryLocation(
      initialDirectory: initialDirectory,
    ))?.workingPath;
  }

  static Future<bool> hasDirectoryLocation(String path) async =>
      (await NativePlatform.channel.invokeMethod<bool>('hasDirectoryLocation', {
        'path': path,
      })) ??
      false;
  static Future<String> directorySaveLocation(String root, String name) async =>
      _remember(
        await NativePlatform.channel.invokeMethod<Object?>(
          'directorySaveLocation',
          {'root': root, 'name': name},
        ),
      )!;

  static Future<bool> hasSaveLocation(String path) async =>
      !NativePlatform.isHarmonyOS ||
      (await NativePlatform.channel.invokeMethod<bool>('hasSaveLocation', {
            'path': path,
          }) ??
          false);

  static Future<void> finishSave(String path) async {
    if (!NativePlatform.isHarmonyOS) return;
    _remember(
      await NativePlatform.channel.invokeMethod<Object?>('finishSave', {
        'path': path,
      }),
    );
  }

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

  /// Copies to an already authorized URI without changing the archive's source.
  static Future<void> copyToUri(String path, String uri) {
    NativePlatform._requireHarmonyOS();
    return NativePlatform.channel.invokeMethod<void>('copyDocumentToUri', {
      'path': path,
      'uri': uri,
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
