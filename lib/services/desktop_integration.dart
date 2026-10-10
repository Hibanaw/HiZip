import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import 'dart:convert';

import '../models/application_menu.dart';
import '../models/finder_compression_request.dart';

import 'linux_file_association_io.dart' as linux;

class DefaultApplication {
  const DefaultApplication(this.name, this.icon);
  final String name;
  final Uint8List? icon;
}

class FileApplication extends DefaultApplication {
  const FileApplication(
    super.name,
    super.icon,
    this.path, {
    this.isDefault = false,
  });
  final String path;
  final bool isDefault;
}

/// Native desktop APIs stay separate from archive algorithms.
/// Missing platform support leaves the regular Flutter UI usable.
class DesktopIntegration {
  bool? lastDragSucceeded;
  static const channel = MethodChannel('dev.hizip/native_files');
  bool get supportsMenuBar => defaultTargetPlatform == TargetPlatform.macOS;
  bool get supportsQuickLook => defaultTargetPlatform == TargetPlatform.macOS;
  bool get supportsFileIntegration =>
      (defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux);
  bool get supportsDefaultApplication =>
      (defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux);
  final _icons = <String, Future<Uint8List?>>{};
  final _applications = <String, Future<DefaultApplication?>>{};
  final _handlers = <String, Future<List<FileApplication>>>{};

  FileApplication _application(Map<Object?, Object?> info) => FileApplication(
    info['name'] as String,
    info['icon'] as Uint8List?,
    info['path'] as String,
    isDefault: info['default'] == true,
  );

  Future<List<FileApplication>> applicationsForFile(String name) {
    if (!supportsFileIntegration) return Future.value([]);
    return _handlers.putIfAbsent(p.extension(name).toLowerCase(), () async {
      try {
        final apps = await channel.invokeListMethod<Object?>(
          'applicationsForFile',
          {'path': name},
        );
        return (apps ?? [])
            .map((e) => _application(e as Map<Object?, Object?>))
            .toList();
      } on MissingPluginException {
        return [];
      } on PlatformException {
        return [];
      }
    });
  }

  Future<FileApplication?> chooseApplication([String? name]) async {
    if (!supportsFileIntegration) return null;
    final app = await channel.invokeMapMethod<Object?, Object?>(
      'chooseApplication',
      name == null ? null : {'path': name},
    );
    return app == null ? null : _application(app);
  }

  Future<void> openWith(String path, FileApplication app) => channel
      .invokeMethod<void>('openWith', {'path': path, 'application': app.path});

