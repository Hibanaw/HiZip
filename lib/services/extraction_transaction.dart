import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hizip_native/hizip_native.dart';
import 'package:path/path.dart' as p;

enum ExtractionConflictPolicy { ask, overwrite, skip, rename }

typedef ExtractionConflictResolver = Future<ExtractionConflictPolicy?> Function(
  String path,
);

class ExtractionRecoveryRequired implements Exception {
  ExtractionRecoveryRequired(this.path, this.cause);
  final String path;
  final Object cause;
  @override
  String toString() => '恢复未完成，备份目录：$path。请保留该目录。';
}

class _Placement {
  _Placement(this.source, this.target, this.type, this.snapshot);
  final String source, target;
  final FileSystemEntityType type;
  final String? snapshot;
  String? publishedSnapshot;
}

/// Plan every conflict before touching the destination. Existing directories
/// merge for overwrite/skip/ask; rename preserves the entire root separately.
/// No archive entry may traverse an existing symbolic-link parent.
Future<Map<String, String>> publishExtraction(
  Directory staging,
  String destination,
  ExtractionConflictPolicy policy, {
  ExtractionConflictResolver? resolve,
  Future<void> Function(String, String) publish = NativeArchive.commitNew,
}) async {
  final root = await Directory(destination).resolveSymbolicLinks();
  final records = <_Placement>[];
  final roots = <String, String>{};
  final reserved = <String>{};
  Future<String?> fingerprint(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    final stat = await FileStat.stat(path);
    if (type == FileSystemEntityType.file) {
      return 'file:${await sha256.bind(File(path).openRead().asyncMap((bytes) async {
        await NativeArchive.checkpoint();
        return bytes;
      })).first}';
    }
    if (type == FileSystemEntityType.link) {
      return 'link:${await Link(path).target()}';
    }
    if (type == FileSystemEntityType.directory) {
      final children = await Directory(path).list(followLinks: false).toList();
      children.sort((a, b) => a.path.compareTo(b.path));
      final signatures = <String>[];
      for (final child in children) {
        await NativeArchive.checkpoint();
        signatures.add(
          '${p.basename(child.path)}:${await fingerprint(child.path)}',
        );
      }
      return 'directory:${sha256.convert(utf8.encode(jsonEncode(signatures)))}';
    }
    return '$type:${stat.size}';
  }

  Future<void> safeParents(String path) async {
    var parent = p.dirname(path);
    while (parent != root) {
      if (!p.isWithin(root, parent)) {
        throw StateError('Unsafe extraction destination');
      }
      final type = await FileSystemEntity.type(parent, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw StateError(
          'Extraction destination contains a symbolic link or non-directory parent',
        );
      }
      parent = p.dirname(parent);
    }
  }

  Future<String> freeName(String path) async {
    final stem = p.basenameWithoutExtension(path),
        extension = p.extension(path);
    var candidate = path, n = 2;
    while (reserved.contains(candidate.toLowerCase()) ||
        await FileSystemEntity.type(candidate, followLinks: false) !=
            FileSystemEntityType.notFound) {
      candidate = p.join(p.dirname(path), '$stem $n$extension');
      n++;
    }
    return candidate;
  }

  Future<String?> plan(String source, String target) async {
    await NativeArchive.checkpoint();
    await safeParents(target);
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    final existing = await FileSystemEntity.type(target, followLinks: false);
    var choice = policy;
    if (existing == FileSystemEntityType.directory &&
        sourceType == FileSystemEntityType.directory &&
        choice != ExtractionConflictPolicy.rename) {
      await for (final child in Directory(source).list(followLinks: false)) {
        await plan(child.path, p.join(target, p.basename(child.path)));
      }
      return target;
    }
    if (existing != FileSystemEntityType.notFound) {
      if (choice == ExtractionConflictPolicy.ask) {
        choice =
            await resolve?.call(target) ??
            (throw const ArchiveOperationCancelled());
        if (choice == ExtractionConflictPolicy.ask) {
          throw StateError('Invalid extraction conflict decision');
        }
      }
      if (choice == ExtractionConflictPolicy.skip) return null;
      if (choice == ExtractionConflictPolicy.rename) {
        target = await freeName(target);
      }
    }
    if (!reserved.add(target.toLowerCase())) {
      throw StateError('Duplicate extraction destination');
    }
    records.add(
      _Placement(source, target, sourceType, await fingerprint(target)),
    );
    return target;
  }

  final children = await staging.list(followLinks: false).toList();
  children.sort((a, b) => a.path.compareTo(b.path));
  for (final child in children) {
    final target = await plan(child.path, p.join(root, p.basename(child.path)));
    if (target != null) roots[child.path] = target;
  }
  for (final record in records) {
    await safeParents(record.target);
    if (await fingerprint(record.target) != record.snapshot) {
      throw StateError('Extraction destination changed. Try again.');
    }
  }
  await NativeArchive.checkpoint();
  NativeArchive.beginCommit();
  final backup = await staging.createTemp('recovery-');
  final moved = <_Placement>[], saved = <String, String>{};
  // This journal and the backup remain available if rollback cannot complete.
  final journal = File(p.join(backup.path, 'journal.json'));
  Future<void> saveJournal() => journal.writeAsString(
    jsonEncode({
      'destination': root,
      'created': moved.map((r) => r.target).toList(),
      'backups': saved,
      'directories': <String>[],
    }),
    flush: true,
  );
  Future<void> rename(
    String source,
    String target,
    FileSystemEntityType type,
  ) async {
    if (type == FileSystemEntityType.directory) {
      await Directory(source).rename(target);
    } else if (type == FileSystemEntityType.link) {
      await Link(source).rename(target);
    } else {
      await File(source).rename(target);
    }
  }

  try {
    for (final record in records) {
      await safeParents(record.target);
      if (await fingerprint(record.target) != record.snapshot) {
        throw StateError('Extraction destination changed. Try again.');
      }
      if (record.snapshot != null) {
        final path = p.join(backup.path, 'item-${saved.length}');
        saved[record.target] = path;
        await saveJournal();
        await rename(
          record.target,
          path,
          await FileSystemEntity.type(record.target, followLinks: false),
        );
      }
      // Journal intent before the rename, making recovery possible after a crash.
      moved.add(record);
      await saveJournal();
      record.publishedSnapshot = await fingerprint(record.source);
      await publish(record.source, record.target);
    }
    return roots;
  } catch (error) {
    try {
      for (final record in moved.reversed) {
        // A failed rename leaves its source in place; never delete a new file
        // created by another process in that case.
        if (await FileSystemEntity.type(record.source, followLinks: false) !=
            FileSystemEntityType.notFound) {
          continue;
        }
        if (await fingerprint(record.target) != record.publishedSnapshot) {
          throw StateError(
            'Published extraction files changed; recovery requires review',
          );
        }
        final type = await FileSystemEntity.type(
          record.target,
          followLinks: false,
        );
        if (type == FileSystemEntityType.directory) {
          await Directory(record.target).delete(recursive: true);
        } else if (type == FileSystemEntityType.link) {
          await Link(record.target).delete();
        } else if (type == FileSystemEntityType.file) {
          await File(record.target).delete();
        }
      }
      for (final item in saved.entries.toList().reversed) {
        final type = await FileSystemEntity.type(
          item.value,
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound) {
          if (await FileSystemEntity.type(item.key, followLinks: false) !=
              FileSystemEntityType.notFound) {
            throw StateError('Recovery destination occupied');
          }
          await rename(item.value, item.key, type);
        }
      }
    } catch (rollback) {
      throw ExtractionRecoveryRequired(staging.path, rollback);
    }
    rethrow;
  }
}
