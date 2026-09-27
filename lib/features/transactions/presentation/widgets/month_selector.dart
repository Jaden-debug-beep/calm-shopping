import 'package:flutter/material.dart';

/// Widget: MonthSelector
///
/// Provides month navigation controls for the transactions view.
/// Allows moving between months and choosing a date to view its month.
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
    final now = DateTime.now();
    final isCurrentMonth =
        currentMonth.year == now.year && currentMonth.month == now.month;
    final selectedLabel = isCurrentMonth ? '本月' : '${currentMonth.month}月';

    Future<void> chooseDate() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: isCurrentMonth ? now : currentMonth,
        firstDate: DateTime(2000),
        lastDate: DateTime(2099, 12, 31),
        helpText: '选择日期，查看所在月份',
      );
      if (picked != null) onChanged(DateTime(picked.year, picked.month));
    }

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
            onPressed: currentMonth.year == 2000 && currentMonth.month == 1
                ? null
                : () => onChanged(
                    DateTime(currentMonth.year, currentMonth.month - 1),
                  ),
            tooltip: '上个月',
          ),

          const SizedBox(width: 8),

          // The displayed month is also a date-picker entry point.
          Expanded(
            child: TextButton(
              onPressed: chooseDate,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${currentMonth.year} 年 ${currentMonth.month} 月',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Next Month Button
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: currentMonth.year == 2099 && currentMonth.month == 12
                ? null
                : () => onChanged(
                    DateTime(currentMonth.year, currentMonth.month + 1),
                  ),
            tooltip: '下个月',
          ),

          const SizedBox(width: 8),

          // Keep the calendar action's label in sync with the selected month.
          TextButton.icon(
            onPressed: chooseDate,
            icon: const Icon(Icons.today, size: 18),
            label: Text(selectedLabel),
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
