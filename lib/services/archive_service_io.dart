import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;

import 'package:crypto/crypto.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:hizip_native/zip_metadata.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/archive_entry.dart';
import '../models/archive_create_options.dart';
import '../models/preview_limit.dart';
import '../models/extraction_progress.dart';
import '../models/archive_index.dart';
import 'archive_worker.dart';
import 'extraction_plan.dart';
import 'extraction_transaction.dart';
import 'archive_volumes.dart';
import 'rar_volumes.dart';

class ArchiveDocument {
  ArchiveDocument(
    this.path,
    this.entries,
    this.format,
    this.writable, {
    ArchiveIndex? index,
    this.encoding = 'auto',
    this.password = '',
    this.comment = '',
    String? nativePath,
    String? resolvedEncoding,
  }) : nativePath = nativePath ?? path,
       resolvedEncoding = resolvedEncoding ?? encoding,
       index = index ?? ArchiveIndex(entries);
  final ArchiveIndex index;
  final String path,
      format,
      encoding,
      resolvedEncoding,
      password,
      comment,
      nativePath;
  bool get supportsComment => format.toUpperCase().startsWith('ZIP');
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
  bool readOnly = false;
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
  Directory? _session;
  Future<Directory>? _creatingSession;
  final List<OpenedArchiveFile> _opened = [];
  final _passwords = <String, String>{};
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
    _passwords.remove(archive);
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
      if (file.readOnly && p.isWithin(directory.path, file.path)) {
        // Unlock only our temporary copies for cleanup, including Windows
        // where the read-only attribute prevents deleting a file.
        await NativeArchive.withControlAddress(0, () async {
          if (!Platform.isWindows && await File(file.path).parent.exists()) {
            await NativeArchive.setReadOnly(p.dirname(file.path), false);
          }
          if (await File(file.path).exists()) {
            await NativeArchive.setReadOnly(file.path, false);
          }
        });
      }
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
  Future<ArchiveDocument> read(String path) async {
    if (RarVolumes.isRarPath(path)) path = await RarVolumes.resolveFirst(path);
    if (ArchiveVolumes.isVolume(path)) {
      final first = ArchiveVolumes.firstPath(path);
      return _cached(first, (cache) async {
        final directory = await cache.createTemp('volumes-');
        try {
          final joined = await ArchiveVolumes.join(first, directory);
          final doc = await _readArchive(
            joined,
            readEncoding,
            password: _passwords[first] ?? '',
            logicalPath: first,
            forceReadOnly: true,
          );
          if (!doc.entries.any((entry) => entry.encrypted)) {
            await NativeArchive.verify(joined, encoding: doc.resolvedEncoding);
          }
          return doc;
        } catch (_) {
          await directory.delete(recursive: true);
          rethrow;
        }
      });
    }
    return _readArchive(
      path,
      readEncoding,
      password: _passwords[path] ?? '',
      forceReadOnly: _opened.any((file) => file.path == path && file.readOnly),
    );
  }

  Future<ArchiveDocument> readWithPassword(String path, String password) async {
    if (RarVolumes.isRarPath(path)) path = await RarVolumes.resolveFirst(path);
    if (ArchiveVolumes.isVolume(path)) {
      final first = ArchiveVolumes.firstPath(path);
      final doc = await read(first);
      await NativeArchive.verify(
        doc.nativePath,
        encoding: doc.resolvedEncoding,
        password: password,
      );
      final unlocked = await _readArchive(
        doc.nativePath,
        readEncoding,
        password: password,
        logicalPath: first,
        forceReadOnly: true,
      );
      _passwords[first] = password;
      return unlocked;
    }
    return _cached(path, (_) async {
      await NativeArchive.verify(
        path,
        encoding: readEncoding,
        password: password,
      );
      final doc = await _readArchive(
        path,
        readEncoding,
        password: password,
        forceReadOnly: _opened.any(
          (file) => file.path == path && file.readOnly,
        ),
      );
      _passwords[path] = password;
      return doc;
    });
  }

