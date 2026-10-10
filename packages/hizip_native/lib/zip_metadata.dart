import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'hizip_native.dart' show NativeArchive;

/// ZIP metadata is patched without decompressing file data. Raw comment bytes
/// survive edits, including comments written with a legacy character set.
class ZipMetadata {
  ZipMetadata(
    this.comment,
    this.entries,
    this.centralOffset,
    this.centralSize,
    this.endOffset,
    this.zip64Offset,
    this.length,
  );
  final Uint8List comment;
  final List<ZipCommentEntry> entries;
  final int centralOffset, centralSize, endOffset, length;
  final int? zip64Offset;
  String get text {
    try {
      return utf8.decode(comment);
    } on FormatException {
      return latin1.decode(comment);
    }
  }

  static Uint8List _read(RandomAccessFile file, int offset, int size) {
    if (offset < 0 || size < 0 || offset + size > file.lengthSync()) {
      throw const FormatException('Invalid ZIP metadata bounds');
    }
    file.setPositionSync(offset);
    final bytes = file.readSync(size);
    if (bytes.length != size) {
      throw const FormatException('Truncated ZIP metadata');
    }
    return bytes;
  }

  static ZipMetadata? read(String path, {bool parseEntries = true}) {
    final file = File(path).openSync();
    try {
      final length = file.lengthSync();
      if (length < 22) return null;
      final start = length > 65557 ? length - 65557 : 0;
      final tail = _read(file, start, length - start);
      final data = ByteData.sublistView(tail);
      int? end;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (data.getUint32(i, Endian.little) == 0x06054b50 &&
            i + 22 + data.getUint16(i + 20, Endian.little) == tail.length) {
          end = i;
          break;
        }
      }
      if (end == null) return null;
      if (data.getUint16(end + 4, Endian.little) != 0 ||
          data.getUint16(end + 6, Endian.little) != 0) {
        throw const FormatException(
          'PKZIP multi-disk archives are not supported',
        );
      }
      var count = data.getUint16(end + 10, Endian.little);
      if (data.getUint16(end + 8, Endian.little) != count) {
        throw const FormatException('Inconsistent ZIP entry count');
      }
      var size = data.getUint32(end + 12, Endian.little);
      var offset = data.getUint32(end + 16, Endian.little);
      final endOffset = start + end;
      int? zip64;
      if (count == 0xffff || size == 0xffffffff || offset == 0xffffffff) {
        final locator = ByteData.sublistView(_read(file, endOffset - 20, 20));
        if (locator.getUint32(0, Endian.little) != 0x07064b50 ||
            locator.getUint32(4, Endian.little) != 0 ||
            locator.getUint32(16, Endian.little) != 1) {
          throw const FormatException('Invalid ZIP64 locator');
        }
        zip64 = locator.getUint64(8, Endian.little);
        final record = ByteData.sublistView(_read(file, zip64, 56));
        if (record.getUint32(0, Endian.little) != 0x06064b50 ||
            record.getUint64(4, Endian.little) < 44 ||
            record.getUint32(16, Endian.little) != 0 ||
            record.getUint32(20, Endian.little) != 0) {
          throw const FormatException('Invalid ZIP64 directory');
        }
        count = record.getUint64(32, Endian.little);
        if (record.getUint64(24, Endian.little) != count) {
          throw const FormatException('Inconsistent ZIP64 entry count');
        }
        size = record.getUint64(40, Endian.little);
        offset = record.getUint64(48, Endian.little);
      }
      if (offset + size > (zip64 ?? endOffset)) {
        throw const FormatException('Invalid ZIP directory bounds');
      }
      if (!parseEntries) {
        return ZipMetadata(
          Uint8List.sublistView(tail, end + 22),
          [],
          offset,
          size,
          endOffset,
          zip64,
          length,
        );
      }
      final entries = <ZipCommentEntry>[];
      var position = offset;
      for (var i = 0; i < count; i++) {
        NativeArchive.checkpointBlocking();
        final header = _read(file, position, 46);
        final h = ByteData.sublistView(header);
        if (h.getUint32(0, Endian.little) != 0x02014b50 ||
            h.getUint16(34, Endian.little) != 0) {
          throw const FormatException('Invalid ZIP directory entry');
        }
        final nameSize = h.getUint16(28, Endian.little),
            extraSize = h.getUint16(30, Endian.little),
            commentSize = h.getUint16(32, Endian.little);
        final name = _read(file, position + 46, nameSize);
        String? decoded;
        // Unflagged non-ASCII bytes can be a legacy charset even when they
        // happen to form valid UTF-8. Keep raw identity rather than guessing.
        if ((h.getUint16(8, Endian.little) & 0x800) != 0 ||
            name.every((byte) => byte < 0x80)) {
          try {
            decoded = utf8.decode(name);
          } on FormatException {
            /* Preserve raw names without guessing their charset. */
          }
        }
        entries.add(
          ZipCommentEntry(
            header,
            name,
            _read(file, position + 46 + nameSize, extraSize),
            _read(file, position + 46 + nameSize + extraSize, commentSize),
            decoded,
          ),
        );
        position += 46 + nameSize + extraSize + commentSize;
        if (position > offset + size) {
          throw const FormatException('Invalid ZIP directory size');
        }
      }
      if (position != offset + size) {
        throw const FormatException('Unsupported ZIP directory extension');
      }
      return ZipMetadata(
        Uint8List.sublistView(tail, end + 22),
        entries,
        offset,
        size,
        endOffset,
        zip64,
        length,
      );
    } finally {
      file.closeSync();
    }
  }

  static void preserve(
    String source,
    String output, {
    String? renameFrom,
    String? renameTo,
    Map<String, String> copies = const {},
  }) {
    final old = read(source);
    if (old == null ||
        (old.comment.isEmpty && old.entries.every((e) => e.comment.isEmpty))) {
      return;
    }
    final current = read(output);
    if (current == null) {
      throw const FormatException('Cannot preserve ZIP comments');
    }
    final comments = <String, Uint8List>{};
    for (final entry in old.entries.where((e) => e.comment.isNotEmpty)) {
      var name = entry.name;
      if (name != null &&
          renameFrom != null &&
          (name == renameFrom || name.startsWith('$renameFrom/'))) {
        name = '$renameTo${name.substring(renameFrom.length)}';
      }
      final key = name ?? 'raw:${base64.encode(entry.rawName)}';
      if (comments.containsKey(key)) {
        throw const FormatException('Ambiguous ZIP entry comments');
      }
      comments[key] = entry.comment;
      if (name != null) {
        for (final copy in copies.entries) {
          if (name == copy.key || name.startsWith('${copy.key}/')) {
            comments['${copy.value}${name.substring(copy.key.length)}'] =
                entry.comment;
          }
        }
      }
    }
    final used = <String>{};
    final updated = [
      for (final entry in current.entries)
        entry.withComment(
          comments[entry.name ?? 'raw:${base64.encode(entry.rawName)}'] ??
              entry.comment,
        ),
    ];
    for (final entry in current.entries) {
      used.add(entry.name ?? 'raw:${base64.encode(entry.rawName)}');
    }
    // A legacy filename can change encoding on rebuild. Refuse to silently
    // discard its metadata; ordinary deletions are allowed for decoded names.
    if (comments.keys.any(
      (key) => key.startsWith('raw:') && !used.contains(key),
    )) {
      throw const FormatException(
        'Cannot safely preserve legacy ZIP entry comments',
      );
    }
    current._rewrite(output, old.comment, updated);
  }

  static void setComment(String path, String text) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    if (bytes.length > 65535) {
      throw const FormatException('ZIP comment exceeds 65535 UTF-8 bytes');
    }
    final metadata = read(path);
    if (metadata == null) {
      throw const FormatException('Archive comments require ZIP format');
    }
    metadata._rewrite(path, bytes, metadata.entries);
  }

  void _rewrite(
    String path,
    Uint8List archiveComment,
    List<ZipCommentEntry> records,
  ) {
    final directory = File(path).parent.createTempSync('.hizip-metadata-');
    final staged = File('${directory.path}/comments.zip');
    try {
      final input = File(path).openSync();
      final output = staged.openSync(mode: FileMode.write);
      try {
        var remaining = centralOffset;
        while (remaining > 0) {
          NativeArchive.checkpointBlocking();
          final chunk = input.readSync(remaining > 262144 ? 262144 : remaining);
          if (chunk.isEmpty) throw const FormatException('Truncated ZIP');
          output.writeFromSync(chunk);
          remaining -= chunk.length;
        }
        var newSize = 0;
        for (final entry in records) {
          final header = Uint8List.fromList(entry.header);
          ByteData.sublistView(
            header,
          ).setUint16(32, entry.comment.length, Endian.little);
          for (final bytes in [
            header,
            entry.rawName,
            entry.extra,
            entry.comment,
          ]) {
            output.writeFromSync(bytes);
            newSize += bytes.length;
          }
        }
        final suffix = _read(
          input,
          centralOffset + centralSize,
          length - centralOffset - centralSize,
        );
        final data = ByteData.sublistView(suffix);
        final end = endOffset - centralOffset - centralSize;
        if (zip64Offset != null) {
          final record = zip64Offset! - centralOffset - centralSize;
          data.setUint64(record + 40, newSize, Endian.little);
          data.setUint64(
            end - 12,
            centralOffset + newSize + record,
            Endian.little,
          );
        } else if (newSize > 0xffffffff) {
          throw const FormatException('ZIP directory requires ZIP64');
        }
        data.setUint32(
          end + 12,
          newSize > 0xffffffff ? 0xffffffff : newSize,
          Endian.little,
        );
        data.setUint16(end + 20, archiveComment.length, Endian.little);
        output.writeFromSync(Uint8List.sublistView(suffix, 0, end + 22));
        output.writeFromSync(archiveComment);
        output.flushSync();
      } finally {
        input.closeSync();
        output.closeSync();
      }
      // Caller always supplies a private staged file, never a live archive.
      if (Platform.isWindows) File(path).deleteSync();
      staged.renameSync(path);
    } finally {
      directory.deleteSync(recursive: true);
    }
  }
}

class ZipCommentEntry {
  ZipCommentEntry(
    this.header,
    this.rawName,
    this.extra,
    this.comment,
    this.name,
  );
  final Uint8List header, rawName, extra, comment;
  final String? name;
  ZipCommentEntry withComment(Uint8List bytes) =>
      ZipCommentEntry(header, rawName, extra, bytes, name);
}
