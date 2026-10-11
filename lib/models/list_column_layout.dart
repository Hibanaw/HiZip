import 'dart:math' as math;

/// Name absorbs window resizing; metadata widths change only by dragging.
class ListColumnLayout {
  const ListColumnLayout({
    required this.availableWidth,
    required this.size,
    required this.modified,
    required this.kind,
  });

  static const minName = 80.0;
  static const minSize = 65.0;
  static const minModified = 90.0;
  static const minKind = 65.0;
  static const maxSize = 400.0;
  static const maxModified = 400.0;
  static const maxKind = 2000.0;

  final double availableWidth, size, modified, kind;
  bool get showMetadata => availableWidth >= minName + size + modified + kind;
  double get name =>
      showMetadata ? availableWidth - size - modified - kind : availableWidth;

  ListColumnLayout withAvailableWidth(double width) => ListColumnLayout(
    availableWidth: width,
    size: size,
    modified: modified,
    kind: kind,
  );

  /// Keep Type's right edge pinned while redistributing space to its left.
  ListColumnLayout resizeBoundary(String column, double delta) {
    final index = switch (column) {
      'name' => 0,
      'size' => 1,
      'modified' => 2,
      _ => -1,
    };
    if (!showMetadata || index < 0) return this;
    final widths = [name, size, modified, kind];
    const minimums = [minName, minSize, minModified, minKind];
    const maximums = [double.infinity, maxSize, maxModified, maxKind];
    if (delta >= 0) {
      var available = 0.0;
      for (var right = index + 1; right < widths.length; right++) {
        available += widths[right] - minimums[right];
      }
      var remaining = math.min(
        delta,
        math.min(available, maximums[index] - widths[index]),
      );
      widths[index] += remaining;
      // Compress the rightmost column first, then work back toward the divider.
      for (var right = widths.length - 1; right > index; right--) {
        final take = math.min(remaining, widths[right] - minimums[right]);
        widths[right] -= take;
        remaining -= take;
      }
    } else {
      final released = math.min(
        -delta,
        math.min(widths[index] - minimums[index], maxKind - kind),
      );
      widths[index] -= released;
      widths[3] += released;
    }
    return ListColumnLayout(
      availableWidth: availableWidth,
      size: widths[1],
      modified: widths[2],
      kind: widths[3],
    );
  }
}
