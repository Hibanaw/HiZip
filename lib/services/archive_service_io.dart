import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/archive_entry.dart';
import '../models/preview_limit.dart';
import '../models/extraction_progress.dart';
import '../models/archive_index.dart';
import 'archive_worker.dart';
import 'extraction_plan.dart';

class ArchiveDocument {
  ArchiveDocument(
    this.path,
    this.entries,
    this.format,
    this.writable, {
    ArchiveIndex? index,
    this.encoding = 'auto',
    String? resolvedEncoding,
  }) : resolvedEncoding = resolvedEncoding ?? encoding,
       index = index ?? ArchiveIndex(entries);
  final ArchiveIndex index;
  final String path, format, encoding, resolvedEncoding;
  final List<ArchiveEntry> entries;
  final bool writable;
}

class OpenedArchiveFile {
  OpenedArchiveFile(
    this.archive,
    this.entry,
    this.path,
    this.hash,
    this.archiveHash,
    this.stat,
  );
  final String archive, path;
  String encoding = 'auto';
  String entry;
  String hash, archiveHash;
  FileStat stat;
  bool pending = false, retained = false, discardOnClose = false;
}

class _ArchiveCache {
  _ArchiveCache(this.directory);
  final Future<Directory> directory;
  final jobs = <Future<dynamic>>{};
}

class ArchiveService {
  ArchiveService({this.temporaryRoot, this.maxExtractionWorkers});

  /// Optional cap for benchmarks and low-resource hosts; auto reserves CPU for
  /// the UI and native window event loops.
  int? maxExtractionWorkers;
  String readEncoding = 'auto', createEncoding = 'UTF-8';
  int compressionLevel = 6;
  final String? temporaryRoot;
  bool get supported => true;
  Directory? _session;
  Future<Directory>? _creatingSession;
  final List<OpenedArchiveFile> _opened = [];
  final _archiveCaches = <String, _ArchiveCache>{};
  final _closingCaches = <String, Future<void>>{};
  final _clipboardExports = <String, List<String>>{};
  final _expiredClipboardExports = <String>{};
  bool _disposed = false;
  Future<void>? _disposing;

  Future<T> _cached<T>(String archive, Future<T> Function(Directory) work) {
    if (_disposed || _closingCaches.containsKey(archive)) {
      return Future.error(StateError('压缩包缓存正在关闭。'));
    }
    final cache = _archiveCaches.putIfAbsent(
      archive,
      () => _ArchiveCache(() async {
        return (await session).createTemp('archive-');
      }()),
    );
    final job = Future<T>.sync(() async => work(await cache.directory));
    cache.jobs.add(job);
    job.then<void>(
      (_) {
        cache.jobs.remove(job);
      },
      onError: (Object _, StackTrace _) {
        cache.jobs.remove(job);
      },
    );
    return job;
  }

  /// Drain readers/export workers before removing this archive's temporary data.
  Future<void> closeArchive(String archive) => _closingCaches.putIfAbsent(
    archive,
    () => _closeArchive(archive).whenComplete(() {
      _closingCaches.remove(archive);
    }),
  );

  Future<void> _closeArchive(String archive) async {
    final cache = _archiveCaches[archive];
    if (cache == null) return;
    await Future.wait(
      cache.jobs.toList().map((job) async {
        try {
          await job;
        } catch (_) {}
      }),
    );
    late final Directory directory;
    try {
      directory = await cache.directory;
    } catch (_) {
      _archiveCaches.remove(archive);
      _preparing.removeWhere((key, _) => key.startsWith('$archive\u0000'));
      return;
    }
    final kept = <String>{
      ..._clipboardExports.keys.where(
        (root) => p.dirname(root) == directory.path,
      ),
    };
    for (final file
        in _opened.where((file) => file.archive == archive).toList()) {
      if (!p.isWithin(directory.path, file.path) ||
          !await File(file.path).exists()) {
        continue;
      }
      var preserve = file.retained;
      if (!preserve && !file.discardOnClose) {
        try {
          preserve = await _digest(file.path) != file.hash;
        } catch (_) {
          preserve = true;
        }
      }
      if (preserve) {
        kept.add(File(file.path).parent.path);
      }
    }
    if (await directory.exists()) {
      await for (final child in directory.list(followLinks: false)) {
        if (!kept.contains(child.path)) await child.delete(recursive: true);
      }
      if (kept.isEmpty) await directory.delete();
    }
    _opened.removeWhere((file) => file.archive == archive);
    _preparing.removeWhere((key, _) => key.startsWith('$archive\u0000'));
    _archiveCaches.remove(archive);
    for (final root in _expiredClipboardExports.toList()) {
      if (p.dirname(root) == directory.path) {
        await _releaseClipboardExport(root);
      }
    }
  }

