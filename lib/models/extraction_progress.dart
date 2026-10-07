class ExtractionProgress {
  const ExtractionProgress({
    required this.completed,
    required this.totalFiles,
    required this.bytes,
    required this.totalBytes,
    required this.currentFile,
    required this.fileBytes,
    required this.fileSize,
  });
  final int completed, totalFiles, bytes, totalBytes, fileBytes, fileSize;
  final String currentFile;
  double? get overall => totalBytes > 0
      ? (bytes / totalBytes).clamp(0, 1)
      : totalBytes < 0
      ? null
      : totalFiles == 0
      ? 1
      : completed / totalFiles;
  double? get current => fileSize < 0
      ? null
      : fileSize == 0
      ? 1
      : (fileBytes / fileSize).clamp(0, 1);
}
