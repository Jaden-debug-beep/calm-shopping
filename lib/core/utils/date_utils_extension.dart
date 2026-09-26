// Adapted from erdipakrana/expense_app (MIT); see docs/REUSE.md.
extension DateUtilsExtension on DateTime {
  String get dateKey =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  String get monthKey => '$year-${month.toString().padLeft(2, '0')}';
  DateTime get startOfDay => DateTime(year, month, day);
  DateTime get startOfMonth => DateTime(year, month);
}

// Upstream's newest-first date grouping, decoupled from paid transactions.
Map<String, List<T>> groupByDate<T>(
  Iterable<T> items,
  DateTime Function(T) date,
) {
  final grouped = <String, List<T>>{};
  for (final item in items) {
    (grouped[date(item).dateKey] ??= []).add(item);
  }
  final entries = grouped.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  return Map.fromEntries(entries);
}