  Future<void> retain(OpenedArchiveFile file) async {
    file.retained = true;
    file.discardOnClose = false;
    await acknowledge(file);
  }

  Future<void> discard(OpenedArchiveFile file) async {
    await acknowledge(file);
    file.retained = false;
    file.discardOnClose = true;
  }

  /// Clipboard exports are leased until the clipboard changes or the app exits.
  Future<void> retainClipboardExports(List<String> paths) async {
    await updateClipboardExports(paths);
    final root = _session;
    if (root == null) return;
    for (final path in paths) {
      final directory = p.dirname(path);
      if (p.isWithin(root.path, directory) &&
          p.basename(directory).startsWith('transfer-')) {
        _clipboardExports[directory] = List.of(paths);
      }
    }
  }

  Future<void> updateClipboardExports(List<String> current) async {
    final caches = _archiveCaches.values.toList();
    final roots = await Future.wait(caches.map((cache) => cache.directory));
    for (final entry in _clipboardExports.entries.toList()) {
      if (entry.value.every(current.contains)) continue;
      _clipboardExports.remove(entry.key);
      _expiredClipboardExports.add(entry.key);
    }
    for (final root in _expiredClipboardExports.toList()) {
      var active = false;
      for (var i = 0; i < roots.length; i++) {
        if (roots[i].path == p.dirname(root) &&
            _archiveCaches.containsValue(caches[i])) {
          active = true;
        }
      }
      if (!active) await _releaseClipboardExport(root);
    }
  }

