import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/utils/date_utils_extension.dart';
import '../data/ledger_store.dart';
import '../domain/ledger.dart';
import '../features/transactions/presentation/widgets/month_selector.dart';
import 'editor.dart';

class Home extends StatefulWidget {
  const Home({super.key, required this.store});
  final LedgerStore store;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  DateTime month = DateTime.now().startOfMonth;
  int page = 0, filter = 0;
  bool reportPrompt = false, fileBusy = false;
  Ledger get ledger => widget.store.ledger;
  String get keyMonth => month.monthKey;
  bool get isCurrentMonth => keyMonth == DateTime.now().monthKey;
  String get selectedMonthName =>
      isCurrentMonth ? '本月' : '${month.year}年${month.month}月';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkReport());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _checkReport();
    }
  }

  Future<void> _checkReport() async {
    if (reportPrompt || !mounted) return;
    final old =
        ledger.recordedMonths
            .where(
              (m) =>
                  m.compareTo(DateTime.now().monthKey) < 0 &&
                  !ledger.seenReports.contains(m),
            )
            .toList()
          ..sort();
    if (old.isEmpty) return;
    reportPrompt = true;
    final last = old.last;
    final s = ledger.summary(last);
    final show = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$last 消费回顾已生成'),
        content: Text(
          '该月记录消费 ${money(s.actual)}，共 ${s.boughtCount} 笔。可查看消费明细与购买计划的处理结果。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('查看月报'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await _change((l) => l.seenReports.addAll(old));
    if (show == true && mounted) {
      setState(() {
        page = 1;
        month = DateTime.parse('$last-01');
      });
    }
    reportPrompt = false;
  }

  Future<void> _change(void Function(Ledger) operation) async {
    try {
      await widget.store.change(operation);
    } catch (e) {
      if (mounted) toast(context, e);
    }
  }

  Future<void> _edit({Wish? wish, bool direct = false}) async {
    final savedDate = await Navigator.push<DateTime>(
      context,
      MaterialPageRoute<DateTime>(
        builder: (_) =>
            WishEditor(store: widget.store, wish: wish, direct: direct),
      ),
    );
    if (mounted && savedDate != null) {
      setState(() {
        month = savedDate.startOfMonth;
        filter = 0;
      });
    }
  }

  Future<void> _buy(Wish w) async {
    final p = await showDialog<Purchase>(
      context: context,
      builder: (_) => PurchaseDialog(wish: w),
    );
    if (p != null) await _change((l) => l.buy(w.id, p.cents, p.date));
  }

  Future<void> _decline(Wish w) async {
    if (await confirm(
      context,
      '确认不买',
      '“${w.title}”会保留在历史记录中，不再计入待购金额。',
      action: '确认不买',
    )) {
      await _change((l) => l.decline(w.id));
    }
  }

  Future<void> _delete(Wish w) async {
    if (await confirm(
      context,
      '删除这条记录？',
      '将删除“${w.title}”的计划、图片和消费记录，并重新计算相关月份的数据。此操作无法在应用内撤销。',
      action: '删除',
    )) {
      await _change((l) => l.items.removeWhere((i) => i.id == w.id));
    }
  }

  Future<void> _budget() async {
    final controller = TextEditingController(
      text: ledger.budgets[keyMonth] == null
          ? ''
          : amountText(ledger.budgets[keyMonth]!),
    );
    final form = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$selectedMonthName消费上限'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixText: '¥ ',
              helperText: '留空并保存，可取消所选月份的上限',
            ),
            validator: (v) => validatePrice(v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(c, controller.text);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Let the dialog's closing animation release its text field first.
    if (result != null) {
      await _change((l) {
        final c = parseMoney(result);
        if (c == null) {
          l.budgets.remove(keyMonth);
        } else {
          l.budgets[keyMonth] = c;
        }
      });
    }
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text(
          '冷静购物',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (page == 0)
            IconButton(
              onPressed: widget.store.busy ? null : () => _edit(direct: true),
              tooltip: '补记已发生的消费',
              icon: const Icon(Icons.receipt_long_outlined),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                if (widget.store.busy)
                  const LinearProgressIndicator(minHeight: 2),
                if (page != 2)
                  MonthSelector(
                    currentMonth: month,
                    onChanged: (v) {
                      if (v.year >= 2000 && v.year <= 2099) {
                        setState(() => month = v.startOfMonth);
                      }
                    },
                  ),
                Expanded(
                  child: page == 2
                      ? _settings()
                      : page == 1
                      ? _report()
                      : _list(),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: page == 0
          ? FloatingActionButton(
              onPressed: widget.store.busy ? null : () => _edit(),
              tooltip: '添加购买计划',
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (v) => setState(() => page = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: '清单',
          ),
          NavigationDestination(
            icon: Icon(Icons.donut_small_outlined),
            selectedIcon: Icon(Icons.donut_small),
            label: '月报',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: '设置',
          ),
        ],
      ),
    ),
  );

  Widget _list() {
    final s = ledger.summary(keyMonth);
    var rows = ledger.inMonth(keyMonth);
    rows = rows
        .where(
          (w) => switch (filter) {
            1 =>
              w.months[keyMonth]?.state == PlanState.pending ||
                  w.months[keyMonth]?.state == PlanState.carried,
            2 => w.purchase?.date.monthKey == keyMonth,
            3 => w.months[keyMonth]?.state == PlanState.declined,
            _ => true,
          },
        )
        .toList();
    final grouped = groupByDate(rows, (w) => w.created);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      children: [
        _hero(s),
        const SizedBox(height: 20),
        _metrics(s),
        if (s.unknown > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${s.unknown} 项未填写价格，未计入金额合计',
              style: TextStyle(color: Colors.brown.shade700),
            ),
          ),
        const SizedBox(height: 14),
        _budgetCard(s),
        if (isCurrentMonth &&
            ledger.unresolved(DateTime.now().monthKey).isNotEmpty)
          _pendingBanner(),
        const SizedBox(height: 22),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (i, label) in ['全部', '待决定', '已消费', '决定不买'].indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Semantics(
                    selected: filter == i,
                    button: true,
                    child: InkWell(
                      onTap: () => setState(() => filter = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: filter == i
                                  ? const Color(0xFF285E50)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontWeight: filter == i
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: filter == i
                                ? const Color(0xFF285E50)
                                : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (rows.isEmpty)
          _empty(
            filter == 0 ? '所选月份暂无记录' : '此分类暂无记录',
            filter == 0 ? '添加购买计划后，可在这里查看金额合计。' : '切换分类可查看其他记录。',
          ),
        for (final group in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 10),
            child: Text(
              '${group.key} 添加 · ${group.value.length} 项',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...group.value.map(_tile),
        ],
      ],
    );
  }

  Widget _hero(MonthlySummary s) => Container(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFDDDED5), width: 0.7)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.spa_outlined, color: Color(0xFF7C8C6B), size: 18),
            const SizedBox(width: 8),
            Text(
              '$selectedMonthName消费概览',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          '已消费与待购合计',
          style: TextStyle(color: Colors.black87, fontSize: 13),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            money(s.forecast),
            style: const TextStyle(
              fontSize: 46,
              fontWeight: FontWeight.w500,
              color: Color(0xFF285E50),
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          s.pendingUnknown > 0
              ? '实际支付 + 待购预计价格；另有 ${s.pendingUnknown} 项待购未填写价格'
              : '实际支付 + 待购预计价格',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    ),
  );
  Widget _metrics(MonthlySummary s) => Row(
    children: [
      _metric('计划金额', money(s.planned)),
      _metric('已记录消费', money(s.actual)),
      _metric('待购金额', money(s.remaining)),
    ],
  );
  Widget _metric(String label, String value) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _budgetCard(MonthlySummary s) {
    final budget = ledger.budgets[keyMonth];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _budget,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.track_changes_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      budget == null
                          ? '设置$selectedMonthName消费上限（可选）'
                          : '$selectedMonthName消费上限 ${money(budget)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              if (budget != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: budget == 0
                      ? (s.forecast > 0 ? 1 : 0)
                      : (s.forecast / budget).clamp(0, 1),
                  minHeight: 2,
                  borderRadius: BorderRadius.zero,
                  color: s.forecast > budget ? const Color(0xFFB66B3B) : null,
                ),
                const SizedBox(height: 8),
                Text(
                  s.forecast > budget
                      ? '按已消费与待购金额计算，超出 ${money(s.forecast - budget)}'
                      : '按已消费与待购金额计算，剩余 ${money(budget - s.forecast)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pendingBanner() => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history),
      title: Text(
        '${ledger.unresolved(DateTime.now().monthKey).length} 项往月待购尚未处理',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: const Text('可保留到本月，或决定不买', style: TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => setState(() {
        month = DateTime.now().startOfMonth;
        page = 1;
      }),
    ),
  );
  String _status(Wish w) {
    if (w.purchase?.date.monthKey == keyMonth) return '已消费';
    return switch (w.months[keyMonth]?.state) {
      PlanState.declined => '决定不买',
      PlanState.carried => '已转至后续月份',
      _ =>
        w.purchase != null
            ? '当月未买 · 后续已消费'
            : w.declined
            ? '当月未买 · 后续决定不买'
            : '待决定',
    };
  }

  Widget _tile(Wish w) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFDDDED5), width: 0.7)),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _details(w.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: w.photo == null
                    ? SizedBox(
                        width: 32,
                        height: 48,
                        child: const Icon(
                          Icons.shopping_bag_outlined,
                          color: Color(0xFF718271),
                        ),
                      )
                    : Image.memory(
                        base64Decode(w.photo!),
                        width: 52,
                        height: 58,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: 52,
                          height: 58,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _status(w),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF647966),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 125),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money(
                        w.purchase?.date.monthKey == keyMonth
                            ? w.purchase!.cents
                            : w.months[keyMonth]?.estimate,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.end,
                    ),
                    Text(
                      w.purchase?.date.monthKey == keyMonth ? '实付' : '预计',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _details(String id) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => ListenableBuilder(
        listenable: widget.store,
        builder: (c, _) {
          final matches = ledger.items.where((w) => w.id == id);
          if (matches.isEmpty) return const SizedBox.shrink();
          final w = matches.first;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    w.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text('添加日期 ${w.created.dateKey} · 预计价格 ${money(w.estimate)}'),
                  if (w.purchase != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '消费日期 ${w.purchase!.date.dateKey} · 实付 ${money(w.purchase!.cents)}',
                      ),
                    ),
                  if (w.months.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '计划月份：${(w.months.keys.toList()..sort()).join(' → ')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  if (w.photo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(
                          base64Decode(w.photo!),
                          height: 170,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Text('图片无法显示'),
                        ),
                      ),
                    ),
                  if (w.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text('备注\n${w.note}'),
                    ),
                  if (w.review.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text('消费感受\n${w.review}'),
                    ),
                  const SizedBox(height: 24),
                  if (w.pending)
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: widget.store.busy ? null : () => _buy(w),
                          icon: const Icon(Icons.check),
                          label: const Text('记录消费'),
                        ),
                        OutlinedButton(
                          onPressed: widget.store.busy
                              ? null
                              : () => _decline(w),
                          child: const Text('决定不买'),
                        ),
                        if (w.latestMonth.compareTo(DateTime.now().monthKey) <
                            0)
                          OutlinedButton(
                            onPressed: widget.store.busy
                                ? null
                                : () => _change(
                                    (l) =>
                                        l.carry(w.id, DateTime.now().monthKey),
                                  ),
                            child: const Text('保留到本月'),
                          ),
                      ],
                    ),
                  if (w.purchase != null)
                    OutlinedButton(
                      onPressed: widget.store.busy ? null : () => _buy(w),
                      child: const Text('修改消费金额与日期'),
                    ),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(c);
                          _edit(wish: w);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('编辑记录'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await _delete(w);
                          if (c.mounted &&
                              !ledger.items.any((i) => i.id == id)) {
                            Navigator.pop(c);
                          }
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('删除记录'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _report() {
    final s = ledger.summary(keyMonth);
    final pending = isCurrentMonth
        ? ledger.unresolved(DateTime.now().monthKey)
        : <Wish>[];
    final bought = ledger.items
        .where((w) => w.purchase?.date.monthKey == keyMonth)
        .toList();
    final declined = ledger.items
        .where((w) => w.months[keyMonth]?.state == PlanState.declined)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '${month.year}年${month.month}月消费回顾',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          '汇总所选月份在应用中记录的计划与消费。',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 26),
        _hero(s),
        const SizedBox(height: 18),
        _metrics(s),
        if (s.unknown > 0) Text('${s.unknown} 项未填写价格，未计入金额合计。'),
        const SizedBox(height: 24),
        _heading('已消费 · ${bought.length} 项'),
        if (bought.isEmpty) const Text('所选月份暂无消费记录。') else ...bought.map(_tile),
        const SizedBox(height: 24),
        _heading('决定不买 · ${declined.length} 项'),
        Text(
          '决定不买的计划金额 ${money(s.declined)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          '按计划价格计算，不代表实际节省金额。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        ...declined.map(_tile),
        if (isCurrentMonth) ...[
          const SizedBox(height: 24),
          _heading('往月待处理计划'),
          const Text(
            '这些记录不会自动计入当前月份。选择“保留到本月”后，才会计入当前月计划。',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          if (pending.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('暂无需要处理的往月计划。'),
            ),
          ...pending.map(
            (w) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: const Border(
                bottom: BorderSide(color: Color(0xFFDDDED5), width: 0.7),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '添加日期 ${w.created.dateKey} · 预计价格 ${money(w.estimate)}',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: widget.store.busy
                              ? null
                              : () => _change(
                                  (l) => l.carry(w.id, DateTime.now().monthKey),
                                ),
                          child: const Text('保留到本月'),
                        ),
                        TextButton(
                          onPressed: widget.store.busy
                              ? null
                              : () => _decline(w),
                          child: const Text('决定不买'),
                        ),
                        TextButton(
                          onPressed: () => _details(w.id),
                          child: const Text('查看'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        const Text(
          '统计说明：计划金额按添加或保留月份计入；实际消费按付款日期计入，包含补记记录。这里只统计在本应用中记录的内容。',
          style: TextStyle(fontSize: 12, height: 1.7, color: Colors.black54),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
  );
  Widget _empty(String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 16),
    child: Column(
      children: [
        const Icon(
          Icons.shopping_bag_outlined,
          size: 44,
          color: Color(0xFF8E9C7D),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            height: 1.8,
            fontSize: 13,
            color: Colors.black54,
          ),
        ),
      ],
    ),
  );

  Widget _settings() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _heading('数据与备份'),
      const Text(
        '无需登录。记录和图片保存在本机，本应用不提供云同步。',
        style: TextStyle(color: Colors.black54),
      ),
      const SizedBox(height: 28),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.save_alt),
        title: const Text('导出备份'),
        subtitle: const Text('包含记录、图片、消费上限和消费感受'),
        onTap: fileBusy || widget.store.busy ? null : _export,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.restore),
        title: const Text('导入备份'),
        subtitle: const Text('校验通过并确认后，将覆盖当前数据'),
        onTap: fileBusy || widget.store.busy ? null : _import,
      ),
      if (fileBusy) const LinearProgressIndicator(),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.only(left: 16),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFFB78950), width: 2)),
        ),
        child: const Text(
          '更换设备或卸载应用前，请先导出备份。备份包含个人记录和图片，请妥善保管。',
          style: TextStyle(height: 1.7, fontSize: 13),
        ),
      ),
      const SizedBox(height: 32),
      _heading('使用方式'),
      const Text(
        '① 添加购买计划，填写预计价格，图片可选。\n② 查看本月计划金额与待购金额。\n③ 消费后记录实付金额；决定不买时更新状态。\n④ 每月查看消费回顾，并处理往月待购计划。',
        style: TextStyle(height: 2),
      ),
      const SizedBox(height: 32),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('开源许可'),
        subtitle: const Text('基于 Smart Expense Tracker 改造 · MIT'),
        onTap: () => showLicensePage(
          context: context,
          applicationName: '冷静购物',
          applicationVersion: '0.1.4',
          applicationLegalese:
              'Derived from erdipakrana/expense_app\nCopyright (c) 2026 Dipak Rana\nMIT License',
        ),
      ),
      const Text(
        '0.1.4\n手动添加 · 无广告 · 无账号',
        style: TextStyle(color: Colors.black45, fontSize: 12, height: 1.8),
      ),
    ],
  );
  Future<void> _export() async {
    setState(() => fileBusy = true);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存冷静购物备份',
        fileName: 'calm-shopping-${DateTime.now().dateKey}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(ledger.encode())),
      );
      if (path != null && mounted) toast(context, '备份已保存');
    } catch (e) {
      if (mounted) toast(context, '导出失败：$e');
    } finally {
      if (mounted) setState(() => fileBusy = false);
    }
  }

  Future<void> _import() async {
    setState(() => fileBusy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null || bytes.length > 50 * 1024 * 1024) {
        throw const FormatException('文件无法读取或超过 50 MB');
      }
      final candidate = Ledger.decode(utf8.decode(bytes));
      if (!mounted) return;
      if (await confirm(
        context,
        '导入 ${candidate.items.length} 条记录？',
        '备份已通过校验。导入后将替换当前 ${ledger.items.length} 条记录及图片，不会合并。',
        action: '确认覆盖',
      )) {
        await widget.store.restore(candidate);
        if (mounted) {
          toast(context, '备份已导入');
          setState(() {
            month = DateTime.now().startOfMonth;
            filter = 0;
          });
        }
      }
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => fileBusy = false);
    }
  }
}
