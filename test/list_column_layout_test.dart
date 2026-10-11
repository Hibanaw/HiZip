import 'package:flutter_test/flutter_test.dart';
import 'package:hizip/models/list_column_layout.dart';

void main() {
  const layout = ListColumnLayout(
    availableWidth: 1000,
    size: 85,
    modified: 115,
    kind: 85,
  );
  test('metadata hide only when the elastic Name cannot fit its minimum', () {
    expect(layout.withAvailableWidth(365).name, 80);
    expect(layout.withAvailableWidth(365).showMetadata, isTrue);
    expect(layout.withAvailableWidth(364).showMetadata, isFalse);
    expect(layout.withAvailableWidth(364).name, 364);
  });
  test('all resize extremes preserve the right edge and viewport width', () {
    for (final column in ['name', 'size', 'modified', 'kind']) {
      for (final delta in [
        -10000.0,
        -600.0,
        -10.0,
        0.0,
        10.0,
        600.0,
        10000.0,
      ]) {
        final next = layout.resizeBoundary(column, delta);
        expect(
          next.name + next.size + next.modified + next.kind,
          closeTo(1000, .0001),
        );
        expect(next.name, greaterThanOrEqualTo(ListColumnLayout.minName));
        expect(
          next.size,
          inInclusiveRange(ListColumnLayout.minSize, ListColumnLayout.maxSize),
        );
        expect(
          next.modified,
          inInclusiveRange(
            ListColumnLayout.minModified,
            ListColumnLayout.maxModified,
          ),
        );
        expect(
          next.kind,
          inInclusiveRange(ListColumnLayout.minKind, ListColumnLayout.maxKind),
        );
        if (column == 'size' || column == 'modified') {
          expect(next.name, layout.name);
        }
        if (column == 'modified') expect(next.size, layout.size);
        if (column == 'kind') expect(next, same(layout));
      }
    }
  });
  test('Name drag right compresses Type, then Modified, then Size', () {
    var next = layout.resizeBoundary('name', 15);
    expect((next.size, next.modified, next.kind), (85, 115, 70));
    next = layout.resizeBoundary('name', 35);
    expect((next.size, next.modified, next.kind), (85, 100, 65));
    next = layout.resizeBoundary('name', 55);
    expect((next.size, next.modified, next.kind), (75, 90, 65));
    next = layout.resizeBoundary('name', 10000);
    expect((next.size, next.modified, next.kind), (65, 90, 65));
  });
  test('leftward drags release width only to Type', () {
    final name = layout.resizeBoundary('name', -600);
    expect(
      (name.name, name.size, name.modified, name.kind),
      (115, 85, 115, 685),
    );
    final size = layout.resizeBoundary('size', -10);
    expect(
      (size.name, size.size, size.modified, size.kind),
      (715, 75, 115, 95),
    );
    final modified = layout.resizeBoundary('modified', -10);
    expect(
      (modified.name, modified.size, modified.modified, modified.kind),
      (715, 85, 105, 95),
    );
  });
}