  Future<void> _releaseClipboardExport(String root) async {
    final directory = Directory(root);
    final parent = directory.parent;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      if (await parent.exists() && await parent.list().isEmpty) {
        await parent.delete();
      }
    } on FileSystemException {
      if (await directory.exists()) rethrow;
    }
    _expiredClipboardExports.remove(root);
  }

  Future<Directory> get session {
    if (_session != null) return Future.value(_session!);
    return _creatingSession ??= _createSession().catchError((
      Object error,
      StackTrace trace,
    ) {
      _creatingSession = null;
      Error.throwWithStackTrace(error, trace);
    });
  }

  Future<Directory> _createSession() async {
    final root = temporaryRoot == null
        ? await getTemporaryDirectory()
        : Directory(temporaryRoot!);
    await root.create(recursive: true);
    return _session = await root.createTemp('hizip-');
  }

  Future<String> _digest(String path) => _runHashFile(path);
  Future<ArchiveDocument> read(String path) => _readArchive(path, readEncoding);

  Future<String> _temporary(
    ArchiveDocument doc,
    ArchiveEntry e, {
    required Directory cache,
    int limit = NativeArchive.unlimitedSize,
  }) async {
    _validate(e);
    if (doc.index.counts[e.normalized] != 1) {
      throw StateError('此路径存在重复条目，无法安全打开。');
    }
    final dir = await cache.createTemp('file-');
    final output = p.join(dir.path, e.name);
    try {
      await NativeArchive.extract(
        doc.path,
        e.path,
        output,
        limit: limit,
        encoding: doc.resolvedEncoding,
      );
      return output;
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) =>
      _cached(doc.path, (cache) async {
        final limit = entry.isText ? 2 * 1024 * 1024 : 20 * 1024 * 1024;
        if (entry.size > limit) throw const PreviewLimitExceeded();
        late final String path;
        try {
          path = await _temporary(doc, entry, cache: cache, limit: limit);
        } on StateError catch (error) {
          if (error.message == 'File exceeds extraction size limit' ||
              error.message == 'Extraction size limit exceeded') {
            throw const PreviewLimitExceeded();
          }
          rethrow;
        }
        try {
          return await File(path).readAsBytes();
        } finally {
          await File(path).parent.delete(recursive: true);
        }
      });

  // Quick Look's own Open button can launch an editor too, so the same
  // prepared file is monitored and reused for both preview and external open.
  final _preparing = <String, Future<OpenedArchiveFile>>{};
  Future<OpenedArchiveFile> prepareExternal(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) {
    final key = '${doc.path}\u0000${entry.path}';
    return _preparing.putIfAbsent(
      key,
      () => _cached(doc.path, (cache) async {
        try {
          _validate(entry);
          final existing = _opened
              .where((f) => f.archive == doc.path && f.entry == entry.path)
              .firstOrNull;
          if (existing != null) return existing;
          final path = await _temporary(doc, entry, cache: cache);
          final watched = OpenedArchiveFile(
            doc.path,
            entry.path,
            path,
            await _digest(path),
            await _digest(doc.path),
            await File(path).stat(),
          )..encoding = doc.resolvedEncoding;
          _opened.add(watched);
          return watched;
        } catch (_) {
          _preparing.remove(key);
          rethrow;
        }
      }),
    );
  }

  Future<OpenedArchiveFile> open(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) async {
    final watched = await prepareExternal(doc, entry);
    final result = await OpenFilex.open(watched.path);
    if (result.type != ResultType.done) throw StateError(result.message);
    return watched;
  }

  Future<List<OpenedArchiveFile>> changes() async {
    final changed = <OpenedArchiveFile>[];
    for (final f in _opened) {
      if (f.pending || !await File(f.path).exists()) continue;
      final stat = await File(f.path).stat();
      if (stat.modified != f.stat.modified || stat.size != f.stat.size) {
        final hash = await _digest(f.path);
        f.stat = stat;
        if (hash != f.hash) {
          f.pending = true;
          changed.add(f);
        }
      }
    }
    return changed;
  }

  Future<void> acknowledge(OpenedArchiveFile file) async {
    file.hash = await _digest(file.path);
    file.stat = await File(file.path).stat();
    file.pending = false;
  }

  Future<void> save(OpenedArchiveFile file) => _cached(file.archive, (
    cache,
  ) async {
    if (await _digest(file.archive) != file.archiveHash) {
      throw StateError('原压缩包已被其他程序修改。为避免覆盖，请保留临时文件并重新打开压缩包。');
    }
    final snapshot = await _digest(file.path);
    final current = await _readArchive(file.archive, file.encoding);
    if (!current.writable) throw StateError('当前格式仅支持读取。请另存临时文件，或创建新的可写压缩包。');
    // Stage alongside the archive so the final rename stays on one filesystem.
    final staging = await NativeArchive.stagingDirectory(file.archive);
    final output = p.join(staging.path, p.basename(file.archive));
    try {
      await NativeArchive.replace(
        file.archive,
        file.entry,
        file.path,
        output,
        encoding: file.encoding,
      );
      await _readArchive(output, 'auto'); // Verify headers before committing.
      if (await _digest(file.archive) != file.archiveHash ||
          await _digest(file.path) != snapshot) {
        throw StateError('文件在保存过程中再次发生变化，请重试。');
      }
      // Retain the original in the session for recovery.
      await File(file.archive).copy(
        p.join(
          cache.path,
          'backup-${DateTime.now().microsecondsSinceEpoch}.zip',
        ),
      );
      await NativeArchive.commit(output, file.archive);
      final hash = await _digest(file.archive);
      for (final f in _opened.where((f) => f.archive == file.archive)) {
        f.archiveHash = hash;
      }
      await acknowledge(file);
      file.retained = false;
      file.discardOnClose = false;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  });

  Future<String> extract(
    ArchiveDocument doc,
    String destination, {
    ArchiveEntry? entry,
    void Function(int, int)? progress,
    void Function(ExtractionProgress)? detailedProgress,
  }) async {
    final events = ReceivePort();
    var reported = -1;
    final subscription = events.listen((event) {
      final values = event as List;
      if (values[0] != reported) {
        reported = values[0] as int;
        progress?.call(reported, values[1] as int);
      }
      if (values.length > 2) {
        detailedProgress?.call(
          ExtractionProgress(
            completed: values[0] as int,
            totalFiles: values[1] as int,
            bytes: values[2] as int,
            totalBytes: values[3] as int,
            currentFile: values[4] as String,
            fileBytes: values[5] as int,
            fileSize: values[6] as int,
          ),
        );
      }
    });
    final port = events.sendPort;
    try {
      final result = await _runExtract(
        doc,
        destination,
        entry,
        port,
        maxExtractionWorkers,
      );
      if (reported != result.$2) progress?.call(result.$2, result.$2);
      return result.$1;
    } finally {
      await subscription.cancel();
      events.close();
    }
  }

  /// Materialize a selection for the system clipboard/drag session. These are
  /// independent export snapshots, not the externally edited file sessions.
  Future<List<String>> exportEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) => _cached(doc.path, (cache) async {
    final sessionPath = cache.path;
    return _runExportArchive(doc, entries, sessionPath);
  });

  Future<(List<String>, List<String>)> _inputFiles(
    List<String> roots,
    List<String> names,
  ) => runArchiveWorker(
    () => _scanInputFiles(roots, names),
    name: 'hizip-file-scan',
  );

  Future<ArchiveDocument> importFiles(
    ArchiveDocument doc,
    List<String> sources,
    String folder, {
    List<ArchiveEntry> moving = const [],
    String? expectedArchiveHash,
  }) => _cached(doc.path, (cache) async {
    if (!doc.writable) throw StateError('当前格式只支持读取，文件传入和内部移动需要可写入的未加密压缩包。');
    if (folder.isNotEmpty && !isSafeArchivePath(folder)) {
      throw StateError('不安全的目标目录。');
    }
    if (sources.isEmpty) return doc;
    final snapshot = await _digest(doc.path);
    if (expectedArchiveHash != null && expectedArchiveHash != snapshot) {
      throw StateError('压缩包在拖拽过程中已变化，请重试。');
    }
    final current = await _readArchive(doc.path, doc.encoding);
    final plan = await _runImportPlan(current, doc, sources, folder, moving);
    final removed = plan.removed,
        names = plan.names,
        paths = plan.paths,
        targets = plan.targets;
    final staging = await NativeArchive.stagingDirectory(doc.path);
    final output = p.join(staging.path, p.basename(doc.path));
    try {
      await NativeArchive.update(
        doc.path,
        output,
        paths,
        targets,
        removed,
        encoding: doc.resolvedEncoding,
      );
      await _readArchive(output, 'auto');
      if (await _digest(doc.path) != snapshot) {
        throw StateError('压缩包在传输过程中已被修改，请重试。');
      }
      final hashes = plan.hashes;
      await _runCheckInputHashes(hashes);
      await File(doc.path).copy(
        p.join(
          cache.path,
          'backup-${DateTime.now().microsecondsSinceEpoch}.zip',
        ),
      );
      await NativeArchive.commit(output, doc.path);
      final hash = await _digest(doc.path);
      for (final file in _opened.where((f) => f.archive == doc.path)) {
        file.archiveHash = hash;
        for (var i = 0; i < moving.length; i++) {
          final m = moving[i];
          if (file.entry == m.path ||
              (m.directory && file.entry.startsWith('${m.normalized}/'))) {
            _preparing.remove('${doc.path}\u0000${file.entry}');
            file.entry =
                names[i] +
                (file.entry == m.path
                    ? ''
                    : file.entry.substring(m.normalized.length));
          }
        }
      }
      return await _readArchive(doc.path, doc.encoding);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  });

  Future<ArchiveDocument> transferEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
    String folder, {
    bool move = false,
  }) async {
    final roots = topLevelEntries(entries);
    if (move &&
        roots.every(
          (e) =>
              (p.posix.dirname(e.normalized) == '.'
                  ? ''
                  : p.posix.dirname(e.normalized)) ==
              folder,
        )) {
      return doc;
    }
    for (final e in roots) {
      if (e.directory &&
          (folder == e.normalized || folder.startsWith('${e.normalized}/'))) {
        throw StateError('不能将目录放入它自身或子目录中。');
      }
    }
    final snapshot = await _digest(doc.path);
    final sources = await exportEntries(doc, roots);
    return importFiles(
      doc,
      sources,
      folder,
      moving: move ? roots : const [],
      expectedArchiveHash: snapshot,
    );
  }

  Future<ArchiveDocument> createEntry(
    ArchiveDocument doc,
    String folder,
    String name, {
    bool directory = false,
  }) async {
    if (!doc.writable) throw StateError('当前格式只支持读取。');
    if (name.trim().isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        !isSafeArchivePath(name)) {
      throw StateError('请输入有效的名称，不能包含路径分隔符。');
    }
    final temporary = await (await session).createTemp('new-entry-');
    try {
      final path = p.join(temporary.path, name);
      if (directory) {
        await Directory(path).create();
      } else {
        await File(path).writeAsBytes(const []);
      }
      return await importFiles(doc, [path], folder);
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  Future<ArchiveDocument> deleteEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) => _cached(doc.path, (cache) async {
    if (!doc.writable) throw StateError('当前格式只支持读取。');
    if (entries.isEmpty) return doc;
    final snapshot = await _digest(doc.path);
    final current = await _readArchive(doc.path, doc.encoding);
    if (current.entries.length != doc.entries.length ||
        current.entries.asMap().entries.any(
          (entry) =>
              entry.value.path != doc.entries[entry.key].path ||
              entry.value.size != doc.entries[entry.key].size,
        )) {
      throw StateError('压缩包已变化，请重新打开后再试。');
    }
    final roots = topLevelEntries(entries);
    for (final entry in roots) {
      if (!entry.safe ||
          !isSafeArchivePath(entry.normalized) ||
          !current.index.byNormalized.containsKey(entry.normalized)) {
        throw StateError('所选条目已变化或路径不安全，请重新选择。');
      }
    }
    final removed = current.entries
        .where(
          (entry) => roots.any(
            (root) =>
                entry.normalized == root.normalized ||
                (root.directory &&
                    entry.normalized.startsWith('${root.normalized}/')),
          ),
        )
        .map((entry) => entry.path)
        .toList();
    final staging = await NativeArchive.stagingDirectory(doc.path);
    final output = p.join(staging.path, p.basename(doc.path));
    try {
      await NativeArchive.update(
        doc.path,
        output,
        const [],
        const [],
        removed,
        encoding: current.resolvedEncoding,
      );
      await _readArchive(output, 'auto');
      if (await _digest(doc.path) != snapshot) {
        throw StateError('压缩包在删除过程中已被修改，请重试。');
      }
      await File(doc.path).copy(
        p.join(
          cache.path,
          'backup-${DateTime.now().microsecondsSinceEpoch}.zip',
        ),
      );
      await NativeArchive.commit(output, doc.path);
      final hash = await _digest(doc.path);
      for (final file
          in _opened.where((file) => file.archive == doc.path).toList()) {
        if (removed.contains(file.entry)) {
          _opened.remove(file);
          _preparing.remove('${doc.path}\u0000${file.entry}');
        } else {
          file.archiveHash = hash;
        }
      }
      return await _readArchive(doc.path, doc.encoding);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  });

  Future<void> create(String output, List<String> files) async {
    final encoding = createEncoding, level = compressionLevel;
    final names = files.map(p.basename).toList();
    if (names.map((s) => s.toLowerCase()).toSet().length != names.length) {
      throw StateError('所选文件存在同名文件，请先重命名。');
    }
    final dir = await NativeArchive.stagingDirectory(output);
    final staged = p.join(dir.path, p.basename(output));
    try {
      final (paths, targets) = await _inputFiles(files, names);
      await NativeArchive.create(
        staged,
        paths,
        targets,
        encoding: encoding,
        compressionLevel: level,
      );
      await _readArchive(staged, encoding);
      await NativeArchive.commit(staged, output);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    try {
      await Future.wait(_archiveCaches.keys.toList().map(closeArchive));
      await updateClipboardExports(const []);
      final root = _session;
      if (root != null && await root.exists() && await root.list().isEmpty) {
        await root.delete();
      }
    } catch (_) {
      _disposed = false;
      _disposing = null;
      rethrow;
    }
  }
}

Future<String> _runHashFile(String path) =>
    runArchiveWorker(() => _hashFile(path), name: 'hizip-hash');
Future<List<String>> _runExportArchive(
  ArchiveDocument doc,
  List<ArchiveEntry> entries,
  String sessionPath,
) => runArchiveWorker(
  () => _exportArchive(doc, entries, sessionPath),
  name: 'hizip-export',
);
Future<_ImportPlan> _runImportPlan(
  ArchiveDocument current,
  ArchiveDocument doc,
  List<String> sources,
  String folder,
  List<ArchiveEntry> moving,
) => runArchiveWorker(
  () => _prepareImport(current, doc, sources, folder, moving),
  name: 'hizip-import-plan',
);
Future<void> _runCheckInputHashes(Map<String, String> hashes) =>
    runArchiveWorker(
      () => _checkInputHashes(hashes),
      name: 'hizip-input-verify',
    );

Future<String> _hashFile(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();
Future<ArchiveDocument> _readArchive(String path, String encoding) =>
    runArchiveWorker(
      () => NativeArchive.listBlocking(
        path,
        (j) => ArchiveDocument(
          path,
          (j['entries'] as List)
              .map((e) => ArchiveEntry.fromJson(e as Map<String, dynamic>))
              .toList(),
          j['format'] as String,
          j['writable'] as bool,
          encoding: encoding,
          resolvedEncoding: j['encoding'] as String?,
        ),
        encoding: encoding,
      ),
      name: 'hizip-read-index',
    );

class _ImportPlan {
  _ImportPlan(this.removed, this.names, this.paths, this.targets, this.hashes);
  final List<String> removed, names, paths, targets;
  final Map<String, String> hashes;
}

Future<void> _checkInputHashes(Map<String, String> hashes) async {
  for (final entry in hashes.entries) {
    if (await _hashFile(entry.key) != entry.value) {
      throw StateError('来源文件在传输过程中已变化，请重试。');
    }
  }
}

void _validate(ArchiveEntry e) {
  if (!e.canExtract || !isSafeArchivePath(e.normalized)) {
    throw StateError('此文件是链接、加密文件或包含不安全路径，暂不支持解压。');
  }
}

Future<(List<String>, List<String>)> _scanInputFiles(
  List<String> roots,
  List<String> names,
) async {
  final paths = <String>[], targets = <String>[];
  final seen = <String>{};
  Future<void> add(String path, String name) async {
    if (!isSafeArchivePath(name)) throw StateError('不安全的文件名。');
    if (!seen.add(name.toLowerCase())) {
      throw StateError('来源文件夹包含重名或大小写冲突的路径。');
    }
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw StateError('暂不支持传入链接或特殊文件。');
    }
    paths.add(path);
    targets.add(type == FileSystemEntityType.directory ? '$name/' : name);
    if (type == FileSystemEntityType.directory) {
      await for (final child in Directory(path).list(followLinks: false)) {
        await add(child.path, '$name/${p.basename(child.path)}');
      }
    }
  }

  for (var i = 0; i < roots.length; i++) {
    await add(roots[i], names[i]);
  }
  return (paths, targets);
}

Future<(String, int)> _runExtract(
  ArchiveDocument doc,
  String destination,
  ArchiveEntry? entry,
  SendPort port,
  int? maxWorkers,
) => runArchiveWorker(
  () => _extractArchive(doc, destination, entry, port, maxWorkers),
  name: 'hizip-extract',
);

Future<(String, int)> _extractArchive(
  ArchiveDocument doc,
  String destination,
  ArchiveEntry? entry,
  SendPort progress,
  int? maxWorkers,
) async {
  final prefix = entry?.directory == true ? '${entry!.normalized}/' : '';
  final selected = doc.entries
      .where(
        (e) =>
            !e.directory &&
            (entry == null ||
                (entry.directory
                    ? e.normalized.startsWith(prefix)
                    : e.path == entry.path)),
      )
      .toList();
  final seen = <String>{};
  var total = 0;
  for (final e in selected) {
    _validate(e);
    if (!seen.add(e.normalized.toLowerCase())) {
      throw StateError('压缩包含有重复的文件路径，无法安全解压。');
    }
    total += e.size < 0 ? 0 : e.size;
  }
  final root = await Directory(destination)
      .createTemp('${p.basenameWithoutExtension(doc.path)}-');
  try {
    final outputs = <String>[];
    final parents = <String>{};
    for (final e in selected) {
      final output = p.joinAll([root.path, ...e.normalized.split('/')]);
      outputs.add(output);
      parents.add(p.dirname(output));
    }
    for (final parent in parents) {
      await Directory(parent).create(recursive: true);
    }
    final batches = planExtraction(
      selected,
      format: doc.format,
      processors: Platform.numberOfProcessors,
      maxWorkers: maxWorkers ?? (Platform.numberOfProcessors > 2 ? 2 : 1),
    );
    final events = ReceivePort();
    final completed = List<int>.filled(batches.length, 0);
    final extractedBytes = List<int>.filled(batches.length, 0);
    final totalBytes = selected.every((e) => e.size >= 0) ? total : -1;
    final clock = Stopwatch()..start();
    var lastProgress = -100;
    final subscription = events.listen((event) {
      final values = event as List<int>;
      completed[values[0]] = values[1];
      extractedBytes[values[0]] = values[2];
      if (clock.elapsedMilliseconds - lastProgress >= 100) {
        lastProgress = clock.elapsedMilliseconds;
        progress.send([
          completed.fold<int>(0, (a, b) => a + b),
          selected.length,
          extractedBytes.fold<int>(0, (a, b) => a + b),
          totalBytes,
          selected[batches[values[0]][values[3]]].path,
          values[4],
          values[5],
        ]);
      }
    });
    try {
      // Future.wait drains ALL workers before cleanup, including on failure.
      await Future.wait([
        for (var i = 0; i < batches.length; i++)
          _runExtractionBatch(
            doc.path,
            [for (final index in batches[i]) selected[index].path],
            [for (final index in batches[i]) outputs[index]],
            List.filled(batches[i].length, NativeArchive.unlimitedSize),
            NativeArchive.unlimitedSize,
            events.sendPort,
            i,
            doc.resolvedEncoding,
          ),
      ]);
    } finally {
      await subscription.cancel();
      events.close();
    }
    progress.send([selected.length, selected.length, total, total, '', 0, 0]);
    // Preserve empty folders too. Never create archive-provided symlinks.
    for (final e in doc.entries.where(
      (e) =>
          e.directory &&
          (entry == null ||
              (entry.directory &&
                  (e.normalized == entry.normalized ||
                      e.normalized.startsWith(prefix)))),
    )) {
      if (e.safe && isSafeArchivePath(e.normalized)) {
        await Directory(p.joinAll([root.path, ...e.normalized.split('/')]))
            .create(recursive: true);
      }
    }
    return (root.path, selected.length);
  } catch (_) {
    await root.delete(recursive: true);
    rethrow;
  }
}

Future<List<String>> _exportArchive(
  ArchiveDocument doc,
  List<ArchiveEntry> entries,
  String sessionPath,
) async {
  final root = await Directory(sessionPath).createTemp('transfer-');
  final paths = <String>[];
  final seen = <String>{};
  try {
    for (final entry in topLevelEntries(entries)) {
      final target = p.join(root.path, entry.name);
      if (!seen.add(entry.name.toLowerCase())) {
        throw StateError('所选条目存在同名文件。');
      }
      if (entry.directory) {
        if (!entry.safe || !isSafeArchivePath(entry.normalized)) {
          throw StateError('不安全的目录路径。');
        }
        await Directory(target).create();
      }
      final contents = entry.directory
          ? doc.entries.where(
              (e) => e.normalized.startsWith('${entry.normalized}/'),
            )
          : [entry];
      for (final e in contents) {
        final relative = entry.directory
            ? e.normalized.substring(entry.normalized.length + 1)
            : '';
        final output = relative.isEmpty
            ? target
            : p.joinAll([target, ...relative.split('/')]);
        if (e.directory) {
          if (!e.safe || !isSafeArchivePath(e.normalized)) {
            throw StateError('不安全的目录路径。');
          }
          await Directory(output).create(recursive: true);
        } else {
          _validate(e);
          await File(output).parent.create(recursive: true);
          NativeArchive.extractBlocking(
            doc.path,
            e.path,
            output,
            encoding: doc.resolvedEncoding,
          );
        }
      }
      paths.add(target);
    }
    return paths;
  } catch (_) {
    await root.delete(recursive: true);
    rethrow;
  }
}

Future<_ImportPlan> _prepareImport(
  ArchiveDocument current,
  ArchiveDocument doc,
  List<String> sources,
  String folder,
  List<ArchiveEntry> moving,
) async {
  // A drop belongs to the document that was displayed when the drag started.
  if (current.entries.length != doc.entries.length ||
      current.entries.asMap().entries.any(
        (e) =>
            e.value.path != doc.entries[e.key].path ||
            e.value.size != doc.entries[e.key].size,
      )) {
    throw StateError('压缩包已变化，请重新打开后再试。');
  }
  final movePaths = moving.map((e) => e.normalized).toSet();
  final moveDirectories = moving
      .where((e) => e.directory)
      .map((e) => e.normalized)
      .toSet();
  bool removedEntry(ArchiveEntry entry) {
    var path = entry.normalized;
    if (movePaths.contains(path)) return true;
    while (path.contains('/')) {
      path = path.substring(0, path.lastIndexOf('/'));
      if (moveDirectories.contains(path)) return true;
    }
    return false;
  }

  final removed = current.entries
      .where(removedEntry)
      .map((e) => e.path)
      .toList();
  for (final m in moving) {
    if (folder == m.normalized || folder.startsWith('${m.normalized}/')) {
      throw StateError('不能将目录移动到它自身或子目录中。');
    }
  }
  final exact = <String>{};
  for (final e in current.entries) {
    if (!exact.add(e.normalized.toLowerCase())) {
      throw StateError('压缩包含有重复路径，无法安全修改。');
    }
    if (!e.directory &&
        (folder == e.normalized || folder.startsWith('${e.normalized}/'))) {
      throw StateError('目标路径不是文件夹。');
    }
  }
  final removedSet = removed.toSet();
  final occupied = <String>{};
  for (final e in current.entries.where((e) => !removedSet.contains(e.path))) {
    if (!e.safe || (!e.directory && !e.canExtract)) {
      throw StateError('含有链接、加密或不安全条目的 ZIP 暂不支持修改。');
    }
    final parts = e.normalized.split('/');
    for (var i = 1; i <= parts.length; i++) {
      occupied.add(parts.take(i).join('/').toLowerCase());
    }
  }
  final names = <String>[];
  for (final source in sources) {
    if (p.equals(p.absolute(source), p.absolute(doc.path))) {
      throw StateError('不能将压缩包加入它自身。');
    }
    final base = p.basename(source);
    final isDirectory = await FileSystemEntity.isDirectory(source);
    var name = base, number = 2;
    String target() => folder.isEmpty ? name : '$folder/$name';
    while (occupied.contains(target().toLowerCase())) {
      final ext = isDirectory ? '' : p.extension(base);
      name = '${base.substring(0, base.length - ext.length)} $number$ext';
      number++;
    }
    names.add(target());
    occupied.add(target().toLowerCase());
  }
  final (paths, targets) = await _scanInputFiles(sources, names);
  if (paths.any((path) => p.equals(p.absolute(path), p.absolute(doc.path)))) {
    throw StateError('传入的文件夹包含当前压缩包，不能将压缩包加入它自身。');
  }
  final inputHashes = <String, String>{};
  for (final path in paths) {
    if (await FileSystemEntity.isFile(path)) {
      inputHashes[path] = await _hashFile(path);
    }
  }
  return _ImportPlan(removed, names, paths, targets, inputHashes);
}

Future<void> _runExtractionBatch(
  String archive,
  List<String> names,
  List<String> outputs,
  List<int> limits,
  int totalLimit,
  SendPort port,
  int shard,
  String encoding,
) => Isolate.run(() {
  final clock = Stopwatch()..start();
  var lastProgress = -100;
  NativeArchive.extractBatchBlocking(
    archive,
    names,
    outputs,
    limits,
    totalLimit: totalLimit,
    encoding: encoding,
    detailedProgress: (done, bytes, index, fileBytes, fileSize) {
      if (clock.elapsedMilliseconds - lastProgress >= 100 ||
          done == names.length) {
        lastProgress = clock.elapsedMilliseconds;
        port.send([shard, done, bytes, index, fileBytes, fileSize]);
      }
    },
  );
}, debugName: 'hizip-extract-$shard');
