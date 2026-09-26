import 'package:flutter/material.dart';

/// Widget: MonthSelector
///
/// Provides month navigation controls for the transactions view.
/// Allows moving between months and jumping to today.
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.currentMonth,
    required this.onChanged,
  });
  final DateTime currentMonth;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Previous Month Button
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                onChanged(DateTime(currentMonth.year, currentMonth.month - 1)),
            tooltip: '上个月',
          ),

          const SizedBox(width: 8),

          // Current Month Display
          Expanded(
            child: Center(
              child: Text(
                '${currentMonth.year} 年 ${currentMonth.month} 月',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Next Month Button
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                onChanged(DateTime(currentMonth.year, currentMonth.month + 1)),
            tooltip: '下个月',
          ),

          const SizedBox(width: 8),

          // Today Button
          TextButton.icon(
            onPressed: () => onChanged(DateTime.now()),
            icon: const Icon(Icons.today, size: 18),
            label: const Text('本月'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
