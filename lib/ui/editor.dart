import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../core/utils/date_utils_extension.dart';
import '../data/ledger_store.dart';
import '../domain/ledger.dart';

class WishEditor extends StatefulWidget {
  const WishEditor({
    super.key,
    required this.store,
    this.wish,
    this.direct = false,
  });
  final LedgerStore store;
  final Wish? wish;
  final bool direct;
  @override
  State<WishEditor> createState() => _WishEditorState();
}

class _WishEditorState extends State<WishEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, price, note, review;
  late DateTime date;
  String? photo;
  bool saving = false, picking = false;
  @override
  void initState() {
    super.initState();
    final w = widget.wish;
    title = TextEditingController(text: w?.title);
    price = TextEditingController(
      text: w?.estimate == null ? '' : amountText(w!.estimate!),
    );
    note = TextEditingController(text: w?.note);
    review = TextEditingController(text: w?.review);
    photo = w?.photo;
    date = w?.created ?? DateTime.now().startOfDay;
    _recoverPhoto();
  }

  Future<void> _recoverPhoto() async {
    // Android can kill the activity while its photo picker is open.
    try {
      final data = await ImagePicker().retrieveLostData();
      if (data.files?.isNotEmpty == true) await _loadPhoto(data.files!.first);
    } catch (_) {
      /* Other platforms do not have Android lost-data recovery. */
    }
  }

  @override
  void dispose() {
    title.dispose();
    price.dispose();
    note.dispose();
    review.dispose();
    super.dispose();
  }

  Future<void> _loadPhoto(XFile f) async {
    final bytes = await f.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      throw const FormatException('图片过大，请选择小于 8 MB 的图片');
    }
    if (mounted) setState(() => photo = base64Encode(bytes));
  }

  Future<void> _pick() async {
    setState(() => picking = true);
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (f != null) await _loadPhoto(f);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final estimate = parseMoney(price.text);
      await widget.store.change((l) {
        if (widget.wish != null) {
          final w = l.find(widget.wish!.id);
          w.title = title.text.trim();
          w.estimate = estimate;
          w.note = note.text.trim();
          w.photo = photo;
          w.review = review.text.trim();
          if (w.months.isNotEmpty) w.months[w.latestMonth]!.estimate = estimate;
        } else {
          final w = Wish(
            id: const Uuid().v4(),
            title: title.text.trim(),
            created: date,
            estimate: widget.direct ? null : estimate,
            photo: photo,
            note: note.text.trim(),
          );
          if (widget.direct) {
            w.purchase = Purchase(estimate!, date);
          } else {
            w.months[date.monthKey] = MonthPlan(estimate);
          }
          l.items.add(w);
        }
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.wish != null
            ? '编辑记录'
            : widget.direct
            ? '补记一笔消费'
            : '记下想买的',
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  widget.direct ? '已经花掉的钱，也可以在这里补上。' : '先记下来，让每一个想买都有全貌。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: title,
                  autofocus: false,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '例如：游戏皮肤、衣服、周末聚餐',
                  ),
                  validator: (v) => v!.trim().isEmpty ? '请写下名称' : null,
                ),
                const SizedBox(height: 14),
                if (widget.wish?.direct != true)
                  TextFormField(
                    controller: price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: widget.direct ? '实际支付金额' : '预计价格（可留空）',
                      prefixText: '¥ ',
                      helperText: widget.direct
                          ? '填写真实支付的金额'
                          : '暂不清楚就留空；不会按 0 元计入合计',
                    ),
                    validator: (v) => validatePrice(v, required: widget.direct),
                  ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(widget.direct ? '消费日期' : '添加日期'),
                  subtitle: Text(date.dateKey),
                  trailing: widget.wish == null
                      ? const Icon(Icons.edit_outlined, size: 20)
                      : null,
                  onTap: widget.wish != null
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null && mounted) {
                            setState(() => date = picked);
                          }
                        },
                ),
                const SizedBox(height: 14),
                if (photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      base64Decode(photo!),
                      height: 180,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(
                        height: 80,
                        child: Center(child: Text('图片无法显示，可以更换')),
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: picking || saving ? null : _pick,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        picking
                            ? '读取中…'
                            : photo == null
                            ? '添加图片（可选）'
                            : '更换图片',
                      ),
                    ),
                    if (photo != null)
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => setState(() => photo = null),
                        child: const Text('移除图片'),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: note,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: '给自己的备注（可选）',
                    hintText: '为什么想买？已有的东西能代替吗？',
                  ),
                ),
                if (widget.wish?.purchase != null) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: review,
                    maxLines: 3,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: '买后感受（可选）',
                      hintText: '用上了吗？满意，还是有点后悔？',
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: saving || picking ? null : _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(18),
                  ),
                  child: Text(saving ? '保存中…' : '保存记录'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String? validatePrice(String? v, {bool required = false}) {
  try {
    if (parseMoney(v ?? '') == null && required) return '请输入实际金额';
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

void toast(BuildContext context, Object message) {
  final text = message is FormatException
      ? message.message
      : message is StateError
      ? message.message
      : message.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String action = '确认',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class PurchaseDialog extends StatefulWidget {
  const PurchaseDialog({super.key, required this.wish});
  final Wish wish;
  @override
  State<PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<PurchaseDialog> {
  final form = GlobalKey<FormState>();
  final price =
      TextEditingController(); // Never prefill from the estimated price.
  late DateTime date = widget.wish.purchase?.date ?? DateTime.now().startOfDay;
  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.wish.purchase == null ? '确认已消费' : '修改实际消费'),
    content: Form(
      key: form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.wish.title),
            const SizedBox(height: 8),
            Text('原预计：${money(widget.wish.estimate)}'),
            const SizedBox(height: 20),
            TextFormField(
              controller: price,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '实际支付金额',
                prefixText: '¥ ',
              ),
              validator: (v) => validatePrice(v, required: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('购买日期'),
              subtitle: Text(date.dateKey),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: widget.wish.created,
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => date = picked);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('再想想'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, Purchase(parseMoney(price.text)!, date));
          }
        },
        child: const Text('确认金额'),
      ),
    ],
  );
}
