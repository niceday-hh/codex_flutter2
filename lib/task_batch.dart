import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_error.dart';
import 'design_tokens.dart';
import 'reminder.dart';
import 'speech.dart';
import 'voice_parser.dart';
import 'widgets/widgets.dart';

typedef EditBatchDraft = Future<Reminder?> Function(BuildContext, Reminder);

class TaskBatchPage extends StatefulWidget {
  final List<ParsedVoice> drafts;
  final String source;
  final MemoStore store;
  final EditBatchDraft edit;
  const TaskBatchPage({super.key, required this.drafts, required this.source, required this.store, required this.edit});
  @override State<TaskBatchPage> createState() => _TaskBatchPageState();
}
class _TaskBatchPageState extends State<TaskBatchPage> {
  late final rows = widget.drafts.map((p) => p.reminder).toList();
  late final warnings = widget.drafts.map((p) => p.warning).toList();
  final done = <int>{}, excluded = <int>{};
  bool saving = false;
  String? feedback;
  List<int> get selected => [for (var i = 0; i < rows.length; i++) if (!done.contains(i) && !excluded.contains(i)) i];
  String? error(int i) {
    final r = rows[i];
    if (!r.dateConfirmed || !r.timeConfirmed) return '请确认日期与时间';
    if (r.text.trim().isEmpty) return '请填写提醒内容';
    if (r.repeat == 'none' && !r.date.isAfter(DateTime.now())) return '时间已过，请修改';
    return warnings[i];
  }
  Future<void> edit(int i) async {
    final copy = Reminder.fromJson(rows[i].toJson())
      ..dateConfirmed = rows[i].dateConfirmed ..timeConfirmed = rows[i].timeConfirmed;
    final updated = await widget.edit(context, copy);
    if (updated != null && mounted) setState(() { rows[i] = updated; warnings[i] = null; feedback = null; });
  }
  Future<void> save() async {
    if (saving || selected.isEmpty) return;
    final selection = selected;
    if (selection.any((i) => error(i) != null)) {
      setState(() => feedback = '请先编辑标注的提醒，或取消勾选。'); return;
    }
    setState(() { saving = true; feedback = null; });
    try {
      await native.invokeMethod('requestNotifications');
      for (final i in selection) {
        if (error(i) != null) throw StateError('确认期间时间已到，请修改剩余提醒');
        await native.invokeMethod('save', jsonEncode(rows[i].toJson()));
        // Mark committed before any refresh/TTS call can fail. Retry only unsaved rows.
        if (mounted) setState(() => done.add(i));
      }
      unawaitedPrepare();
      try { await widget.store.load(); } catch (_) {}
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      unawaitedPrepare();
      if (mounted) setState(() { saving = false; feedback = '已创建 ${done.length} 条。${niceError(e)}；可继续创建剩余项。'; });
    }
  }
  void unawaitedPrepare() { speech.preparePending().catchError((Object _) {}); }
  @override Widget build(BuildContext context) => PopScope(canPop: !saving, child: Scaffold(
    appBar: AppBar(title: Text('核对 ${rows.length} 条提醒')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('逐条核对后，再一起创建', style: context.text.title),
      const SizedBox(height: 12),
      MemoCard(child: Text(widget.source, style: context.text.body)),
      const SizedBox(height: 16),
      for (var i = 0; i < rows.length; i++) Padding(padding: const EdgeInsets.only(bottom: 12), child: MemoCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Checkbox(value: !excluded.contains(i), onChanged: saving || done.contains(i) ? null : (value) => setState(() {
            if (value == true) { excluded.remove(i); } else { excluded.add(i); }
          })), Expanded(child: Text('${rows[i].date.year}/${rows[i].date.month}/${rows[i].date.day}  ${rows[i].time}',
            style: context.text.label.copyWith(color: context.colors.brand700))),
            IconButton(tooltip: '编辑第 ${i + 1} 条', onPressed: saving || done.contains(i) ? null : () => edit(i), icon: const Icon(Icons.edit_outlined))]),
          Text(rows[i].text, style: context.text.title),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [MemoTag(rows[i].repeatLabel),
            MemoTag(rows[i].speechMode == 'on' ? '语音开启' : rows[i].speechMode == 'off' ? '语音关闭' : '语音跟随默认'),
            if (done.contains(i)) const MemoTag('已创建')]),
          if (!done.contains(i) && error(i) != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(error(i)!, style: context.text.caption.copyWith(color: context.colors.danger))),
        ]))),
      if (feedback != null) Text(feedback!, style: context.text.body.copyWith(color: context.colors.danger)),
      const SizedBox(height: 16),
      FilledButton(onPressed: saving || selected.isEmpty ? null : save,
        child: Text(saving ? '正在创建…' : '创建 ${selected.length} 条提醒')),
      TextButton(onPressed: saving ? null : () => Navigator.pop(context, done.isNotEmpty), child: Text(done.isEmpty ? '取消' : '返回，保留已创建的提醒')),
    ]),
  ));
}
