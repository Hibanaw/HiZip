import 'dart:typed_data';

import '../models/archive_entry.dart';
import '../models/extraction_progress.dart';
import 'archive_service.dart';
import 'archive_task_queue.dart';

/// Serialize every archive access, including previews and background exports.
class QueuedArchiveService extends ArchiveService {
  QueuedArchiveService(this.delegate, this.queue)
    : super(temporaryRoot: delegate.temporaryRoot);
  final ArchiveService delegate;
  final ArchiveTaskQueue queue;
  Future<void>? _disposing;
  @override
  int? get maxExtractionWorkers => delegate.maxExtractionWorkers;
  @override
  set maxExtractionWorkers(int? value) => delegate.maxExtractionWorkers = value;
  @override
  bool get supported => delegate.supported;
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
    return queue.run(path, '正在读取压缩包', () {
      delegate.readEncoding = encoding;
      return delegate.read(path);
    });
  }

  @override
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) =>
      queue.run(doc.path, '正在生成预览', () => delegate.preview(doc, entry));
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
  }) => queue.run(
    doc.path,
    '正在解压',
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
    ),
  );
  @override
  Future<OpenedArchiveFile> prepareExternal(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) =>
      queue.run(doc.path, '正在准备文件', () => delegate.prepareExternal(doc, entry));
  @override
  Future<OpenedArchiveFile> open(ArchiveDocument doc, ArchiveEntry entry) =>
      queue.run(doc.path, '正在打开文件', () => delegate.open(doc, entry));
  @override
  Future<List<String>> exportEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) =>
      queue.run(doc.path, '正在准备导出', () => delegate.exportEntries(doc, entries));
  @override
  Future<ArchiveDocument> importFiles(
    ArchiveDocument doc,
    List<String> sources,
    String folder, {
    List<ArchiveEntry> moving = const [],
    String? expectedArchiveHash,
  }) => queue.run(
    doc.path,
    '正在导入文件',
    () => delegate.importFiles(
      doc,
      sources,
      folder,
      moving: moving,
      expectedArchiveHash: expectedArchiveHash,
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
    () => delegate.transferEntries(doc, entries, folder, move: move),
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
    () => delegate.createEntry(doc, folder, name, directory: directory),
  );
  @override
  Future<ArchiveDocument> deleteEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) =>
      queue.run(doc.path, '正在删除项目', () => delegate.deleteEntries(doc, entries));
  @override
  Future<void> save(OpenedArchiveFile file) =>
      queue.run(file.archive, '正在保存回压缩包', () => delegate.save(file));
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
    return queue.run(output, '正在创建压缩包', () {
      delegate.createEncoding = encoding;
      delegate.compressionLevel = level;
      return delegate.create(output, files);
    });
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
