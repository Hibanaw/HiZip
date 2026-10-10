import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:hizip_native/hizip_native.dart';

import '../models/archive_entry.dart';
import '../models/archive_create_options.dart';
import '../models/extraction_progress.dart';
import 'archive_service.dart';
import 'archive_task_queue.dart';
import 'archive_volumes.dart';
import 'rar_volumes.dart';

typedef FileAccessAuthorization = Future<bool> Function({
  required List<String> readPaths,
  required List<String> writeDirectories,
});

/// Serialize every archive access, including previews and background exports.
class QueuedArchiveService extends ArchiveService {
  QueuedArchiveService(this.delegate, this.queue, {this.authorize})
    : super(temporaryRoot: delegate.temporaryRoot);
  final ArchiveService delegate;
  final ArchiveTaskQueue queue;
  final FileAccessAuthorization? authorize;
  Future<T> _access<T>(
    Future<T> Function() work, {
    List<String> reads = const [],
    List<String> writes = const [],
  }) async {
    if (authorize != null &&
        !await authorize!(readPaths: reads, writeDirectories: writes)) {
      throw const ArchiveTaskCancelled();
    }
    await NativeArchive.checkpoint();
    return work();
  }

  List<String> _readPaths(String path) => [
    ArchiveVolumes.isVolume(path) || RarVolumes.isRarPath(path)
        ? p.dirname(path)
        : path,
  ];
  Future<void>? _disposing;
  @override
  int? get maxExtractionWorkers => delegate.maxExtractionWorkers;
  @override
  set maxExtractionWorkers(int? value) => delegate.maxExtractionWorkers = value;
  @override
  String get readEncoding => delegate.readEncoding;
  @override
  set readEncoding(String value) => delegate.readEncoding = value;
  @override
  String get createEncoding => delegate.createEncoding;
  @override
  set createEncoding(String value) => delegate.createEncoding = value;
  @override
  int get compressionLevel => delegate.compressionLevel;
  @override
  set compressionLevel(int value) => delegate.compressionLevel = value;

  @override
  Future<ArchiveDocument> read(String path) {
    final encoding = readEncoding;
    return queue.run(
      path,
      '正在读取压缩包',
      () => _access(() {
        delegate.readEncoding = encoding;
        return delegate.read(path);
      }, reads: _readPaths(path)),
    );
  }

  @override
  Future<ArchiveDocument> readWithPassword(String path, String password) {
    final encoding = readEncoding;
    return queue.run(
      path,
      '正在解锁压缩包',
      () => _access(() {
        delegate.readEncoding = encoding;
        return delegate.readWithPassword(path, password);
      }, reads: _readPaths(path)),
    );
  }