  Future<List<String>> selectCompressionContents({
    bool foldersOnly = false,
  }) async {
    final prompt = _translations['选择'] ?? '选择';
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return await channel.invokeListMethod<String>(
            'selectCompressionContents',
            {'foldersOnly': foldersOnly, 'prompt': prompt},
          ) ??
          [];
    }
    if (foldersOnly) {
      return (await getDirectoryPaths(confirmButtonText: prompt))
          .whereType<String>()
          .toList();
    }
    return (await openFiles(confirmButtonText: prompt))
        .map((file) => file.path)
        .toList();
  }

  void listen({
    required void Function(int) navigate,
    Future<void> Function()? prepareClose,
    void Function(String)? command,
    void Function(String)? openArchive,
    Future<void> Function(FinderCompressionRequest)? compressFiles,
    VoidCallback? clearRecent,
    VoidCallback? dragEnded,
    VoidCallback? dragStarted,
  }) {
    if (!supportsQuickLook) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'prepareWindowClose') {
        await prepareClose?.call();
        return;
      }
      if (call.method == 'quickLookNavigate') navigate(call.arguments as int);
      if (call.method == 'fileCommand') command?.call(call.arguments as String);
      if (call.method == 'openArchive') {
        openArchive?.call(call.arguments as String);
      }
      if (call.method == 'compressFiles') {
        await compressFiles?.call(
          FinderCompressionRequest.fromPlatform(call.arguments),
        );
      }
      if (call.method == 'clearRecent') clearRecent?.call();
      if (call.method == 'fileDragEnded') {
        lastDragSucceeded = call.arguments as bool?;
        dragEnded?.call();
      }
      if (call.method == 'fileDragStarted') dragStarted?.call();
    });
  }

  Future<void> enableFileCommands(bool enabled) async {
    if (!supportsQuickLook) return;
    try {
      await channel.invokeMethod<void>('fileCommandsEnabled', enabled);
    } on MissingPluginException {
      /* Not installed on the current target. */
    }
  }

  Future<void> startFileDrag(List<String> paths, {required bool movable}) =>
      channel.invokeMethod<void>('startFileDrag', {
        'paths': paths,
        'movable': movable,
      });

  Future<List<String>> initializeMenus() async {
    if (!supportsQuickLook) return [];
    try {
      return await channel.invokeListMethod<String>('configureMenus') ?? [];
    } on MissingPluginException {
      return [];
    }
  }

  Future<int> setDefaultArchiveHandler() async {
    if (supportsQuickLook) {
      return await channel.invokeMethod<int>('setDefaultArchiveHandler') ?? 0;
    }
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return linux.setDefaultArchiveHandler();
    }
    throw UnsupportedError('当前平台不支持设置默认打开方式');
  }

  Future<void> showFinderExtensionSettings() =>
      channel.invokeMethod<void>('showFinderExtensionSettings');

  Future<bool> authorizeFileAccess({
    List<String> readPaths = const [],
    List<String> writeDirectories = const [],
  }) async {
    if (!supportsQuickLook) return true;
    String text(String source) => _translations[source] ?? source;
    try {
      return await channel.invokeMethod<bool>('authorizeFileAccess', {
            'readPaths': readPaths,
            'writeDirectories': writeDirectories,
            'message': text('HiZip 需要访问此目录中的文件，并在此创建或安全更新压缩包。授权会被记住。'),
            'prompt': text('授权此目录'),
            'chooseMessage': text('请选择所需目录或包含它的上级目录。'),
            'failureMessage': text('无法访问所选目录，请检查权限后重试。'),
          }) ??
          true;
    } on MissingPluginException {
      // Headless tests and older native hosts have no permission broker.
      return true;
    }
  }

  Future<List<String>> initialArchivePaths() => linux.initialArchivePaths();

  Future<void> noteRecentArchive(String path) async {
    if (!supportsQuickLook) return;
    try {
      await channel.invokeMethod<void>('noteRecentArchive', {'path': path});
    } on MissingPluginException {
      /* Not installed on this target. */
    }
  }

  String? _language;
  Map<String, String> _translations = const {};
  Future<void> setLanguage(
    String language, {
    Map<String, String> translations = const {},
    Map<String, String> english = const {},
  }) async {
    _translations = translations;
    if (!supportsQuickLook || _language == language) return;
    _language = language;
    try {
      await channel.invokeMethod<void>('language', {
        'language': language,
        'translations': translations,
        'english': english,
      });
    } on MissingPluginException {
      /* No native menus on this target. */
    }
  }

  String? _appearance;
  Future<void> setAppearance(String mode) async {
    if (!supportsQuickLook || _appearance == mode) return;
    _appearance = mode;
    try {
      await channel.invokeMethod<void>('appearance', mode);
    } on MissingPluginException {
      /* Not installed on this target. */
    }
  }

  String? _menuState;
  Future<String?> promptEntryName(String title, String initialName) async =>
      channel.invokeMethod<String>('promptEntryName', {
        'title': title,
        'name': initialName,
      });

  Future<void> updateMenuState({
    required bool busy,
    required bool hasDocument,
    String encoding = 'auto',
    bool writable = false,
    bool hasSelection = false,
    bool textEditing = false,
    List<ApplicationMenuItem> menus = const [],
  }) async {
    if (!supportsQuickLook) return;
    final menuData = menus.map((menu) => menu.toJson()).toList();
    final state = jsonEncode([
      busy,
      hasDocument,
      encoding,
      writable,
      hasSelection,
      textEditing,
      menuData,
    ]);
    if (_menuState == state) return;
    _menuState = state;
    try {
      await channel.invokeMethod<void>('menuState', {
        'busy': busy,
        'hasDocument': hasDocument,
        'encoding': encoding,
        'writable': writable,
        'hasSelection': hasSelection,
        'textEditing': textEditing,
        'menus': menuData,
      });
    } on MissingPluginException {
      /* Not installed on this target. */
    }
  }

  Future<void> prepareFileDrag(
    List<String> paths, {
    required bool movable,
    required List<double> frame,
  }) => channel.invokeMethod<void>('prepareFileDrag', {
    'paths': paths,
    'movable': movable,
    'frame': frame,
  });

  Future<Uint8List?> fileIcon(
    String name, {
    bool directory = false,
    int pixelSize = 128,
  }) {
    if (!supportsFileIntegration) return Future.value();
    // Reuse a few resolutions while resizing instead of caching every pixel size.
    var resolution = 32;
    final requestedSize = pixelSize.clamp(32, 1024);
    while (resolution < requestedSize) {
      resolution *= 2;
    }
    final type = directory ? 'folder' : p.extension(name).toLowerCase();
    final key = '$type:$resolution';
    return _icons.putIfAbsent(key, () async {
      try {
        return await channel.invokeMethod<Uint8List>('fileIcon', {
          'path': name,
          'directory': directory,
          'pixelSize': resolution,
        });
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    });
  }

  Future<DefaultApplication?> defaultApplication(String name) {
    if (!supportsFileIntegration) return Future.value();
    return _applications.putIfAbsent(p.extension(name).toLowerCase(), () async {
      try {
        final info = await channel.invokeMapMethod<String, dynamic>(
          'defaultApplication',
          {'path': name},
        );
        if (info == null || info['name'] is! String) return null;
        return DefaultApplication(
          info['name'] as String,
          info['icon'] as Uint8List?,
        );
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    });
  }

  Future<bool> quickLookVisible() async {
    if (!supportsQuickLook) return false;
    return await channel.invokeMethod<bool>('quickLookVisible') ?? false;
  }

  Future<void> showQuickLook(String path) =>
      channel.invokeMethod<void>('quickLook', {'path': path});
  Future<void> closeQuickLook() async {
    if (!supportsQuickLook) return;
    try {
      await channel.invokeMethod<void>('closeQuickLook');
    } on MissingPluginException {
      /* Not installed on the current target. */
    }
  }

  void dispose() {
    if (supportsQuickLook) channel.setMethodCallHandler(null);
  }
}