  Future<Map<String, dynamic>> capabilities() => NativeArchive.capabilities();

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
        doc.nativePath,
        e.path,
        output,
        limit: limit,
        encoding: doc.resolvedEncoding,
        password: doc.password,
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
        String? preparedPath;
        try {
          _validate(entry);
          final existing = _opened
              .where((f) => f.archive == doc.path && f.entry == entry.path)
              .firstOrNull;
          if (existing != null) return existing;
          final path = await _temporary(doc, entry, cache: cache);
          preparedPath = path;
          if (!doc.writable) {
            await NativeArchive.setReadOnly(path, true);
            if (!Platform.isWindows) {
              await NativeArchive.setReadOnly(p.dirname(path), true);
            }
          }
          final watched =
              OpenedArchiveFile(
                  doc.path,
                  entry.path,
                  path,
                  await _digest(path),
                  await _digest(doc.nativePath),
                  await File(path).stat(),
                )
                ..encoding = doc.resolvedEncoding
                ..readOnly = !doc.writable;
          _opened.add(watched);
          return watched;
        } catch (_) {
          final path = preparedPath;
          if (path != null) {
            await NativeArchive.withControlAddress(0, () async {
              if (!Platform.isWindows && await File(path).parent.exists()) {
                await NativeArchive.setReadOnly(p.dirname(path), false);
              }
              if (await File(path).exists()) {
                await NativeArchive.setReadOnly(path, false);
              }
              if (await File(path).parent.exists()) {
                await File(path).parent.delete(recursive: true);
              }
            });
          }
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
      if (f.readOnly || f.pending || !await File(f.path).exists()) continue;
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
    if (file.readOnly) throw StateError('当前格式仅支持读取。请将文件另存到其他位置。');
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
      await _readArchive(output, 'auto');
      await NativeArchive.verify(output); // Verify headers before committing.
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

  /// Entries that would collide on [destination] because it ignores letter
  /// case. Empty on case-sensitive disks.
  Future<List<ArchiveEntry>> caseConflicts(
    ArchiveDocument doc,
    String destination, {
    ArchiveEntry? entry,
    List<ArchiveEntry>? roots,
  }) async {
    final conflicts = _caseConflictsIn(
      _extractionScope(doc, roots ?? (entry == null ? null : [entry])),
    );
    if (conflicts.isEmpty) return const [];
    if (!await _caseInsensitiveDirectory(Directory(destination))) {
      return const [];
    }
    return conflicts;
  }

  Future<String> extract(
    ArchiveDocument doc,
    String destination, {
    ArchiveEntry? entry,
    List<ArchiveEntry>? roots,
    void Function(int, int)? progress,
    void Function(ExtractionProgress)? detailedProgress,
    LinkPolicy linkPolicy = LinkPolicy.keepAll,
    CaseConflictPolicy caseConflictPolicy = CaseConflictPolicy.rename,
    void Function(String)? notice,
    ExtractionConflictPolicy conflictPolicy = ExtractionConflictPolicy.rename,
    ExtractionConflictResolver? resolveConflict,
  }) async {
    final events = ReceivePort();
    var reported = -1;
    final subscription = events.listen((event) {
      final values = event as List;
      if (values[0] == 'notice') {
        notice?.call(values[1] as String);
        return;
      }
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
    final selection = roots ?? (entry == null ? null : [entry]);
    final insensitive =
        _caseConflictsIn(_extractionScope(doc, selection)).isNotEmpty &&
        await _caseInsensitiveDirectory(Directory(destination));
    final staging = await Directory(destination).createTemp('.hizip-extract-');
    var retainRecovery = false;
    try {
      final snapshot = await _digest(doc.nativePath);
      final result = await _runExtract(
        doc,
        staging.path,
        selection,
        port,
        maxExtractionWorkers,
        linkPolicy,
        caseConflictPolicy,
        insensitive,
      );
      if (reported != result.$2) progress?.call(result.$2, result.$2);
      if (await _digest(doc.nativePath) != snapshot) {
        throw StateError('Archive changed during extraction');
      }
      final placed = await publishExtraction(
        staging,
        destination,
        conflictPolicy,
        resolve: resolveConflict,
      );
      if (result.$1 == staging.path) return destination;
      final actual = placed[result.$1];
      if (actual == null) return destination;
      final root = await Directory(destination).resolveSymbolicLinks();
      return p.join(destination, p.relative(actual, from: root));
    } on ExtractionRecoveryRequired {
      retainRecovery = true;
      rethrow;
    } finally {
      if (!retainRecovery && await staging.exists()) {
        await staging.delete(recursive: true);
      }
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
    List<ArchiveEntry> commentSources = const [],
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
        commentPaths: {
          for (var i = 0; i < commentSources.length; i++)
            commentSources[i].normalized: names[i],
        },
        encoding: doc.resolvedEncoding,
      );
      await _readArchive(output, 'auto');
      await NativeArchive.verify(output);
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
      commentSources: roots,
    );
  }

  Future<Map<String, dynamic>> verify(ArchiveDocument doc) => _cached(
    doc.path,
    (_) => NativeArchive.verify(
      doc.nativePath,
      encoding: doc.resolvedEncoding,
      password: doc.password,
    ),
  );

  Future<ArchiveDocument> writeComment(
    ArchiveDocument doc,
    String comment, {
    required String original,
  }) => _cached(doc.path, (_) async {
    if (!doc.supportsComment || !doc.writable) {
      throw StateError('Archive comments require a writable ZIP archive');
    }
    if (utf8.encode(comment).length > 65535) {
      throw StateError('ZIP comment exceeds 65535 UTF-8 bytes');
    }
    final snapshot = await _digest(doc.path);
    final current = await _readArchive(doc.path, doc.encoding);
    if (current.comment != original) {
      throw StateError('Archive comment changed. Reopen the dialog.');
    }
    final staging = await NativeArchive.stagingDirectory(doc.path);
    final output = p.join(staging.path, p.basename(doc.path));
    try {
      await File(doc.path).copy(output);
      await _runWriteComment(output, comment);
      await NativeArchive.verify(output, encoding: current.resolvedEncoding);
      if (await _digest(doc.path) != snapshot) {
        throw StateError('Archive changed during comment editing');
      }
      await NativeArchive.commit(output, doc.path);
      final hash = await _digest(doc.path);
      for (final opened in _opened.where((file) => file.archive == doc.path)) {
        opened.archiveHash = hash;
      }
      return await _readArchive(doc.path, doc.encoding);
    } finally {
      await staging.delete(recursive: true);
    }
  });

  Future<ArchiveDocument> renameEntry(
    ArchiveDocument doc,
    ArchiveEntry entry,
    String name,
  ) => _cached(doc.path, (cache) async {
    if (!doc.writable) throw StateError('当前格式只支持读取。');
    if (name.trim().isEmpty ||
        name != name.trim() ||
        name.contains('/') ||
        !isSafeArchivePath(name)) {
      throw StateError('请输入有效的名称，不能包含路径分隔符。');
    }
    final parent = p.posix.dirname(entry.normalized);
    final target = parent == '.' ? name : '$parent/$name';
    if (target == entry.normalized) return doc;
    final snapshot = await _digest(doc.path);
    final current = await _readArchive(doc.path, doc.encoding);
    if (!current.index.byNormalized.containsKey(entry.normalized)) {
      throw StateError('所选条目已变化，请重新打开压缩包。');
    }
    for (final item in current.entries) {
      if (item.normalized == entry.normalized ||
          item.normalized.startsWith('${entry.normalized}/')) {
        continue;
      }
      final path = item.normalized.toLowerCase(),
          destination = target.toLowerCase();
      if (path == destination || path.startsWith('$destination/')) {
        throw StateError('目标名称已存在。');
      }
    }
    final staging = await NativeArchive.stagingDirectory(doc.path);
    final output = p.join(staging.path, p.basename(doc.path));
    try {
      await NativeArchive.rename(
        doc.path,
        entry.normalized,
        target,
        output,
        encoding: current.resolvedEncoding,
      );
      final updated = await _readArchive(output, 'auto');
      await NativeArchive.verify(output);
      if (!updated.entries.any(
        (item) =>
            item.normalized == target || item.normalized.startsWith('$target/'),
      )) {
        throw StateError('重命名结果校验失败。');
      }
      if (await _digest(doc.path) != snapshot) {
        throw StateError('压缩包在操作过程中已变化，请重试。');
      }
      await NativeArchive.commit(output, doc.path);
      final hash = await _digest(doc.path);
      for (final opened in _opened.where((file) => file.archive == doc.path)) {
        opened.archiveHash = hash;
        if (opened.entry == entry.path ||
            opened.entry.startsWith('${entry.normalized}/')) {
          _preparing.remove('${doc.path}\u0000${opened.entry}');
          opened.entry =
              '$target${opened.entry.substring(entry.normalized.length)}';
        }
      }
      return await _readArchive(doc.path, doc.encoding);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  });

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
      await NativeArchive.verify(output);
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

  Future<void> create(String output, List<String> files) => createWithOptions(
    output,
    files,
    ArchiveCreateOptions(compressionLevel: compressionLevel),
  );

  Future<void> createWithOptions(
    String output,
    List<String> files,
    ArchiveCreateOptions options,
  ) async {
    if (options.compressionLevel < 0 ||
        options.compressionLevel > 9 ||
        !['store', 'deflate'].contains(options.zipCompression) ||
        !['none', 'aes256'].contains(options.encryption)) {
      throw ArgumentError('Invalid archive options');
    }
    if (options.encrypted &&
        (options.password.isEmpty ||
            !output.toLowerCase().endsWith('.zip') ||
            files.isEmpty)) {
      throw StateError('加密压缩需要 ZIP 格式、密码和至少一个文件。');
    }
    if (!options.encrypted && options.password.isNotEmpty) {
      throw StateError('设置密码时必须启用加密。');
    }
    if (!output.toLowerCase().endsWith('.zip') &&
        options.zipCompression != 'deflate') {
      throw StateError('ZIP 压缩算法仅适用于 ZIP 格式。');
    }
    if (options.volumeSize != 0 &&
        (options.volumeSize < 65536 ||
            !RegExp(r'\.(zip|7z)$', caseSensitive: false).hasMatch(output))) {
      throw ArgumentError(
        'Split volumes require ZIP or 7z and at least 64 KiB per volume',
      );
    }
    if (options.comment.isNotEmpty && !output.toLowerCase().endsWith('.zip')) {
      throw ArgumentError('Archive comments require ZIP format');
    }
    final encoding = createEncoding, level = options.compressionLevel;
    final prefix = options.nestInFolder ? _archiveStem(output) : '';
    if (options.nestInFolder && !isSafeArchivePath(prefix)) {
      throw StateError('不安全的文件名。');
    }
    final names = files
        .map(
          (file) => options.nestInFolder
              ? '$prefix/${p.basename(file)}'
              : p.basename(file),
        )
        .toList();
    if (names.map((s) => s.toLowerCase()).toSet().length != names.length) {
      throw StateError('所选文件存在同名文件，请先重命名。');
    }
    final (paths, targets) = await _inputFiles(files, names);
    if (paths.any((path) => p.equals(p.absolute(path), p.absolute(output)))) {
      throw StateError('不能将压缩包加入它自身。');
    }
    final inputHashes = await _runCaptureInputHashes(paths);
    final originalOutput = await FileSystemEntity.type(
      output,
      followLinks: false,
    );
    if (!options.overwrite && originalOutput != FileSystemEntityType.notFound) {
      throw StateError('目标名称已存在。');
    }
    if (originalOutput != FileSystemEntityType.notFound &&
        originalOutput != FileSystemEntityType.file) {
      throw StateError('Invalid archive output destination');
    }
    final outputHash = originalOutput == FileSystemEntityType.file
        ? await _digest(output)
        : null;
    final dir = await NativeArchive.stagingDirectory(output);
    final staged = p.join(dir.path, p.basename(output));
    var retainRecovery = false;
    try {
      await NativeArchive.create(
        staged,
        paths,
        targets,
        encoding: encoding,
        compressionLevel: level,
        password: options.password,
        encryption: options.encryption,
        zipCompression: options.zipCompression,
      );
      final checked = await _readArchive(
        staged,
        encoding,
        password: options.password,
      );
      if (options.encrypted &&
          !checked.entries.any((entry) => entry.encrypted)) {
        throw StateError('加密压缩需要至少一个普通文件。');
      }
      await NativeArchive.verify(
        staged,
        encoding: encoding,
        password: options.password,
      );
      await _runCheckInputHashes(inputHashes);
      if (options.comment.isNotEmpty) {
        await _runWriteComment(staged, options.comment);
      }
      if (options.volumeSize > 0) {
        await ArchiveVolumes.split(staged, output, dir, options.volumeSize);
      } else if (outputHash == null) {
        await NativeArchive.commitNew(staged, output);
      } else {
        if (await _digest(output) != outputHash) {
          throw StateError('Archive output changed during creation');
        }
        await NativeArchive.commit(staged, output);
      }
      if (options.encrypted) {
        _passwords[options.volumeSize > 0 ? '$output.001' : output] =
            options.password;
      }
    } on ExtractionRecoveryRequired {
      retainRecovery = true;
      rethrow;
    } finally {
      if (!retainRecovery) await dir.delete(recursive: true);
    }
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _passwords.clear();
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
Future<Map<String, String>> _runCaptureInputHashes(List<String> paths) =>
    runArchiveWorker(() async {
      final hashes = <String, String>{};
      for (final path in paths) {
        await NativeArchive.checkpoint();
        if (await FileSystemEntity.isFile(path)) {
          hashes[path] = await _hashFile(path);
        }
      }
      return hashes;
    }, name: 'hizip-input-snapshot');

Future<void> _runWriteComment(String path, String text) => runArchiveWorker(
  () => ZipMetadata.setComment(path, text),
  name: 'hizip-comment',
);

Future<void> _runCheckInputHashes(Map<String, String> hashes) =>
    runArchiveWorker(
      () => _checkInputHashes(hashes),
      name: 'hizip-input-verify',
    );

Future<String> _hashFile(String path) async =>
    (await sha256
            .bind(
              File(path).openRead().asyncMap((bytes) async {
                await NativeArchive.checkpoint();
                return bytes;
              }),
            )
            .first)
        .toString();
Future<ArchiveDocument> _readArchive(
  String path,
  String encoding, {
  String password = '',
  String? logicalPath,
  bool forceReadOnly = false,
}) => runArchiveWorker(
  () => NativeArchive.listBlocking(
    path,
    (j) => ArchiveDocument(
      logicalPath ?? path,
      (j['entries'] as List)
          .map(
            (e) => ArchiveEntry.fromJson(
              e as Map<String, dynamic>,
              unlocked: password.isNotEmpty,
            ),
          )
          .toList(),
      j['format'] as String,
      !forceReadOnly && j['writable'] as bool,
      nativePath: path,
      encoding: encoding,
      password: password,
      resolvedEncoding: j['encoding'] as String?,
      comment: j['comment'] as String? ?? '',
    ),
    encoding: encoding,
    password: password,
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

bool _underRoots(ArchiveEntry e, List<ArchiveEntry>? roots) =>
    roots == null ||
    roots.any(
      (r) =>
          e.path == r.path ||
          (r.directory && e.normalized.startsWith('${r.normalized}/')),
    );

/// Files below [roots] (or all of [doc]) that extraction would write.
List<ArchiveEntry> _extractionScope(
  ArchiveDocument doc,
  List<ArchiveEntry>? roots,
) => doc.entries.where((e) => !e.directory && _underRoots(e, roots)).toList();

/// Archive name without its (possibly compound) extension.
String _archiveStem(String path) {
  final name = p.basename(path);
  final lower = name.toLowerCase();
  for (final ext in const [
    '.tar.gz',
    '.tar.bz2',
    '.tar.xz',
    '.tar.zst',
    '.tar.lz4',
    '.tar.lzip',
    '.tar.lzma',
    '.tar.z',
  ]) {
    if (lower.endsWith(ext)) return name.substring(0, name.length - ext.length);
  }
  final stem = p.basenameWithoutExtension(name);
  return stem.isEmpty ? name : stem;
}

/// [name] or "name 2", "name 3"… so extraction never merges into or
/// overwrites something already in [directory].
String _freeName(String directory, String name, Set<String> taken) {
  final stem = p.posix.basenameWithoutExtension(name);
  final ext = p.posix.extension(name);
  var candidate = name;
  for (
    var n = 2;
    taken.contains(candidate.toLowerCase()) ||
        FileSystemEntity.typeSync(
              p.join(directory, candidate),
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound;
    n++
  ) {
    candidate = '$stem $n$ext';
  }
  taken.add(candidate.toLowerCase());
  return candidate;
}

/// Lets tests exercise the case-insensitive path on any disk.
@visibleForTesting
bool? debugForceCaseInsensitive;

/// Whether [dir] treats names that differ only by case as the same file.
Future<bool> _caseInsensitiveDirectory(Directory dir) async {
  if (debugForceCaseInsensitive != null) return debugForceCaseInsensitive!;
  final probe = File(p.join(dir.path, '.HiZipCase${pid}_${dir.hashCode}'));
  try {
    await probe.writeAsString('');
    return await File(p.join(dir.path, p.basename(probe.path).toLowerCase()))
        .exists();
  } on FileSystemException {
    return false;
  } finally {
    try {
      if (await probe.exists()) await probe.delete();
    } on FileSystemException {
      /* Leave the probe; it is a harmless hidden empty file. */
    }
  }
}

/// Later entries whose path equals an earlier one except for letter case.
List<ArchiveEntry> _caseConflictsIn(List<ArchiveEntry> entries) {
  final first = <String, String>{};
  final result = <ArchiveEntry>[];
  for (final e in entries) {
    final owner = first.putIfAbsent(e.normalized.toLowerCase(), () => e.path);
    if (owner != e.path) result.add(e);
  }
  return result;
}

bool _isSymlink(ArchiveEntry e) => e.isSymlink && e.safe && !e.encrypted;

/// Hard links and special files inside a folder are left out instead of
/// failing the whole extraction.
bool _isSkippableSpecial(ArchiveEntry e) =>
    !e.directory &&
    !e.regular &&
    !e.encrypted &&
    e.safe &&
    e.linkTarget == null;

/// Creates a symlink as the final step, after every regular file is written,
/// so no later entry can be written through a link leaving the destination.
Future<bool> _createLink(String output, String target) async {
  try {
    await Directory(p.dirname(output)).create(recursive: true);
    await Link(output).create(target);
    return true;
  } on FileSystemException catch (error) {
    // Windows without symlink privilege, or a name clash with a real entry.
    if (kDebugMode) {
      debugPrint('[HiZip] symlink not created: "$output" -> "$target": $error');
    }
    return false;
  }
}

void _validate(ArchiveEntry e) {
  if (!e.canExtract || !isSafeArchivePath(e.normalized)) {
    if (kDebugMode) {
      debugPrint(
        '[HiZip] extract rejected: path="${e.path}" '
        'safe=${e.safe} regular=${e.regular} directory=${e.directory} '
        'encrypted=${e.encrypted} size=${e.size} '
        'pathSafe=${isSafeArchivePath(e.normalized)}',
      );
    }
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
  List<ArchiveEntry>? roots,
  SendPort port,
  int? maxWorkers,
  LinkPolicy linkPolicy,
  CaseConflictPolicy caseConflictPolicy,
  bool caseInsensitive,
) => runArchiveWorker(
  () => _extractArchive(
    doc,
    destination,
    roots,
    port,
    maxWorkers,
    linkPolicy,
    caseConflictPolicy,
    caseInsensitive,
  ),
  name: 'hizip-extract',
);

Future<(String, int)> _extractArchive(
  ArchiveDocument doc,
  String destination,
  List<ArchiveEntry>? roots,
  SendPort progress,
  int? maxWorkers,
  LinkPolicy linkPolicy,
  CaseConflictPolicy caseConflictPolicy,
  bool caseInsensitive,
) async {
  final bulk = roots == null || roots.any((r) => r.directory);
  final inScope = _extractionScope(doc, roots);
  var links = inScope
      .where(_isSymlink)
      .where((e) => linkPolicy == LinkPolicy.keepAll || !e.hasUnsafeLink)
      .toList();
  var skippedSpecial = 0;
  var selected = inScope.where((e) {
    if (_isSymlink(e)) return false;
    if (!bulk || !_isSkippableSpecial(e)) return true;
    skippedSpecial++;
    if (kDebugMode) debugPrint('[HiZip] extract skipped special: "${e.path}"');
    return false;
  }).toList();
  if (kDebugMode && links.isNotEmpty) {
    debugPrint('[HiZip] extract will create ${links.length} symlink(s)');
  }
  for (final e in selected) {
    _validate(e);
  }
  for (final e in links) {
    if (!isSafeArchivePath(e.normalized)) {
      throw StateError('不安全的目录路径。');
    }
  }
  // The same path twice is always an error; paths differing only by case
  // collide only on disks that ignore case.
  final exact = <String>{};
  for (final e in [...selected, ...links]) {
    if (!exact.add(e.normalized)) {
      throw StateError('压缩包含有重复的文件路径，无法安全解压。');
    }
  }
  final renamed = <String, String>{};
  var skippedCase = 0;
  if (caseInsensitive && _caseConflictsIn([...selected, ...links]).isNotEmpty) {
    final taken = <String>{};
    final dropped = <String>{};
    for (final e in [...selected, ...links]) {
      var path = e.normalized;
      if (taken.contains(path.toLowerCase())) {
        if (caseConflictPolicy == CaseConflictPolicy.skip) {
          dropped.add(e.path);
          skippedCase++;
          if (kDebugMode) {
            debugPrint('[HiZip] extract skipped case clash: "${e.path}"');
          }
          continue;
        }
        final dir = p.posix.dirname(path);
        final stem = p.posix.basenameWithoutExtension(path);
        final ext = p.posix.extension(path);
        var n = 2;
        do {
          final name = '$stem ($n)$ext';
          path = dir == '.' ? name : '$dir/$name';
          n++;
        } while (taken.contains(path.toLowerCase()) || exact.contains(path));
        renamed[e.path] = path;
        if (kDebugMode) {
          debugPrint(
            '[HiZip] extract renamed case clash: "${e.path}" -> "$path"',
          );
        }
      }
      taken.add(path.toLowerCase());
    }
    selected = selected.where((e) => !dropped.contains(e.path)).toList();
    links = links.where((e) => !dropped.contains(e.path)).toList();
  }
  // Whole archives go in a folder named after the archive; a selection goes
  // straight into the destination without its parent folders.
  final partial = roots != null && roots.isNotEmpty;
  final topNames = <String, String>{};
  if (partial) {
    final used = <String>{};
    for (final r in roots) {
      topNames[r.path] = _freeName(
        destination,
        p.posix.basename(r.normalized),
        used,
      );
    }
  }
  ArchiveEntry? rootOf(String normalized, String path) {
    for (final r in roots ?? const <ArchiveEntry>[]) {
      if (r.path == path ||
          (r.directory && normalized.startsWith('${r.normalized}/'))) {
        return r;
      }
    }
    return null;
  }

  String placed(String normalized, String path, String full) {
    final r = rootOf(normalized, path);
    if (!partial || r == null) return full;
    final top = topNames[r.path]!;
    return r.path == path ? top : '$top${full.substring(r.normalized.length)}';
  }

  String relativeOutput(ArchiveEntry e) =>
      placed(e.normalized, e.path, renamed[e.path] ?? e.normalized);
  var total = 0;
  for (final e in selected) {
    total += e.size < 0 ? 0 : e.size;
  }
  final String rootPath;
  if (partial) {
    rootPath = destination;
  } else {
    rootPath = p.join(
      destination,
      _freeName(destination, _archiveStem(doc.path), <String>{}),
    );
    await Directory(rootPath).create();
  }
  final created = [
    if (partial)
      for (final r in roots) p.join(destination, topNames[r.path]!)
    else
      rootPath,
  ];
  try {
    final outputs = <String>[];
    final parents = <String>{};
    for (final e in selected) {
      final output = p.joinAll([rootPath, ...relativeOutput(e).split('/')]);
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
            doc.nativePath,
            [for (final index in batches[i]) selected[index].path],
            [for (final index in batches[i]) outputs[index]],
            List.filled(batches[i].length, NativeArchive.unlimitedSize),
            NativeArchive.unlimitedSize,
            events.sendPort,
            i,
            doc.resolvedEncoding,
            doc.password,
          ),
      ]);
    } finally {
      await subscription.cancel();
      events.close();
    }
    progress.send([selected.length, selected.length, total, total, '', 0, 0]);
    // Preserve empty folders too.
    for (final e in doc.entries.where(
      (e) => e.directory && _underRoots(e, roots),
    )) {
      if (e.safe && isSafeArchivePath(e.normalized)) {
        await Directory(
          p.joinAll([
            rootPath,
            ...placed(e.normalized, e.path, e.normalized).split('/'),
          ]),
        ).create(recursive: true);
      }
    }
    var failedLinks = 0;
    for (final e in links) {
      final created = await _createLink(
        p.joinAll([rootPath, ...relativeOutput(e).split('/')]),
        e.linkTarget!,
      );
      if (!created) failedLinks++;
    }
    final notes = [
      if (skippedSpecial > 0) '已跳过 $skippedSpecial 个硬链接或特殊文件',
      if (failedLinks > 0) '$failedLinks 个符号链接无法创建',
      if (renamed.isNotEmpty) '已重命名 ${renamed.length} 个仅大小写不同的文件',
      if (skippedCase > 0) '已跳过 $skippedCase 个仅大小写不同的文件',
    ];
    if (notes.isNotEmpty) progress.send(['notice', notes.join('；')]);
    return (
      partial && roots.length == 1 ? created.single : rootPath,
      selected.length + links.length - failedLinks,
    );
  } catch (_) {
    for (final path in created) {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else if (type != FileSystemEntityType.notFound) {
        await File(path).delete();
      }
    }
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
  final deferredLinks = <(String, String)>[];
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
              (e) =>
                  e.normalized.startsWith('${entry.normalized}/') &&
                  !_isSkippableSpecial(e),
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
        } else if (_isSymlink(e)) {
          // A drag cannot ask the user, so links leaving the folder are left out.
          if (!e.hasUnsafeLink) deferredLinks.add((output, e.linkTarget!));
        } else {
          _validate(e);
          await File(output).parent.create(recursive: true);
          NativeArchive.extractBlocking(
            doc.nativePath,
            e.path,
            output,
            encoding: doc.resolvedEncoding,
            password: doc.password,
          );
        }
      }
      paths.add(target);
    }
    for (final (output, target) in deferredLinks) {
      await _createLink(output, target);
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
  String password,
) => runArchiveWorker(() {
  final clock = Stopwatch()..start();
  var lastProgress = -100;
  NativeArchive.extractBatchBlocking(
    archive,
    names,
    outputs,
    limits,
    totalLimit: totalLimit,
    encoding: encoding,
    password: password,
    detailedProgress: (done, bytes, index, fileBytes, fileSize) {
      if (clock.elapsedMilliseconds - lastProgress >= 100 ||
          done == names.length) {
        lastProgress = clock.elapsedMilliseconds;
        port.send([shard, done, bytes, index, fileBytes, fileSize]);
      }
    },
  );
}, name: 'hizip-extract-$shard');
