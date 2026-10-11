import 'dart:async';
import 'dart:convert';

import 'zip_metadata.dart';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

typedef _One = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _PrepareWorkerNative = Void Function();
typedef _ExtractNative =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int64);
typedef _Extract =
    Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int);
typedef _Four =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _CreateNative =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      Int32,
    );
typedef _Create =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      int,
    );

typedef _UpdateNative =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      Int32,
      Pointer<Pointer<Utf8>>,
      Int32,
    );
typedef _Update =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      int,
      Pointer<Pointer<Utf8>>,
      int,
    );

typedef _BatchProgressNative = Void Function(Int32, Int64, Int32, Int64, Int64);
typedef _BatchNative =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      Pointer<Int64>,
      Int32,
      Int64,
      Pointer<NativeFunction<_BatchProgressNative>>,
    );
typedef _Batch =
    Pointer<Utf8> Function(
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      Pointer<Int64>,
      int,
      int,
      Pointer<NativeFunction<_BatchProgressNative>>,
    );

class ArchiveOperationCancelled implements Exception {
  const ArchiveOperationCancelled();
  @override
  String toString() => 'Operation cancelled';
}

/// A task owns this control until every worker has drained. Never send the
/// controller object to an isolate; send its native address instead.
class NativeOperationControl {
  Pointer<Void> _pointer = nullptr;
  int _state = 0;
  bool _disposed = false;
  int get state => _pointer == nullptr
      ? _state
      : _openLibrary().lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('hz_control_get')(_pointer);
  int get address {
    if (_disposed) throw StateError('Operation control disposed');
    if (_pointer == nullptr) {
      _pointer = _openLibrary()
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'hz_control_create',
          )();
      if (_pointer == nullptr) {
        throw StateError('Cannot allocate operation control');
      }
      _set(_state);
    }
    return _pointer.address;
  }

  void _set(int value) {
    if (_disposed || state >= 2) return;
    _state = value;
    if (_pointer != nullptr) {
      _openLibrary().lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('hz_control_set')(_pointer, value);
    }
  }

  void pause() => _set(1);
  void resume() => _set(0);
  void cancel() => _set(2);
  void beginCommit() {
    if (state == 2) throw const ArchiveOperationCancelled();
    _set(3);
    if (state == 2) throw const ArchiveOperationCancelled();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_pointer != nullptr) {
      _openLibrary().lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('hz_control_free')(_pointer);
    }
    _pointer = nullptr;
  }
}

Future<T> _runNative<T>(FutureOr<T> Function() work) {
  final address = NativeArchive.controlAddress;
  return Isolate.run(() => NativeArchive.withControlAddress(address, work));
}

/// All compression work runs off the UI isolate. The C ABI is shared by all
/// native platforms; no compression implementation lives in Dart.
class NativeArchive {
  static final _controlKey = Object();
  static int get controlAddress {
    final value = Zone.current[_controlKey];
    return value is NativeOperationControl ? value.address : value as int? ?? 0;
  }

  static T withControl<T>(NativeOperationControl control, T Function() work) =>
      runZoned(work, zoneValues: {_controlKey: control});
  static T withControlAddress<T>(int address, T Function() work) =>
      runZoned(work, zoneValues: {_controlKey: address});
  static void checkpointBlocking() {
    final address = controlAddress;
    if (address == 0) return;
    if (_openLibrary().lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('hz_control_checkpoint')(Pointer.fromAddress(address)) ==
        0) {
      throw const ArchiveOperationCancelled();
    }
  }