  @override
  Future<Map<String, dynamic>> capabilities() => delegate.capabilities();
  @override
  Future<void> createWithOptions(
    String output,
    List<String> files,
    ArchiveCreateOptions options,
  ) {
    final encoding = createEncoding;
    return queue.run(
      output,
      '正在创建压缩包',
      () => _access(
        () {
          delegate.createEncoding = encoding;
          return delegate.createWithOptions(output, files, options);
        },
        reads: files,
        writes: [p.dirname(output)],
      ),
    );
  }

  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) =>
      queue.run(
        doc.path,
        '正在生成预览',
        () => _access(
          () => delegate.preview(doc, entry),
          reads: _readPaths(doc.nativePath),
        ),
      );
  @override
  Future<List<ArchiveEntry>> caseConflicts(
    ArchiveDocument doc,
    String destination, {
    ArchiveEntry? entry,
    List<ArchiveEntry>? roots,
  }) => queue.run(
    doc.path,
    '正在检查文件名',
    () => _access(
      () =>
          delegate.caseConflicts(doc, destination, entry: entry, roots: roots),
      writes: [destination],
    ),
  );
  @override
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
  }) => queue.run(
    doc.path,
    '正在解压',
    () => _access(
      () => delegate.extract(
        doc,
        destination,
        entry: entry,
        roots: roots,
        progress: progress,
        detailedProgress: detailedProgress,
        linkPolicy: linkPolicy,
        caseConflictPolicy: caseConflictPolicy,
        notice: notice,
        conflictPolicy: conflictPolicy,
        resolveConflict: resolveConflict,
      ),
      reads: _readPaths(doc.nativePath),
      writes: [destination],
    ),
  );
  @override
  Future<OpenedArchiveFile> prepareExternal(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) => queue.run(
    doc.path,
    '正在准备文件',
    () => _access(
      () => delegate.prepareExternal(doc, entry),
      reads: _readPaths(doc.nativePath),
    ),
  );
  @override
  Future<OpenedArchiveFile> open(ArchiveDocument doc, ArchiveEntry entry) =>
      queue.run(
        doc.path,
        '正在打开文件',
        () => _access(
          () => delegate.open(doc, entry),
          reads: _readPaths(doc.nativePath),
        ),
      );
  @override
  Future<List<String>> exportEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) => queue.run(
    doc.path,
    '正在准备导出',
    () => _access(
      () => delegate.exportEntries(doc, entries),
      reads: _readPaths(doc.nativePath),
    ),
  );
  @override
  Future<ArchiveDocument> importFiles(
    ArchiveDocument doc,
    List<String> sources,
    String folder, {
    List<ArchiveEntry> moving = const [],
    String? expectedArchiveHash,
    List<ArchiveEntry> commentSources = const [],
  }) => queue.run(
    doc.path,
    '正在导入文件',
    () => _access(
      () => delegate.importFiles(
        doc,
        sources,
        folder,
        moving: moving,
        expectedArchiveHash: expectedArchiveHash,
        commentSources: commentSources,
      ),
      reads: sources,
      writes: [p.dirname(doc.path)],
    ),
  );
  @override
  Future<ArchiveDocument> transferEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
    String folder, {
    bool move = false,
  }) => queue.run(
    doc.path,
    '正在传输文件',
    () => _access(
      () => delegate.transferEntries(doc, entries, folder, move: move),
      writes: [p.dirname(doc.path)],
    ),
  );
  @override
  Future<Map<String, dynamic>> verify(ArchiveDocument doc) => queue.run(
    doc.path,
    '正在测试压缩包',
    () =>
        _access(() => delegate.verify(doc), reads: _readPaths(doc.nativePath)),
  );
  @override
  Future<ArchiveDocument> writeComment(
    ArchiveDocument doc,
    String comment, {
    required String original,
  }) => queue.run(
    doc.path,
    '正在保存注释',
    () => _access(
      () => delegate.writeComment(doc, comment, original: original),
      writes: [p.dirname(doc.path)],
    ),
  );
  @override
  Future<ArchiveDocument> renameEntry(
    ArchiveDocument doc,
    ArchiveEntry entry,
    String name,
  ) => queue.run(
    doc.path,
    '正在重命名',
    () => _access(
      () => delegate.renameEntry(doc, entry, name),
      writes: [p.dirname(doc.path)],
    ),
  );
  @override
  Future<ArchiveDocument> createEntry(
    ArchiveDocument doc,
    String folder,
    String name, {
    bool directory = false,
  }) => queue.run(
    doc.path,
    '正在创建项目',
    () => _access(
      () => delegate.createEntry(doc, folder, name, directory: directory),
      writes: [p.dirname(doc.path)],
    ),
  );
  @override
  Future<ArchiveDocument> deleteEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) => queue.run(
    doc.path,
    '正在删除项目',
    () => _access(
      () => delegate.deleteEntries(doc, entries),
      writes: [p.dirname(doc.path)],
    ),
  );
  @override
  Future<void> save(OpenedArchiveFile file) => queue.run(
    file.archive,
    '正在保存回压缩包',
    () => _access(() => delegate.save(file), writes: [p.dirname(file.archive)]),
  );
  @override
  Future<void> acknowledge(OpenedArchiveFile file) =>
      queue.run(file.archive, '正在确认修改', () => delegate.acknowledge(file));
  @override
  Future<void> retain(OpenedArchiveFile file) =>
      queue.run(file.archive, '正在保留临时文件', () => delegate.retain(file));
  @override
  Future<void> discard(OpenedArchiveFile file) =>
      queue.run(file.archive, '正在放弃修改', () => delegate.discard(file));
  @override
  Future<void> closeArchive(String archive) =>
      queue.run(archive, '正在关闭压缩包', () => delegate.closeArchive(archive));
  @override
  Future<void> create(String output, List<String> files) {
    final encoding = createEncoding, level = compressionLevel;
    return queue.run(
      output,
      '正在创建压缩包',
      () => _access(
        () {
          delegate.createEncoding = encoding;
          delegate.compressionLevel = level;
          return delegate.create(output, files);
        },
        reads: files,
        writes: [p.dirname(output)],
      ),
    );
  }

  @override
  Future<List<OpenedArchiveFile>> changes() => delegate.changes();
  @override
  Future<void> retainClipboardExports(List<String> paths) =>
      delegate.retainClipboardExports(paths);
  @override
  Future<void> updateClipboardExports(List<String> current) =>
      delegate.updateClipboardExports(current);
  @override
  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    await queue.stop();
    await delegate.dispose();
    queue.dispose();
  }
}
