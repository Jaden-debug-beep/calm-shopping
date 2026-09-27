import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_expense_tracker/main.dart';
import 'package:smart_expense_tracker/data/ledger_store.dart';
import 'package:smart_expense_tracker/domain/ledger.dart';
import 'package:smart_expense_tracker/ui/editor.dart';
import 'package:smart_expense_tracker/core/utils/date_utils_extension.dart';

void main() {
  testWidgets('calendar button selects a month and updates monthly labels', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final previous = DateTime(DateTime.now().year, DateTime.now().month - 1);
    final store = LedgerStore(null, Ledger());
    await t.pumpWidget(CalmApp(store: store));
    await t.pumpAndSettle();
    await t.tap(find.text('本月'));
    await t.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('选择日期，查看所在月份'), findsOneWidget);
    final picker = find.byType(DatePickerDialog);
    await t.tap(
      find.descendant(of: picker, matching: find.byIcon(Icons.chevron_left)),
    );
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: picker, matching: find.text('15')).last);
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    expect(find.text('${previous.month}月'), findsOneWidget);
    expect(
      find.text('${previous.year}年${previous.month}月消费概览'),
      findsOneWidget,
    );
    expect(
      find.text('设置${previous.year}年${previous.month}月消费上限（可选）'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('a backdated new plan remains visible after saving', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final previous = DateTime(DateTime.now().year, DateTime.now().month - 1);
    final store = LedgerStore(null, Ledger());
    await t.pumpWidget(CalmApp(store: store));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('添加购买计划'));
    await t.pumpAndSettle();
    await t.tap(find.text('添加日期'));
    await t.pumpAndSettle();
    final picker = find.byType(DatePickerDialog);
    await t.tap(
      find.descendant(of: picker, matching: find.byIcon(Icons.chevron_left)),
    );
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: picker, matching: find.text('15')).last);
    await t.tap(find.text('确定'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, '上月补记的商品');
    await t.ensureVisible(find.text('保存记录'));
    await t.tap(find.text('保存记录'));
    await t.pumpAndSettle();
    expect(store.ledger.items.single.created.monthKey, previous.monthKey);
    expect(find.text('上月补记的商品'), findsOneWidget);
    expect(find.text('${previous.month}月'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('month opening prompts review; later preserves unresolved wish', (
    t,
  ) async {
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1, 2);
    final w = Wish(
      id: 'old',
      title: '上个月的心愿',
      created: previous,
      estimate: 50000,
      months: {previous.monthKey: MonthPlan(50000)},
    );
    final store = LedgerStore(null, Ledger(items: [w]));
    await t.pumpWidget(CalmApp(store: store));
    await t.pumpAndSettle();
    expect(find.text('${previous.monthKey} 消费回顾已生成'), findsOneWidget);
    await t.tap(find.text('稍后'));
    await t.pumpAndSettle();
    expect(store.ledger.unresolved(now.monthKey).length, 1);
    expect(store.ledger.summary(now.monthKey).planned, 0);
    expect(store.ledger.seenReports.contains(previous.monthKey), true);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'manual add with unknown price, actual amount required, then decline remains in history',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final store = LedgerStore(null, Ledger());
      await t.pumpWidget(CalmApp(store: store));
      await t.pumpAndSettle();
      expect(find.text('所选月份暂无记录'), findsOneWidget);
      await t.tap(find.byTooltip('添加购买计划'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, '游戏皮肤');
      await t.ensureVisible(find.text('保存记录'));
      await t.tap(find.text('保存记录'));
      await t.pumpAndSettle();
      expect(store.ledger.items.single.estimate, null);
      await t.ensureVisible(find.text('游戏皮肤'));
      await t.tap(find.text('游戏皮肤'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '记录消费'));
      await t.pumpAndSettle();
      await t.tap(find.text('确认记录'));
      await t.pumpAndSettle();
      expect(find.text('请输入实际金额'), findsOneWidget);
      expect(store.ledger.items.single.purchase, null);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(OutlinedButton, '决定不买'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '确认不买'));
      await t.pumpAndSettle();
      expect(store.ledger.items.single.declined, true);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('purchase dialog has no estimated amount prefilled', (t) async {
    final w = Wish(
      id: '1',
      title: '衣服',
      created: DateTime.now(),
      estimate: 20000,
    );
    await t.pumpWidget(MaterialApp(home: PurchaseDialog(wish: w)));
    await t.pumpAndSettle();
    expect(
      t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '',
    );
    await t.enterText(find.byType(TextFormField), '180.5');
    await t.pump();
    expect(t.takeException(), isNull);
  });
  testWidgets('editing a purchase prefills the actual paid amount', (t) async {
    final w = Wish(
      id: 'paid',
      title: '衣服',
      created: DateTime.now(),
      estimate: 20000,
      purchase: Purchase(18050, DateTime.now()),
    );
    await t.pumpWidget(MaterialApp(home: PurchaseDialog(wish: w)));
    await t.pumpAndSettle();
    expect(
      t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '180.50',
    );
  });
}
