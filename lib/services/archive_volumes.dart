import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:hizip_native/zip_metadata.dart';

import 'extraction_transaction.dart' show ExtractionRecoveryRequired;

import 'package:path/path.dart' as p;

/// Continuous byte-split volumes only. PKZIP .z01 and RAR volume layouts are
/// different formats and are never treated as raw concatenation.
class ArchiveVolumes {
  static bool isVolume(String path) =>
      RegExp(r'\.(zip|7z)\.\d{3,}$', caseSensitive: false).hasMatch(path);
  static String firstPath(String path) =>
      path.replaceFirst(RegExp(r'\.\d{3,}$'), '.001');
  static Future<String> join(String path, Directory cache) async {
    final first = firstPath(path), base = first.substring(0, first.length - 4);
    final folder = Directory(p.dirname(first));
    final pattern = RegExp('^${RegExp.escape(p.basename(base))}\\.(\\d{3,})\$');
    final parts = <int, File>{};
    await for (final entry in folder.list(followLinks: false)) {
      final match = pattern.firstMatch(p.basename(entry.path));
      if (match == null) continue;
      final index = int.parse(match[1]!);
      if (index < 1 || entry is! File || parts.containsKey(index)) {
        throw StateError('Invalid or ambiguous archive volume');
      }
      parts[index] = entry;
    }
    if (parts.isEmpty || !parts.containsKey(1)) {
      throw StateError('First archive volume is missing');
    }
    final manifestFile = File('$base.hizip-volumes.json');
    List<dynamic>? manifest;
    if (await manifestFile.exists()) {
      final stat = await manifestFile.stat();
      if (stat.size > 16 * 1024 * 1024) {
        throw StateError('Archive volume manifest is too large');
      }
      final decoded =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      if (decoded['version'] != 1 || decoded['parts'] is! List) {
        throw StateError('Invalid archive volume manifest');
      }
      manifest = decoded['parts'] as List;
      if (manifest.length != parts.length) {
        throw StateError(
          'Archive volume set is incomplete or contains unexpected parts',
        );
      }
    }
    final count = parts.keys.reduce((a, b) => a > b ? a : b);
    if (count != parts.length) throw StateError('Archive volume is missing');
    final output = File(p.join(cache.path, p.basename(base)));
    final sink = await output.open(mode: FileMode.write);
    try {
      for (var index = 1; index <= count; index++) {
        final file = parts[index]!, before = await parts[index]!.stat();
        // Hash exactly the bytes being joined, not a second read that could
        // observe a different file. Await writes to bound buffering per block.
        final digest = await sha256
            .bind(
              file.openRead().asyncMap((bytes) async {
                await NativeArchive.checkpoint();
                await sink.writeFrom(bytes);
                return bytes;
              }),
            )
            .first;
        await sink.flush();
        final after = await file.stat();
        if (before.size != after.size || before.modified != after.modified) {
          throw StateError('Archive volume changed while opening');
        }
        if (manifest != null) {
          final expected = manifest[index - 1] as Map<String, dynamic>;
          if (expected['name'] != p.basename(file.path) ||
              expected['size'] != after.size ||
              expected['sha256'] != digest.toString()) {
            throw StateError('Archive volume checksum mismatch');
          }
        }
      }
      await sink.close();
      if (base.toLowerCase().endsWith('.zip') &&
          ZipMetadata.read(output.path, parseEntries: false) == null) {
        throw StateError(
          'Archive volume set is truncated or missing its final part',
        );
      }
      return output.path;
    } catch (_) {
      await sink.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  static Future<List<String>> split(
    String source,
    String output,
    Directory staging,
    int volumeSize,
  ) async {
    if (volumeSize < 65536) {
      throw ArgumentError('Volume size must be at least 64 KiB');
    }
    final input = await File(source).open();
    final files = <String>[], manifest = <Map<String, Object>>[];
    try {
      var remaining = await input.length(), index = 1;
      while (remaining > 0) {
        final name =
            '${p.basename(output)}.${index.toString().padLeft(3, '0')}';
        final part = File(p.join(staging.path, name));
        final handle = await part.open(mode: FileMode.write);
        var size = remaining < volumeSize ? remaining : volumeSize;
        final partSize = size;
        try {
          while (size > 0) {
            await NativeArchive.checkpoint();
            final bytes = await input.read(size > 262144 ? 262144 : size);
            if (bytes.isEmpty) {
              throw StateError('Source archive truncated during splitting');
            }
            await handle.writeFrom(bytes);
            size -= bytes.length;
            remaining -= bytes.length;
          }
          await handle.flush();
        } finally {
          await handle.close();
        }
        files.add(part.path);
        manifest.add({
          'name': name,
          'size': partSize,
          'sha256': (await sha256.bind(_controlledRead(part)).first).toString(),
        });
        index++;
      }
    } finally {
      await input.close();
    }
    final indexFile = File(
      p.join(staging.path, '${p.basename(output)}.hizip-volumes.json'),
    );
    final indexText = jsonEncode({'version': 1, 'parts': manifest});
    if (utf8.encode(indexText).length > 16 * 1024 * 1024) {
      throw StateError('Archive volume manifest is too large');
    }
    await indexFile.writeAsString(indexText, flush: true);
    files.add(indexFile.path);
    final destinations = files
        .map((file) => p.join(p.dirname(output), p.basename(file)))
        .toList();
    // Never replace an existing set of volumes or its manifest.
    for (final file in destinations) {
      if (await FileSystemEntity.type(file, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Archive volume destination already exists');
      }
    }
    final expectedHashes = <String, String>{};
    for (var i = 0; i < files.length; i++) {
      await NativeArchive.checkpoint();
      expectedHashes[destinations[i]] =
          (await sha256.bind(_controlledRead(File(files[i]))).first).toString();
    }
    await NativeArchive.checkpoint();
    NativeArchive.beginCommit();
    final created = <String>[];
    // Publish the manifest first: a crash leaves a detectable incomplete set,
    // rather than a truncated first volume that appears to stand alone.
    final order = [
      files.length - 1,
      for (var i = 0; i < files.length - 1; i++) i,
    ];
    try {
      for (final i in order) {
        await NativeArchive.commitNew(files[i], destinations[i]);
        created.add(destinations[i]);
      }
    } catch (_) {
      try {
        for (final file in created.reversed) {
          final type = await FileSystemEntity.type(file, followLinks: false);
          if (type == FileSystemEntityType.notFound) continue;
          if (type != FileSystemEntityType.file ||
              (await sha256.bind(File(file).openRead()).first).toString() !=
                  expectedHashes[file]) {
            throw StateError(
              'Published archive volume changed; recovery requires review',
            );
          }
          await File(file).delete();
        }
      } catch (rollback) {
        throw ExtractionRecoveryRequired(staging.path, rollback);
      }
      rethrow;
    }
    return destinations.take(destinations.length - 1).toList();
  }
}

Stream<List<int>> _controlledRead(File file) async* {
  await for (final bytes in file.openRead()) {
    await NativeArchive.checkpoint();
    yield bytes;
  }
}
