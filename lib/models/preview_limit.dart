/// A preview fallback, not a failed open/extract operation.
class PreviewLimitExceeded implements Exception {
  const PreviewLimitExceeded();

  @override
  String toString() => '文件超过预览限制，请打开文件查看完整内容。';
}
