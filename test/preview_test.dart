import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_expense_tracker/main.dart';
import 'package:smart_expense_tracker/data/ledger_store.dart';
import 'package:smart_expense_tracker/domain/ledger.dart';
import 'package:smart_expense_tracker/core/utils/date_utils_extension.dart';

void main() {
  testWidgets('capture phone layout for visual review', (t) async {
    await t.runAsync(() async {
      final loader = FontLoader('Roboto');
      loader.addFont(
        File(
          const String.fromEnvironment(
            'PREVIEW_FONT',
            defaultValue: 'C:/Windows/Fonts/msyh.ttc',
          ),
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File(
          '${const String.fromEnvironment('FLUTTER_SDK')}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
      await icons.load();
    });
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final l = Ledger(budgets: {now.monthKey: 100000});
    for (final (i, (name, price)) in [
      ('游戏皮肤', 10000),
      ('秋天的外套', 20000),
      ('周末朋友聚餐', 10000),
      ('新的蓝牙耳机', 59900),
    ].indexed) {
      l.items.add(
        Wish(
          id: '$i',
          title: name,
          created: now.startOfDay,
          estimate: price,
          months: {now.monthKey: MonthPlan(price)},
        ),
      );
    }
    l.buy('2', 8800, now);
    await t.pumpWidget(
      RepaintBoundary(
        key: const Key('preview'),
        child: CalmApp(store: LedgerStore(null, l)),
      ),
    );
    await t.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('preview')),
      matchesGoldenFile('../docs/screens/home.png'),
    );
    await t.tap(find.byTooltip('记下想买的'));
    await t.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('preview')),
      matchesGoldenFile('../docs/screens/add.png'),
    );
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('月报'));
    await t.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('preview')),
      matchesGoldenFile('../docs/screens/report.png'),
    );
    await t.tap(find.text('设置'));
    await t.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('preview')),
      matchesGoldenFile('../docs/screens/settings.png'),
    );
    expect(t.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('CAPTURE_PREVIEW'));
}
