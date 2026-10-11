import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/archive_entry.dart';
import 'package:hizip/models/directory_listing.dart';
import 'package:hizip/models/archive_index.dart';

void main() {
  List<ArchiveEntry> entries(int count) => List.generate(
    count,
    (index) => ArchiveEntry(path: '$index.txt', size: 0, directory: false),
  );

  test('small directories do not need an expansion row', () {
    for (final count in [0, 999, 1000]) {
      final listing = DirectoryListing(entries(count));
      expect(listing.length, count);
      expect(listing.remainingCount, 0);
    }
  });

  test('large directories expose a read-only prefix without copying', () {
    final source = entries(100001);
    final listing = DirectoryListing(source);
    expect(identical(listing.entries, source), true);
    expect(listing.length, 1000);
    expect(listing.remainingCount, 99001);
    expect(listing.last, same(source[999]));
    expect(() => listing[1000], throwsRangeError);
    expect(() => listing[-1], throwsRangeError);
    expect(() => listing.length = 0, throwsUnsupportedError);
    expect(() => listing[0] = source.last, throwsUnsupportedError);
    expect(source.length, 100001);
  });

  test('expansion exposes every remaining item without another limit', () {
    final source = entries(100001);
    final listing = DirectoryListing(source, expanded: true);
    expect(identical(listing.entries, source), true);
    expect(listing.length, source.length);
    expect(listing.remainingCount, 0);
    expect(listing.last, same(source.last));
  });

  test('search filters the full directory before folding its results', () {
    final source = entries(2505);
    final collapsed = DirectoryListing(source);
    expect(collapsed.any((entry) => entry.path == '2504.txt'), false);
    final results = DirectoryListing(filterArchiveEntries((source, '2504')));
    expect(results.single.path, '2504.txt');
    expect(results.remainingCount, 0);
  });
}