  static Future<void> checkpoint() async {
    final value = Zone.current[_controlKey];
    int state() => value is NativeOperationControl
        ? value.state
        : value is int && value != 0
        ? _openLibrary().lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('hz_control_get')(Pointer.fromAddress(value))
        : 0;
    while (state() == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (state() == 2) throw const ArchiveOperationCancelled();
  }

  static void beginCommit() {
    final value = Zone.current[_controlKey];
    if (value is NativeOperationControl) value.beginCommit();
    if (value is int && value != 0) {
      final lib = _openLibrary(), pointer = Pointer<Void>.fromAddress(value);
      lib.lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >('hz_control_set')(pointer, 3);
      if (lib.lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('hz_control_get')(pointer) ==
          2) {
        throw const ArchiveOperationCancelled();
      }
    }
  }

  /// The native ABI uses signed 64-bit byte counts; no application size cap.
  static const unlimitedSize = 0x7fffffffffffffff;
  static const _files = MethodChannel('dev.hizip/native_files');
  static bool get _usesMacFiles =>
      Platform.isMacOS && Platform.environment['HIZIP_NATIVE_LIBRARY'] == null;
  static Future<Directory> stagingDirectory(String destination) async {
    if (_usesMacFiles) {
      final path = await _files.invokeMethod<String>('replacementDirectory', {
        'path': destination,
      });
      if (path == null) throw StateError('Missing replacement directory');
      return Directory(path);
    }
    return File(destination).parent.createTemp('.hizip-');
  }

  static Future<void> commit(String source, String destination) async {
    await checkpoint();
    beginCommit();
    if (_usesMacFiles) {
      await _files.invokeMethod<void>('commit', {
        'source': source,
        'path': destination,
      });
    } else {
      await File(source).rename(destination);
    }
  }

  static Future<void> commitNew(String source, String destination) async {
    await checkpoint();
    beginCommit();
    await _runNative(() => _call('publishNew', [source, destination]));
  }

  static Future<Map<String, dynamic>> capabilities() =>
      _runNative(() => _call('capabilities', []));

  static Future<void> setReadOnly(String path, bool readOnly) async {
    await _runNative(() => _call('readOnly', [path], limit: readOnly ? 1 : 0));
  }

  static Future<Map<String, dynamic>> list(
    String path, {
    String encoding = 'auto',
    String password = '',
  }) => _runNative(() => _list(path, encoding, password));

  /// Transform the decoded native result before returning it to the UI isolate.
  static Future<T> listWith<T>(
    String path,
    T Function(Map<String, dynamic>) decode, {
    String encoding = 'auto',
    String password = '',
  }) => _runNative(
    () => listBlocking(path, decode, encoding: encoding, password: password),
  );

  /// Worker-only listing/decoding hook; never call this on a UI isolate.
  static T listBlocking<T>(
    String path,
    T Function(Map<String, dynamic>) decode, {
    String encoding = 'auto',
    String password = '',
  }) => decode(_list(path, encoding, password));

  /// Blocking worker-only primitive for a batch, avoiding an isolate per file.
  static void extractBlocking(
    String archive,
    String entry,
    String output, {
    int limit = unlimitedSize,
    String encoding = 'auto',
    String password = '',
  }) {
    _call(
      'extract',
      [archive, entry, output],
      limit: limit,
      encoding: encoding,
      password: password,
    );
  }

  /// Called on a worker isolate. The callback executes synchronously on that
  /// worker's thread and must only send lightweight progress messages.
  static void extractBatchBlocking(
    String archive,
    List<String> entries,
    List<String> outputs,
    List<int> limits, {
    required int totalLimit,
    String encoding = 'auto',
    String password = '',
    void Function(int completed, int bytes)? progress,
    void Function(
      int completed,
      int bytes,
      int index,
      int fileBytes,
      int fileSize,
    )?
    detailedProgress,
  }) {
    if (entries.length != outputs.length || entries.length != limits.length) {
      throw ArgumentError('Invalid extraction batch');
    }
    if (entries.isEmpty) return;
    final lib = _openLibrary();
    final path = archive.toNativeUtf8();
    final names = entries.map((s) => s.toNativeUtf8()).toList();
    final destinations = outputs.map((s) => s.toNativeUtf8()).toList();
    final nameArray = calloc<Pointer<Utf8>>(entries.length);
    final outputArray = calloc<Pointer<Utf8>>(entries.length);
    final sizeArray = calloc<Int64>(entries.length);
    final callback = progress == null && detailedProgress == null
        ? null
        : NativeCallable<_BatchProgressNative>.isolateLocal((
            int done,
            int bytes,
            int index,
            int fileBytes,
            int fileSize,
          ) {
            progress?.call(done, bytes);
            detailedProgress?.call(done, bytes, index, fileBytes, fileSize);
          });
    Pointer<Utf8> result = nullptr;
    try {
      _configure(lib, encoding: encoding, password: password);
      for (var i = 0; i < entries.length; i++) {
        nameArray[i] = names[i];
        outputArray[i] = destinations[i];
        sizeArray[i] = limits[i];
      }
      result =
          lib.lookupFunction<_BatchNative, _Batch>('hz_extract_batch_detailed')(
            path,
            nameArray,
            outputArray,
            sizeArray,
            entries.length,
            totalLimit,
            callback?.nativeFunction ?? nullptr,
          );
      if (result == nullptr) {
        throw StateError('Native extraction returned no result');
      }
      final decoded = jsonDecode(result.toDartString()) as Map<String, dynamic>;
      if (decoded['error'] == 'Operation cancelled') {
        throw const ArchiveOperationCancelled();
      }
      if (decoded['error'] != null) {
        throw StateError(decoded['error'] as String);
      }
    } finally {
      _configure(lib);
      lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('hz_control_bind')(nullptr);
      callback?.close();
      if (result != nullptr) {
        lib.lookupFunction<
          Void Function(Pointer<Utf8>),
          void Function(Pointer<Utf8>)
        >('hz_free')(result);
      }
      calloc.free(path);
      for (final value in [...names, ...destinations]) {
        calloc.free(value);
      }
      calloc.free(nameArray);
      calloc.free(outputArray);
      calloc.free(sizeArray);
    }
  }

  static Future<void> extract(
    String archive,
    String entry,
    String output, {
    int limit = unlimitedSize,
    String encoding = 'auto',
    String password = '',
  }) async {
    await _runNative(
      () => _call(
        'extract',
        [archive, entry, output],
        limit: limit,
        encoding: encoding,
        password: password,
      ),
    );
  }

  static Future<void> replace(
    String archive,
    String entry,
    String file,
    String output, {
    String encoding = 'auto',
  }) async {
    await _runNative(
      () =>
          _call('replace', [archive, entry, file, output], encoding: encoding),
    );
  }

  static Future<void> update(
    String archive,
    String output,
    List<String> paths,
    List<String> names,
    List<String> removed, {
    Map<String, String> commentPaths = const {},
    String encoding = 'auto',
  }) async {
    if (paths.length != names.length) throw ArgumentError('Invalid batch');
    await _runNative(
      () => _call(
        'update',
        [archive, output, ...paths, ...names, ...removed],
        limit: paths.length,
        removeCount: removed.length,
        commentPaths: commentPaths,
        encoding: encoding,
      ),
    );
  }

  static Future<void> rename(
    String archive,
    String oldName,
    String newName,
    String output, {
    String encoding = 'auto',
  }) async {
    await _runNative(
      () => _call('rename', [
        archive,
        oldName,
        newName,
        output,
      ], encoding: encoding),
    );
  }

  static Future<Map<String, dynamic>> verify(
    String archive, {
    String encoding = 'auto',
    String password = '',
  }) => _runNative(
    () => _call('verify', [archive], encoding: encoding, password: password),
  );

  static Future<void> create(
    String output,
    List<String> paths,
    List<String> names, {
    String encoding = 'UTF-8',
    int compressionLevel = 6,
    String password = '',
    String encryption = 'none',
    String zipCompression = 'deflate',
  }) async {
    if (paths.length != names.length) {
      throw ArgumentError('Invalid file list');
    }
    await _runNative(
      () => _call(
        'create',
        [output, ...paths, ...names],
        limit: paths.length,
        writeEncoding: encoding,
        compressionLevel: compressionLevel,
        password: password,
        encryption: encryption,
        zipCompression: zipCompression,
      ),
    );
  }
}

bool _workerPrepared = false;

Map<String, dynamic> _list(String path, String encoding, String password) {
  if (encoding != 'auto') {
    return {
      ..._call('list', [path], encoding: encoding, password: password),
      'encoding': encoding,
    };
  }
  // Honor Unicode headers first. Legacy archives without a charset marker need
  // a fallback; ambiguous filenames can always be corrected through the menu.
  Object? lastError;
  for (final candidate in [
    'UTF-8',
    'GB18030',
    'BIG5',
    'CP932',
    'CP949',
    'CP437',
  ]) {
    try {
      return {
        ..._call('list', [path], encoding: candidate, password: password),
        'encoding': candidate,
      };
    } on FormatException catch (error) {
      lastError = error;
    } on StateError catch (error) {
      final message = error.toString().toLowerCase();
      if (!message.contains('convert') &&
          !message.contains('charset') &&
          !message.contains('encoding')) {
        rethrow;
      }
      lastError = error;
    }
  }
  throw StateError('无法识别文件名编码，请通过编码菜单选择：$lastError');
}

Map<String, dynamic> _call(
  String operation,
  List<String> args, {
  int limit = 0,
  int removeCount = 0,
  Map<String, String> commentPaths = const {},
  String encoding = 'auto',
  String writeEncoding = 'UTF-8',
  int compressionLevel = 6,
  String password = '',
  String encryption = 'none',
  String zipCompression = 'deflate',
}) {
  final lib = _openLibrary();
  final pointers = args.map((s) => s.toNativeUtf8()).toList();
  Pointer<Utf8> result = nullptr;
  Pointer<Pointer<Utf8>> paths = nullptr, names = nullptr, removed = nullptr;
  try {
    _configure(
      lib,
      encoding: encoding,
      writeEncoding: writeEncoding,
      compressionLevel: compressionLevel,
      password: password,
      encryption: encryption,
      zipCompression: zipCompression,
    );
    switch (operation) {
      case 'capabilities':
        result = lib
            .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
              'hz_capabilities',
            )();
      case 'readOnly':
        result = lib
            .lookupFunction<
              Pointer<Utf8> Function(Pointer<Utf8>, Int32),
              Pointer<Utf8> Function(Pointer<Utf8>, int)
            >('hz_set_read_only')(pointers[0], limit);
      case 'publishNew':
        result = lib
            .lookupFunction<
              Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>),
              Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)
            >('hz_publish_new')(pointers[0], pointers[1]);
      case 'list':
        result = lib.lookupFunction<_One, _One>('hz_list')(pointers[0]);
      case 'verify':
        result = lib.lookupFunction<_One, _One>('hz_verify')(pointers[0]);
      case 'rename':
        result = lib.lookupFunction<_Four, _Four>('hz_rename')(
          pointers[0],
          pointers[1],
          pointers[2],
          pointers[3],
        );
      case 'extract':
        result = lib.lookupFunction<_ExtractNative, _Extract>('hz_extract')(
          pointers[0],
          pointers[1],
          pointers[2],
          limit,
        );
      case 'replace':
        result = lib.lookupFunction<_Four, _Four>('hz_replace')(
          pointers[0],
          pointers[1],
          pointers[2],
          pointers[3],
        );
      case 'update':
        paths = calloc<Pointer<Utf8>>(limit == 0 ? 1 : limit);
        names = calloc<Pointer<Utf8>>(limit == 0 ? 1 : limit);
        removed = calloc<Pointer<Utf8>>(removeCount == 0 ? 1 : removeCount);
        for (var i = 0; i < limit; i++) {
          paths[i] = pointers[2 + i];
          names[i] = pointers[2 + limit + i];
        }
        for (var i = 0; i < removeCount; i++) {
          removed[i] = pointers[2 + limit * 2 + i];
        }
        result = lib.lookupFunction<_UpdateNative, _Update>('hz_update')(
          pointers[0],
          pointers[1],
          paths,
          names,
          limit,
          removed,
          removeCount,
        );
      case 'create':
        paths = calloc<Pointer<Utf8>>(limit == 0 ? 1 : limit);
        names = calloc<Pointer<Utf8>>(limit == 0 ? 1 : limit);
        for (var i = 0; i < limit; i++) {
          paths[i] = pointers[i + 1];
          names[i] = pointers[i + 1 + limit];
        }
        result = lib.lookupFunction<_CreateNative, _Create>('hz_create')(
          pointers[0],
          paths,
          names,
          limit,
        );
    }
    if (result == nullptr) {
      throw StateError('Native archive engine returned no result');
    }
    final data = jsonDecode(result.toDartString()) as Map<String, dynamic>;
    if (data['error'] != null &&
        lib.lookupFunction<
              Int32 Function(Pointer<Void>),
              int Function(Pointer<Void>)
            >('hz_control_get')(
              Pointer.fromAddress(NativeArchive.controlAddress),
            ) ==
            2) {
      throw const ArchiveOperationCancelled();
    }
    if (data['error'] == 'Operation cancelled') {
      throw const ArchiveOperationCancelled();
    }
    if (data['error'] != null) throw StateError(data['error'] as String);
    if (['replace', 'update', 'rename'].contains(operation)) {
      final output = operation == 'update' ? args[1] : args[3];
      ZipMetadata.preserve(
        args[0],
        output,
        renameFrom: operation == 'rename' ? args[1] : null,
        renameTo: operation == 'rename' ? args[2] : null,
        copies: commentPaths,
      );
    }
    if (operation == 'list' &&
        (data['format'] as String).toUpperCase().startsWith('ZIP')) {
      final metadata = ZipMetadata.read(args[0], parseEntries: false);
      data['comment'] = metadata?.text ?? '';
    }
    return data;
  } finally {
    _configure(lib);
    lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)
    >('hz_control_bind')(nullptr);
    if (result != nullptr) {
      lib.lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('hz_free')(result);
    }
    for (final p in pointers) {
      calloc.free(p);
    }
    if (paths != nullptr) calloc.free(paths);
    if (names != nullptr) calloc.free(names);
    if (removed != nullptr) calloc.free(removed);
  }
}

