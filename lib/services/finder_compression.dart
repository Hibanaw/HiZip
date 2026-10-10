import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/archive_create_options.dart';
import 'archive_service.dart';

Future<String> finderArchiveStem(List<String> paths) async {
  if (paths.isEmpty) throw ArgumentError('Empty Finder selection');
  final first = paths.first;
  final name = paths.length == 1
      ? await FileSystemEntity.type(first, followLinks: false) ==
                FileSystemEntityType.directory
            ? p.basename(first)
            : p.basenameWithoutExtension(first)
      : p.basename(p.dirname(first));
  return name.isEmpty || name == p.separator || name == '.' ? 'Archive' : name;
}

Future<String> availableFinderArchivePath(
  List<String> paths,
  String format,
) async {
  final stem = await finderArchiveStem(paths);
  final directory = p.dirname(paths.first);
  var candidate = p.join(directory, '$stem.$format');
  for (
    var suffix = 2;
    await FileSystemEntity.type(candidate, followLinks: false) !=
        FileSystemEntityType.notFound;
    suffix++
  ) {
    candidate = p.join(directory, '$stem ($suffix).$format');
  }
  return candidate;
}

Future<String> createFinderQuickZip(
  ArchiveService service,
  List<String> paths, {
  String? output,
}) async {
  output ??= await availableFinderArchivePath(paths, 'zip');
  // A destination that appears after the name check must never be replaced.
  await service.createWithOptions(
    output,
    paths,
    const ArchiveCreateOptions(overwrite: false),
  );
  return output;
}
