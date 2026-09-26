import 'dart:convert';
import '../core/utils/date_utils_extension.dart';

const maxCents = 99999999999;
int? parseMoney(String input) {
  final v = input.trim();
  if (v.isEmpty) return null;
  if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(v)) {
    throw const FormatException('请输入非负金额，最多两位小数');
  }
  final p = v.split('.');
  final c =
      int.parse(p[0]) * 100 +
      (p.length == 2 ? int.parse(p[1].padRight(2, '0')) : 0);
  checkMoney(c);
  return c;
}

String amountText(int c) =>
    '${c ~/ 100}.${(c % 100).toString().padLeft(2, '0')}';
String money(int? c) => c == null ? '待补价格' : '¥${amountText(c)}';

enum PlanState { pending, carried, bought, declined }

class MonthPlan {
  MonthPlan(
    this.estimate, {
    this.state = PlanState.pending,
    this.purchaseOnly = false,
  });
  int? estimate;
  PlanState state;
  bool purchaseOnly;
  Map<String, dynamic> toJson() => {
    'estimate': estimate,
    'state': state.name,
    'purchaseOnly': purchaseOnly,
  };
  factory MonthPlan.fromJson(Map<String, dynamic> j) => MonthPlan(
    j['estimate'] as int?,
    state: PlanState.values.byName(j['state'] as String),
    purchaseOnly: j['purchaseOnly'] as bool,
  );
}

class Purchase {
  Purchase(this.cents, this.date);
  int cents;
  DateTime date;
  Map<String, dynamic> toJson() => {'cents': cents, 'date': date.dateKey};
  factory Purchase.fromJson(Map<String, dynamic> j) =>
      Purchase(j['cents'] as int, _date(j['date']));
}

