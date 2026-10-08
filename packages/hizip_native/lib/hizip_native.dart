import 'dart:convert';
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

/// All compression work runs off the UI isolate. The C ABI is shared by all
/// native platforms; no compression implementation lives in Dart.
class NativeArchive {
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
    if (_usesMacFiles) {
      await _files.invokeMethod<void>('commit', {
        'source': source,
        'path': destination,
      });
    } else {
      await File(source).rename(destination);
    }
  }

  static Future<Map<String, dynamic>> list(
    String path, {
    String encoding = 'auto',
  }) => Isolate.run(() => _list(path, encoding));

  /// Transform the decoded native result before returning it to the UI isolate.
  static Future<T> listWith<T>(
    String path,
    T Function(Map<String, dynamic>) decode, {
    String encoding = 'auto',
  }) => Isolate.run(() => listBlocking(path, decode, encoding: encoding));

  /// Worker-only listing/decoding hook; never call this on a UI isolate.
  static T listBlocking<T>(
    String path,
    T Function(Map<String, dynamic>) decode, {
    String encoding = 'auto',
  }) => decode(_list(path, encoding));

  /// Blocking worker-only primitive for a batch, avoiding an isolate per file.
  static void extractBlocking(
    String archive,
    String entry,
    String output, {
    int limit = unlimitedSize,
    String encoding = 'auto',
  }) {
    _call(
      'extract',
      [archive, entry, output],
      limit: limit,
      encoding: encoding,
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
      _configure(lib, encoding: encoding);
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
      if (decoded['error'] != null) {
        throw StateError(decoded['error'] as String);
      }
    } finally {
      _configure(lib);
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
  }) async {
    await Isolate.run(
      () => _call(
        'extract',
        [archive, entry, output],
        limit: limit,
        encoding: encoding,
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
    await Isolate.run(
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
    String encoding = 'auto',
  }) async {
    if (paths.length != names.length) throw ArgumentError('Invalid batch');
    await Isolate.run(
      () => _call(
        'update',
        [archive, output, ...paths, ...names, ...removed],
        limit: paths.length,
        removeCount: removed.length,
        encoding: encoding,
      ),
    );
  }

  static Future<void> create(
    String output,
    List<String> paths,
    List<String> names, {
    String encoding = 'UTF-8',
    int compressionLevel = 6,
  }) async {
    if (paths.isEmpty || paths.length != names.length) {
      throw ArgumentError('Invalid file list');
    }
    await Isolate.run(
      () => _call(
        'create',
        [output, ...paths, ...names],
        limit: paths.length,
        writeEncoding: encoding,
        compressionLevel: compressionLevel,
      ),
    );
  }
}

bool _workerPrepared = false;

Map<String, dynamic> _list(String path, String encoding) {
  if (encoding != 'auto') {
    return {
      ..._call('list', [path], encoding: encoding),
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
        ..._call('list', [path], encoding: candidate),
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
  String encoding = 'auto',
  String writeEncoding = 'UTF-8',
  int compressionLevel = 6,
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
    );
    switch (operation) {
      case 'list':
        result = lib.lookupFunction<_One, _One>('hz_list')(pointers[0]);
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
        paths = calloc<Pointer<Utf8>>(limit);
        names = calloc<Pointer<Utf8>>(limit);
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
    if (data['error'] != null) throw StateError(data['error'] as String);
    return data;
  } finally {
    _configure(lib);
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
}) {
  final read = (encoding == 'auto' ? 'UTF-8' : encoding).toNativeUtf8();
  final write = writeEncoding.toNativeUtf8();
  try {
    lib.lookupFunction<
      Void Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
      void Function(Pointer<Utf8>, Pointer<Utf8>, int)
    >('hz_configure_encoding')(read, write, compressionLevel);
  } finally {
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
