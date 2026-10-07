import 'dart:convert';
import 'dart:typed_data';

/// Decode away from the UI and bound paragraph/layout work for huge text files.
String decodePreviewText(Uint8List bytes) {
  const byteLimit = 64 * 1024, lineLimit = 1000;
  var truncated = bytes.length > byteLimit;
  final text = utf8.decode(
    bytes.length > byteLimit
        ? Uint8List.sublistView(bytes, 0, byteLimit)
        : bytes,
    allowMalformed: true,
  );
  final lines = text.split('\n');
  if (lines.length > lineLimit) truncated = true;
  final visible = lines
      .take(lineLimit)
      .map((line) {
        if (line.length <= 2000) return line;
        truncated = true;
        return '${line.substring(0, 2000)}…';
      })
      .join('\n');
  return truncated ? '$visible\n\n…预览已截断，请打开文件查看完整内容。' : visible;
}
