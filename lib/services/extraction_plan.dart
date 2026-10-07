import '../models/archive_entry.dart';

/// ZIP entries have independent codecs. Stream/solid archives use one pass so
/// prior data is not repeatedly decompressed by competing readers.
List<List<int>> planExtraction(
  List<ArchiveEntry> entries, {
  required String format,
  required int processors,
  int? maxWorkers,
}) {
  if (entries.isEmpty) return [];
  final size = entries.fold<int>(
    0,
    (sum, e) => sum + (e.size < 0 ? 0 : e.size),
  );
  final parallel =
      format.toUpperCase().startsWith('ZIP') &&
      entries.every((e) => e.size >= 0);
  final cap = (maxWorkers ?? (processors - 1)).clamp(1, 4);
  final count = parallel && (size >= 8 * 1024 * 1024 || maxWorkers != null)
      ? cap.clamp(1, entries.length)
      : 1;
  final batches = List.generate(count, (_) => <int>[]);
  final loads = List<int>.filled(count, 0);
  final indices = List.generate(entries.length, (i) => i)
    ..sort((a, b) => entries[b].size.compareTo(entries[a].size));
  for (final index in indices) {
    var lightest = 0;
    for (var i = 1; i < count; i++) {
      if (loads[i] < loads[lightest]) lightest = i;
    }
    batches[lightest].add(index);
    loads[lightest] += entries[index].size > 0 ? entries[index].size : 1;
  }
  return batches;
}
