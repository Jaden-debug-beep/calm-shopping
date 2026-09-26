import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_expense_tracker/main.dart';
import 'package:smart_expense_tracker/data/ledger_store.dart';
import 'package:smart_expense_tracker/domain/ledger.dart';
import 'package:smart_expense_tracker/ui/editor.dart';
import 'package:smart_expense_tracker/core/utils/date_utils_extension.dart';

void main() {
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
    expect(find.text('${previous.monthKey} 月报已生成'), findsOneWidget);
    await t.tap(find.text('稍后查看'));
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
      expect(find.text('给想买的东西，一个停留的地方'), findsOneWidget);
      await t.tap(find.byTooltip('记下想买的'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, '游戏皮肤');
      await t.ensureVisible(find.text('保存记录'));
      await t.tap(find.text('保存记录'));
      await t.pumpAndSettle();
      expect(store.ledger.items.single.estimate, null);
      await t.ensureVisible(find.text('游戏皮肤'));
      await t.tap(find.text('游戏皮肤'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, '已消费'));
      await t.pumpAndSettle();
      await t.tap(find.text('确认金额'));
      await t.pumpAndSettle();
      expect(find.text('请输入实际金额'), findsOneWidget);
      expect(store.ledger.items.single.purchase, null);
      await t.tap(find.text('再想想'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(OutlinedButton, '不买了'));
      await t.pumpAndSettle();
      await t.tap(find.text('确定不买'));
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
}
