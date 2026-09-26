import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:smart_expense_tracker/domain/ledger.dart';
import 'package:smart_expense_tracker/data/ledger_store.dart';

Wish item({int? price = 50000}) => Wish(
  id: 'one',
  title: '一件外套',
  created: DateTime(2025, 1, 3),
  estimate: price,
  months: {'2025-01': MonthPlan(price)},
);
void main() {
  test('backup rejects contradictory purchase and decline states', () {
    final l = Ledger(items: [item()]);
    l.find('one').months['2025-01']!.state = PlanState.declined;
    expect(() => Ledger.decode(l.encode()), throwsFormatException);
  });
  test(
    'money: exact fen, zero is valid, empty is unknown, invalid amounts rejected',
    () {
      expect(parseMoney('0.1'), 10);
      expect(parseMoney('0.20'), 20);
      expect(parseMoney(''), null);
      expect(parseMoney('0'), 0);
      expect(amountText(parseMoney('0.10')! + parseMoney('0.20')!), '0.30');
      for (final v in ['-1', 'NaN', '1.001', '1e3', '1000000000']) {
        expect(() => parseMoney(v), throwsFormatException);
      }
    },
  );
  test('carry retains historical estimate, buy records actual only once', () {
    final l = Ledger(items: [item()]);
    l.carry('one', '2025-02');
    l.carry('one', '2025-02');
    l.buy('one', 45000, DateTime(2025, 2, 4));
    expect(l.find('one').created, DateTime(2025, 1, 3));
    expect(l.summary('2025-01').planned, 50000);
    expect(l.summary('2025-01').actual, 0);
    expect(l.summary('2025-01').remaining, 50000);
    final feb = l.summary('2025-02');
    expect(feb.planned, 50000);
    expect(feb.actual, 45000);
    expect(feb.remaining, 0);
    expect(feb.forecast, 45000);
    expect(l.unresolved('2025-03'), isEmpty);
    expect(l.find('one').months.length, 2);
  });
  test('skipped months do not silently acquire plans', () {
    final l = Ledger(items: [item()]);
    l.carry('one', '2025-04');
    expect(l.summary('2025-02').planned, 0);
    expect(l.summary('2025-03').planned, 0);
    expect(l.inMonth('2025-04').length, 1);
  });
  test('unknown price and decline are not fake spending or savings', () {
    final l = Ledger(items: [item(price: null)]);
    expect(l.summary('2025-01').unknown, 1);
    expect(l.summary('2025-01').pendingUnknown, 1);
    l.decline('one');
    expect(l.summary('2025-01').declinedCount, 1);
    expect(l.summary('2025-01').actual, 0);
    expect(l.summary('2025-01').pendingUnknown, 0);
    expect(l.items.length, 1);
  });
  test('direct expense contributes to actual, never planned', () {
    final l = Ledger(
      items: [
        Wish(
          id: 'meal',
          title: '聚餐',
          created: DateTime(2025, 1, 2),
          purchase: Purchase(10000, DateTime(2025, 1, 2)),
        ),
      ],
    );
    expect(l.summary('2025-01').actual, 10000);
    expect(l.summary('2025-01').planned, 0);
  });
  test(
    'correct purchase date moves the actual amount, never duplicates it',
    () {
      final l = Ledger(items: [item()]);
      l.buy('one', 45000, DateTime(2025, 2, 4));
      l.buy('one', 43000, DateTime(2025, 3, 4));
      expect(l.summary('2025-02').actual, 0);
      expect(l.summary('2025-02').planned, 0);
      expect(l.summary('2025-03').actual, 43000);
      expect(l.summary('2025-01').remaining, 50000);
    },
  );
  test(
    'backup roundtrip includes photo, budget and review; bad versions rejected',
    () {
      final w = item()
        ..photo = base64Encode([1, 2, 3])
        ..review = '好用';
      final l = Ledger(
        items: [w],
        budgets: {'2025-01': 100000},
        seenReports: {'2025-01'},
      );
      final copy = Ledger.decode(l.encode());
      expect(copy.encode(), l.encode());
      expect(copy.find('one').photo, w.photo);
      expect(
        () => Ledger.decode(
          l.encode().replaceFirst('"version":1', '"version":9'),
        ),
        throwsFormatException,
      );
      expect(
        () =>
            Ledger.decode(l.encode().replaceFirst('2025-01-03', '2025-02-31')),
        throwsFormatException,
      );
      expect(() => Ledger.decode('{broken'), throwsFormatException);
    },
  );
  test(
    'failed mutation leaves memory and persisted record unchanged',
    () async {
      final store = LedgerStore(null, Ledger(items: [item()]));
      final before = store.ledger.encode();
      await expectLater(
        store.change((l) {
          l.items.clear();
          throw StateError('failed');
        }),
        throwsStateError,
      );
      expect(store.ledger.encode(), before);
      expect(store.busy, false);
      await expectLater(
        store.change((l) => l.find('one').estimate = -1),
        throwsFormatException,
      );
      expect(store.ledger.encode(), before);
    },
  );
  test(
    'real Hive restart and restore preserve records and backup images',
    () async {
      final dir = await Directory.systemTemp.createTemp('calm-store-test-');
      Hive.init(dir.path);
      try {
        var box = await Hive.openBox<String>('test_ledger');
        final store = LedgerStore(box, Ledger());
        await store.change((l) => l.items.add(item()));
        await box.close();
        box = await Hive.openBox<String>('test_ledger');
        final reopened = LedgerStore(box, Ledger.decode(box.get('ledger')!));
        expect(reopened.ledger.find('one').title, '一件外套');
        final before = reopened.ledger.encode();
        await reopened.restore(Ledger());
        expect(box.get('before_restore'), before);
        expect(reopened.ledger.items, isEmpty);
        await box.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
