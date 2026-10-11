import 'dart:collection';
import 'dart:math' as math;

import 'archive_entry.dart';

class DirectoryListing extends ListBase<ArchiveEntry> {
  DirectoryListing(this.entries, {this.expanded = false});

  static const collapsedCount = 1000;
  final List<ArchiveEntry> entries;
  final bool expanded;

  int get remainingCount => entries.length - length;

  @override
  int get length =>
      expanded ? entries.length : math.min(entries.length, collapsedCount);

  @override
  set length(int value) =>
      throw UnsupportedError('Read-only directory listing');

  @override
  ArchiveEntry operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return entries[index];
  }

  @override
  void operator []=(int index, ArchiveEntry value) =>
      throw UnsupportedError('Read-only directory listing');
}
