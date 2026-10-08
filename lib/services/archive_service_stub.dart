import 'dart:typed_data';

import '../models/extraction_progress.dart';

import '../models/archive_entry.dart';
import '../models/archive_index.dart';

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
  final String entry, archive, path;
  String hash, archiveHash;
  Object stat;
  bool pending = false;
}

class ArchiveService {
  ArchiveService({this.temporaryRoot, this.maxExtractionWorkers});

  /// Optional cap for benchmarks and low-resource hosts; auto defaults to four.
  int? maxExtractionWorkers;
  String readEncoding = 'auto', createEncoding = 'UTF-8';
  int compressionLevel = 6;
  final String? temporaryRoot;
  bool get supported => false;
  Future<ArchiveDocument> read(String path) async =>
      throw UnsupportedError('Web requires a WebAssembly archive backend');
  Future<Uint8List> preview(ArchiveDocument doc, ArchiveEntry entry) async =>
      throw UnsupportedError('Web preview unavailable');
  Future<List<ArchiveEntry>> caseConflicts(
    ArchiveDocument doc,
    String destination, {
    ArchiveEntry? entry,
    List<ArchiveEntry>? roots,
  }) async => const [];

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
  }) async => throw UnsupportedError('Web extraction unavailable');
  Future<OpenedArchiveFile> prepareExternal(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) async => throw UnsupportedError('Web unavailable');
  Future<OpenedArchiveFile> open(
    ArchiveDocument doc,
    ArchiveEntry entry,
  ) async => throw UnsupportedError('Web unavailable');
  Future<List<OpenedArchiveFile>> changes() async => [];
  Future<void> save(OpenedArchiveFile file) async {}
  Future<void> acknowledge(OpenedArchiveFile file) async {}
  Future<void> create(String output, List<String> files) async =>
      throw UnsupportedError('Web unavailable');
  Future<List<String>> exportEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) async => throw UnsupportedError('Web unavailable');
  Future<ArchiveDocument> importFiles(
    ArchiveDocument doc,
    List<String> sources,
    String folder, {
    List<ArchiveEntry> moving = const [],
    String? expectedArchiveHash,
  }) async => throw UnsupportedError('Web unavailable');
  Future<ArchiveDocument> transferEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
    String folder, {
    bool move = false,
  }) async => throw UnsupportedError('Web unavailable');
  Future<void> retainClipboardExports(List<String> paths) async {}
  Future<ArchiveDocument> createEntry(
    ArchiveDocument doc,
    String folder,
    String name, {
    bool directory = false,
  }) async => throw UnsupportedError('Web unavailable');
  Future<ArchiveDocument> deleteEntries(
    ArchiveDocument doc,
    List<ArchiveEntry> entries,
  ) async => throw UnsupportedError('Web unavailable');
  Future<void> updateClipboardExports(List<String> current) async {}
  Future<void> closeArchive(String archive) async {}
  Future<void> retain(OpenedArchiveFile file) async {}
  Future<void> discard(OpenedArchiveFile file) async {}
  Future<void> dispose() async {}
}
