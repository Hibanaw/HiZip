import 'dart:io';

import 'package:path/path.dart' as p;

/// RAR volumes retain their own headers; the native decoder opens each volume.
/// They must never pass through the ZIP/7z byte-concatenation path.
class RarVolumes {
  static final _parts = RegExp(
    r'^(.*\.part)(\d+)(\.rar)$',
    caseSensitive: false,
  );
  static final _old = RegExp(r'^(.*)\.([r-z]\d{2})$', caseSensitive: false);

  static bool isRarPath(String path) =>
      path.toLowerCase().endsWith('.rar') || _old.hasMatch(p.basename(path));

  static String firstPath(String path) {
    final name = p.basename(path);
    final parts = _parts.firstMatch(name);
    if (parts != null) {
      final index = int.tryParse(parts[2]!);
      if (index == null || index < 1) {
        throw StateError('Invalid RAR volume number');
      }
      return p.join(
        p.dirname(path),
        '${parts[1]}${'1'.padLeft(parts[2]!.length, '0')}${parts[3]}',
      );
    }
    final old = _old.firstMatch(name);
    if (old != null) {
      final extension = old[2]![0] == old[2]![0].toUpperCase() ? 'RAR' : 'rar';
      return p.join(p.dirname(path), '${old[1]}.$extension');
    }
    return path;
  }

  static Future<String> resolveFirst(String path) async {
    final first = firstPath(path);
    if (await File(first).exists()) return first;
    // Case-sensitive disks may hold foo.rar alongside foo.R00.
    final expected = p.basename(first).toLowerCase();
    final matches = <String>[];
    await for (final entry in Directory(
      p.dirname(first),
    ).list(followLinks: false)) {
      if (entry is File && p.basename(entry.path).toLowerCase() == expected) {
        matches.add(entry.path);
      }
    }
    if (matches.length == 1) return matches.single;
    throw StateError('First RAR volume is missing or ambiguous: $first');
  }
}