void _configure(
  DynamicLibrary lib, {
  String encoding = 'auto',
  String writeEncoding = 'UTF-8',
  int compressionLevel = 6,
  String password = '',
  String encryption = 'none',
  String zipCompression = 'deflate',
}) {
  lib.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
  >('hz_control_bind')(Pointer.fromAddress(NativeArchive.controlAddress));
  if (password.contains('\u0000') || utf8.encode(password).length > 4096) {
    throw ArgumentError(
      'Password must be at most 4096 UTF-8 bytes without null characters',
    );
  }
  final secret = password.toNativeUtf8();
  final encrypted = encryption.toNativeUtf8();
  final method = zipCompression.toNativeUtf8();
  final read = (encoding == 'auto' ? 'UTF-8' : encoding).toNativeUtf8();
  final write = writeEncoding.toNativeUtf8();
  try {
    lib.lookupFunction<
      Void Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
      void Function(Pointer<Utf8>, Pointer<Utf8>, int)
    >('hz_configure_encoding')(read, write, compressionLevel);
    lib.lookupFunction<
      Void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
      void Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)
    >('hz_configure_security')(secret, encrypted, method);
  } finally {
    secret
        .cast<Uint8>()
        .asTypedList(utf8.encode(password).length)
        .fillRange(0, utf8.encode(password).length, 0);
    calloc.free(secret);
    calloc.free(encrypted);
    calloc.free(method);
    calloc.free(read);
    calloc.free(write);
  }
}

DynamicLibrary _openLibrary() {
  final override = Platform.environment['HIZIP_NATIVE_LIBRARY'];
  final lib = DynamicLibrary.open(
    override ??
        (Platform.isMacOS || Platform.isIOS
            ? 'hizip_native.framework/hizip_native'
            : Platform.isWindows
            ? 'hizip_native.dll'
            : 'libhizip_native.so'),
  );
  if (!_workerPrepared) {
    lib.lookupFunction<_PrepareWorkerNative, void Function()>(
      'hz_prepare_worker',
    )();
    _workerPrepared = true;
  }
  return lib;
}
