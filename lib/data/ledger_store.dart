import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/ledger.dart';

/// Adapted from upstream ExpenseLocalDataSource's Hive init and awaited writes.
/// A single snapshot keeps purchase/month transitions atomic.
class LedgerStore extends ChangeNotifier {
  LedgerStore(this._box, this.ledger);
  final Box<String>? _box;
  Ledger ledger;
  bool busy = false;
  static Future<LedgerStore> open() async {
    await Hive.initFlutter();
    final box = await Hive.openBox<String>('calm_shopping_v1');
    final data = box.get('ledger');
    // Never use upstream's delete-and-recreate recovery: preserve data on errors.
    return LedgerStore(box, data == null ? Ledger() : Ledger.decode(data));
  }

  Future<void> change(void Function(Ledger) operation) async {
    if (busy) throw StateError('正在保存，请稍候');
    busy = true;
    notifyListeners();
    try {
      final next = Ledger.decode(ledger.encode());
      operation(next);
      final encoded = next.encode();
      Ledger.decode(encoded);
      await _box?.put('ledger', encoded);
      ledger = next;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> restore(Ledger candidate) async {
    if (busy) throw StateError('正在保存，请稍候');
    busy = true;
    notifyListeners();
    try {
      final encoded = candidate.encode();
      final checked = Ledger.decode(encoded);
      await _box?.put('before_restore', ledger.encode());
      await _box?.put('ledger', encoded);
      ledger = checked;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