class Wish {
  Wish({
    required this.id,
    required this.title,
    required this.created,
    this.estimate,
    this.photo,
    this.note = '',
    this.review = '',
    this.declined = false,
    this.purchase,
    Map<String, MonthPlan>? months,
  }) : months = months ?? {};
  final String id;
  String title;
  DateTime created;
  int? estimate;
  String? photo;
  String note;
  String review;
  bool declined;
  Purchase? purchase;
  final Map<String, MonthPlan> months;
  bool get pending => purchase == null && !declined;
  bool get direct => months.isEmpty && purchase != null;
  String get latestMonth =>
      months.keys.reduce((a, b) => a.compareTo(b) > 0 ? a : b);
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created': created.dateKey,
    'estimate': estimate,
    'photo': photo,
    'note': note,
    'review': review,
    'declined': declined,
    'purchase': purchase?.toJson(),
    'months': months.map((k, v) => MapEntry(k, v.toJson())),
  };
  factory Wish.fromJson(Map<String, dynamic> j) => Wish(
    id: j['id'] as String,
    title: j['title'] as String,
    created: _date(j['created']),
    estimate: j['estimate'] as int?,
    photo: j['photo'] as String?,
    note: j['note'] as String,
    review: j['review'] as String,
    declined: j['declined'] as bool,
    purchase: j['purchase'] == null
        ? null
        : Purchase.fromJson(Map<String, dynamic>.from(j['purchase'] as Map)),
    months: (j['months'] as Map).map(
      (k, v) => MapEntry(
        k as String,
        MonthPlan.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
  );
}

class MonthlySummary {
  int planned = 0, actual = 0, remaining = 0, declined = 0;
  int unknown = 0, pendingUnknown = 0, boughtCount = 0, declinedCount = 0;
  int get forecast => actual + remaining;
}

class Ledger {
  Ledger({
    List<Wish>? items,
    Map<String, int>? budgets,
    Set<String>? seenReports,
  }) : items = items ?? [],
       budgets = budgets ?? {},
       seenReports = seenReports ?? {};
  final List<Wish> items;
  final Map<String, int> budgets;
  final Set<String> seenReports;
  MonthlySummary summary(String month) {
    final s = MonthlySummary();
    for (final w in items) {
      final p = w.months[month];
      if (p != null) {
        s.planned += p.estimate ?? 0;
        if (p.estimate == null) s.unknown++;
        if (p.state == PlanState.pending || p.state == PlanState.carried) {
          s.remaining += p.estimate ?? 0;
          if (p.estimate == null) s.pendingUnknown++;
        }
        if (p.state == PlanState.declined) {
          s.declined += p.estimate ?? 0;
          s.declinedCount++;
        }
      }
      if (w.purchase?.date.monthKey == month) {
        s.actual += w.purchase!.cents;
        s.boughtCount++;
      }
    }
    return s;
  }

  List<Wish> inMonth(String month) => items
      .where(
        (w) =>
            w.months.containsKey(month) || w.purchase?.date.monthKey == month,
      )
      .toList();
  List<Wish> unresolved(String currentMonth) => items
      .where(
        (w) =>
            w.pending &&
            w.months.isNotEmpty &&
            w.latestMonth.compareTo(currentMonth) < 0,
      )
      .toList();
  Set<String> get recordedMonths => {
    for (final w in items) ...w.months.keys,
    for (final w in items)
      if (w.purchase != null) w.purchase!.date.monthKey,
  };
  Wish find(String id) => items.firstWhere((w) => w.id == id);
  void carry(String id, String target) {
    checkMonth(target);
    final w = find(id);
    if (!w.pending || w.months.isEmpty) throw StateError('这条记录已处理');
    if (w.months.containsKey(target)) return;
    if (target.compareTo(w.latestMonth) <= 0) throw StateError('只能保留到后续月份');
    w.months[w.latestMonth]!.state = PlanState.carried;
    w.months[target] = MonthPlan(w.estimate);
  }

  void decline(String id) {
    final w = find(id);
    if (!w.pending || w.months.isEmpty) throw StateError('这条记录已处理');
    w.declined = true;
    w.months[w.latestMonth]!.state = PlanState.declined;
  }

  void buy(String id, int cents, DateTime date) {
    checkMoney(cents);
    final w = find(id);
    if (w.declined) throw StateError('已放弃的记录不能直接购买');
    if (date.startOfDay.isBefore(w.created.startOfDay)) {
      throw StateError('购买日期不能早于添加日期');
    }
    if (date.startOfDay.isAfter(DateTime.now().startOfDay)) {
      throw StateError('购买日期不能晚于今天');
    }
    if (w.purchase != null && !w.direct) {
      final old = w.purchase!.date.monthKey;
      if (w.months[old]?.purchaseOnly == true) {
        w.months.remove(old);
      } else {
        w.months[old]?.state = PlanState.pending;
      }
    }
    if (w.months.isNotEmpty) {
      if (date.monthKey.compareTo(w.latestMonth) < 0) {
        throw StateError('购买日期不能早于最后保留的月份');
      }
      w.months
              .putIfAbsent(
                date.monthKey,
                () => MonthPlan(w.estimate, purchaseOnly: true),
              )
              .state =
          PlanState.bought;
    }
    w.purchase = Purchase(cents, date.startOfDay);
  }

  String encode() => jsonEncode({
    'format': 'calm-shopping',
    'version': 1,
    'items': items.map((w) => w.toJson()).toList(),
    'budgets': budgets,
    'seenReports': seenReports.toList(),
  });
  factory Ledger.decode(String source) {
    try {
      if (utf8.encode(source).length > 50 * 1024 * 1024) {
        throw const FormatException('备份文件超过 50 MB');
      }
      final j = jsonDecode(source) as Map<String, dynamic>;
      if (j['format'] != 'calm-shopping' || j['version'] != 1) {
        throw const FormatException('不是此版本支持的购物冷静清单备份');
      }
      final raw = j['items'] as List;
      if (raw.length > 5000) throw const FormatException('记录数量超过上限');
      final ledger = Ledger(
        items: raw
            .map((v) => Wish.fromJson(Map<String, dynamic>.from(v as Map)))
            .toList(),
        budgets: (j['budgets'] as Map).map(
          (k, v) => MapEntry(k as String, v as int),
        ),
        seenReports: (j['seenReports'] as List).cast<String>().toSet(),
      );
      final ids = <String>{};
      for (final w in ledger.items) {
        if (w.id.isEmpty ||
            !ids.add(w.id) ||
            w.title.trim().isEmpty ||
            w.title.length > 100 ||
            w.note.length > 2000 ||
            w.review.length > 2000) {
          throw const FormatException('记录内容不完整或重复');
        }
        if (w.estimate != null) checkMoney(w.estimate!);
        if (w.photo != null &&
            (w.photo!.length > 12 * 1024 * 1024 ||
                base64Decode(w.photo!).isEmpty)) {
          throw const FormatException('图片数据无效');
        }
        if (w.months.isEmpty && (w.purchase == null || w.declined)) {
          throw const FormatException('记录缺少消费状态');
        }
        if (w.declined && w.purchase != null) {
          throw const FormatException('消费状态冲突');
        }
        for (final m in w.months.entries) {
          checkMonth(m.key);
          if (m.key.compareTo(w.created.monthKey) < 0) {
            throw const FormatException('计划月份早于添加日期');
          }
          if (m.value.estimate != null) checkMoney(m.value.estimate!);
          if (m.value.state == PlanState.bought &&
              w.purchase?.date.monthKey != m.key) {
            throw const FormatException('消费日期与状态不一致');
          }
          if (m.value.state == PlanState.declined && !w.declined) {
            throw const FormatException('放弃状态与记录不一致');
          }
          if (m.value.purchaseOnly && m.value.state != PlanState.bought) {
            throw const FormatException('购买月份状态无效');
          }
        }
        if (w.purchase != null) {
          checkMoney(w.purchase!.cents);
          if (w.purchase!.date.isBefore(w.created.startOfDay)) {
            throw const FormatException('消费日期错误');
          }
          if (w.months.isNotEmpty &&
              w.months[w.purchase!.date.monthKey]?.state != PlanState.bought) {
            throw const FormatException('消费状态不完整');
          }
          if (w.months.isNotEmpty &&
              w.latestMonth != w.purchase!.date.monthKey) {
            throw const FormatException('购买后不能还有待购月份');
          }
        }
        if (w.declined &&
            w.months.values
                    .where((p) => p.state == PlanState.declined)
                    .length !=
                1) {
          throw const FormatException('放弃状态不完整');
        }
      }
      for (final b in ledger.budgets.entries) {
        checkMonth(b.key);
        checkMoney(b.value);
      }
      for (final m in ledger.seenReports) {
        checkMonth(m);
      }
      return ledger;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份内容损坏或格式不兼容');
    }
  }
}

void checkMoney(int c) {
  if (c < 0 || c > maxCents) throw const FormatException('金额超出范围');
}

void checkMonth(String v) {
  if (!RegExp(r'^20\d{2}-(0[1-9]|1[0-2])$').hasMatch(v)) {
    throw const FormatException('月份格式错误');
  }
}

DateTime _date(dynamic v) {
  if (v is! String || !RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(v)) {
    throw const FormatException('日期格式错误');
  }
  final d = DateTime.parse(v);
  if (d.dateKey != v) throw const FormatException('日期不存在');
  return d;
}
