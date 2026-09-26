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
        title: Text('$last 月报已生成'),
        content: Text(
          '已记录消费 ${money(s.actual)}，共 ${s.boughtCount} 笔。\n\n还没买的东西，可以保留到本月、不买，或者留待下次处理。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('稍后查看'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('看看月报'),
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
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            WishEditor(store: widget.store, wish: wish, direct: direct),
      ),
    );
    if (mounted) {
      setState(() {
        if (wish == null) {
          month = DateTime.now().startOfMonth;
          filter = 0;
        }
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
      '这次不买了',
      '“${w.title}”会保留在记录中，并从待购金额中移出。',
      action: '确定不买',
    )) {
      await _change((l) => l.decline(w.id));
    }
  }

  Future<void> _delete(Wish w) async {
    if (await confirm(
      context,
      '删除这条记录？',
      '“${w.title}”及其图片、跨月记录和实际消费会一起删除，相关月报会重新统计。此操作无法撤销。',
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
        title: Text('${month.month} 月消费上限'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixText: '¥ ',
              helperText: '可选；留空即取消本月上限',
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
              tooltip: '记下想买的',
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
              '${s.unknown} 项待补价格，未计入预计金额',
              style: TextStyle(color: Colors.brown.shade700),
            ),
          ),
        const SizedBox(height: 14),
        _budgetCard(s),
        if (ledger.unresolved(DateTime.now().monthKey).isNotEmpty)
          _pendingBanner(),
        const SizedBox(height: 22),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (i, label) in ['全部', '待考虑', '已消费', '不买了'].indexed)
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
            filter == 0 ? '给想买的东西，一个停留的地方' : '这里暂时没有记录',
            filter == 0 ? '从一件衣服、一次聚餐开始。\n记下来，看看它们加在一起是多少。' : '切换筛选，看看其他记录。',
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
        const Row(
          children: [
            Icon(Icons.spa_outlined, color: Color(0xFF7C8C6B), size: 18),
            SizedBox(width: 8),
            Text(
              '把想买的放在一起看',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          '如果待购的都买了，本月合计',
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
              ? '已消费 + 待购估价 · 另有 ${s.pendingUnknown} 项待补价格'
              : '已消费 + 待购估价 · 给决定多一点余地',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    ),
  );
  Widget _metrics(MonthlySummary s) => Row(
    children: [
      _metric('计划总额', money(s.planned)),
      _metric('已记录消费', money(s.actual)),
      _metric('剩余待购', money(s.remaining)),
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
                          ? '给这个月设个消费上限（可选）'
                          : '本月上限 ${money(budget)}',
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
                      ? '按当前计划，预计超出 ${money(s.forecast - budget)}'
                      : '按当前计划，还留有 ${money(budget - s.forecast)}',
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
        '${ledger.unresolved(DateTime.now().monthKey).length} 项往月心愿，等你再看看',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: const Text('保留到本月、不买，或者以后再说', style: TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => setState(() => page = 1),
    ),
  );
  String _status(Wish w) {
    if (w.purchase?.date.monthKey == keyMonth) return '已消费';
    return switch (w.months[keyMonth]?.state) {
      PlanState.declined => '不买了',
      PlanState.carried => '已保留到后月',
      _ =>
        w.purchase != null
            ? '当月未买 · 后来已买'
            : w.declined
            ? '当月未买 · 后来放弃'
            : '待考虑',
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
                  Text('添加于 ${w.created.dateKey} · 预计 ${money(w.estimate)}'),
                  if (w.purchase != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${w.purchase!.date.dateKey} 实付 ${money(w.purchase!.cents)}',
                      ),
                    ),
                  if (w.months.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '保留记录：${(w.months.keys.toList()..sort()).join(' → ')}',
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
                      child: Text('给自己的备注\n${w.note}'),
                    ),
                  if (w.review.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text('买后感受\n${w.review}'),
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
                          label: const Text('已消费'),
                        ),
                        OutlinedButton(
                          onPressed: widget.store.busy
                              ? null
                              : () => _decline(w),
                          child: const Text('不买了'),
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
                      child: const Text('修改实付金额 / 日期'),
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
                        label: Text(w.purchase != null ? '编辑 / 买后感受' : '编辑'),
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
    final pending = ledger.unresolved(DateTime.now().monthKey);
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
          '${month.month} 月，回头看一看',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('不评判每一笔钱，了解自己的选择。', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 26),
        _hero(s),
        const SizedBox(height: 18),
        _metrics(s),
        if (s.unknown > 0) Text('有 ${s.unknown} 项价格未填写，预计金额不包含这些项目。'),
        const SizedBox(height: 24),
        _heading('买下的 · ${bought.length} 项'),
        if (bought.isEmpty)
          const Text('这个月还没有记录实际消费。')
        else
          ...bought.map(_tile),
        const SizedBox(height: 24),
        _heading('决定不买 · ${declined.length} 项'),
        Text(
          '放弃的计划金额 ${money(s.declined)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          '这是放弃的估价，不等于实际省下的钱。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        ...declined.map(_tile),
        const SizedBox(height: 24),
        _heading('往月未买的，还想保留吗？'),
        const Text(
          '不处理也没关系，记录会一直留着。只有选择保留，才会计入本月计划。',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('目前没有需要跨月处理的记录。'),
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
                  Text('${w.created.dateKey} 添加 · ${money(w.estimate)}'),
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
                        onPressed: widget.store.busy ? null : () => _decline(w),
                        child: const Text('不买了'),
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
        const SizedBox(height: 28),
        const Text(
          '统计口径：计划总额含本月新建与确认保留的计划；实际消费按支付日期计入，包含补记消费。统计仅覆盖你在这里记录的内容。',
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
      _heading('只属于你的清单'),
      const Text('免登录，记录和图片都保存在本机。', style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 28),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.save_alt),
        title: const Text('导出完整备份'),
        subtitle: const Text('包含记录、图片、预算与买后感受'),
        onTap: fileBusy || widget.store.busy ? null : _export,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.restore),
        title: const Text('从备份恢复'),
        subtitle: const Text('恢复前会校验，并请你确认覆盖当前数据'),
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
          '换手机或卸载前，请导出备份到你选定的位置。备份内含个人记录和图片，请自行妥善保管。',
          style: TextStyle(height: 1.7, fontSize: 13),
        ),
      ),
      const SizedBox(height: 32),
      _heading('使用方式'),
      const Text(
        '① 手动记下名称和预计价格，图片可选。\n② 看看本月全部计划加起来是多少。\n③ 买了填写实付，不买就留个决定。\n④ 下个月打开，回顾消费和未买的心愿。',
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
          applicationVersion: '0.1.2',
          applicationLegalese:
              'Derived from erdipakrana/expense_app\nCopyright (c) 2026 Dipak Rana\nMIT License',
        ),
      ),
      const Text(
        '0.1.2\n手动添加 · 无广告 · 无账号',
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
      if (path != null && mounted) toast(context, '备份已保存，包含图片');
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
        '恢复 ${candidate.items.length} 条记录？',
        '备份已通过校验。恢复将用备份完整替换当前 ${ledger.items.length} 条记录及图片，不会合并。',
        action: '覆盖并恢复',
      )) {
        await widget.store.restore(candidate);
        if (mounted) {
          toast(context, '备份已恢复');
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
