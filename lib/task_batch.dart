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
  final bool voiceSource;
  final String? sceneName;
  final List<int>? sceneOffsets;
  const TaskBatchPage({super.key, required this.drafts, required this.source, required this.store, required this.edit,
    this.voiceSource = false, this.sceneName, this.sceneOffsets})
    : assert((sceneName == null) == (sceneOffsets == null)),
      assert(sceneOffsets == null || sceneOffsets.length == drafts.length);
  @override State<TaskBatchPage> createState() => _TaskBatchPageState();
}
class _TaskBatchPageState extends State<TaskBatchPage> {
  late final rows = widget.drafts.map((p) => p.reminder).toList();
  late final warnings = widget.drafts.map((p) => p.warning).toList();
  final done = <int>{}, excluded = <int>{};
  final customTimes = <int>{};
  DateTime? sceneStart;
  bool saving = false, choosingStart = false;
  bool get isScene => widget.sceneOffsets != null;
  bool get needsStart => isScene && sceneStart == null;
  String relativeLabel(int i) {
    final offset = widget.sceneOffsets![i];
    return offset == 0 ? '开始时' : '$offset 分钟后';
  }
  String? feedback;
  List<int> get selected => [for (var i = 0; i < rows.length; i++) if (!done.contains(i) && !excluded.contains(i)) i];
  String? error(int i) {
    if (needsStart) return '请先选择开始时间';
    final r = rows[i];
    if (!r.dateConfirmed || !r.timeConfirmed) return '请确认日期与时间';
    if (r.text.trim().isEmpty) return '请填写提醒内容';
    if (r.repeat == 'none' && !r.date.isAfter(DateTime.now())) return '时间已过，请修改';
    return warnings[i];
  }
  Future<void> edit(int i) async {
    if (saving || choosingStart || needsStart || done.contains(i)) return;
    final copy = Reminder.fromJson(rows[i].toJson())
      ..dateConfirmed = rows[i].dateConfirmed ..timeConfirmed = rows[i].timeConfirmed;
    final updated = await widget.edit(context, copy);
    if (updated != null && mounted) {
      setState(() {
        if (isScene && updated.date.millisecondsSinceEpoch != rows[i].date.millisecondsSinceEpoch) { customTimes.add(i); }
        rows[i] = updated; warnings[i] = null; feedback = null;
      });
    }
  }
  Future<void> chooseStart() async {
    if (!isScene || saving || choosingStart || done.isNotEmpty) return;
    setState(() => choosingStart = true);
    try {
      final now = DateTime.now();
      final suggested = now.add(const Duration(minutes: 5));
      final initial = sceneStart != null && sceneStart!.isAfter(now) ? sceneStart!
        : DateTime(suggested.year, suggested.month, suggested.day, suggested.hour, suggested.minute);
      final start = await showMemoTimeSheet(context, initial: initial, title: '设置场景开始时间');
      if (!mounted || start == null) return;
      setState(() {
        sceneStart = start; feedback = null;
        for (var i = 0; i < rows.length; i++) {
          if (customTimes.contains(i) || done.contains(i)) { continue; }
          rows[i].date = start.add(Duration(minutes: widget.sceneOffsets![i]));
          rows[i].dateConfirmed = true; rows[i].timeConfirmed = true;
        }
      });
    } finally { if (mounted) setState(() => choosingStart = false); }
  }
  Future<void> save() async {
    if (saving || choosingStart || needsStart || selected.isEmpty) return;
    final selection = selected;
    if (selection.any((i) => error(i) != null)) {
      setState(() => feedback = '请先编辑标注的提醒，或取消勾选。'); return;
    }
    setState(() { saving = true; feedback = null; });
    try {
      await native.invokeMethod('requestNotifications');
      for (final i in selection) {
        if (error(i) != null) throw StateError('确认期间时间已到，请修改剩余提醒');
        if (rows[i].id == 0) {
          final id = await native.invokeMethod<int>('reserveReminderId');
          if (id == null || id <= 0) throw StateError('无法准备提醒，请重试');
          rows[i].id = id;
        }
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
    appBar: AppBar(title: Text(widget.sceneName ?? '核对 ${rows.length} 条提醒', maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text(needsStart ? '先看安排，再选择开始时间'
        : widget.voiceSource && rows.length == 1 ? '仅识别到 1 条，请核对' : '逐条核对后，再一起创建', style: context.text.title),
      const SizedBox(height: 8),
      Text(needsStart ? '共 ${rows.length} 条提醒。先预览相对安排，选择开始时间后可逐条编辑。'
        : widget.voiceSource && rows.length == 1 ? '如需多条，请返回修改原话，为每件事补充时间。' : '点铅笔单独调整时间、正文和提醒方式；取消勾选即可跳过。',
        style: context.text.caption.copyWith(color: context.colors.muted)),
      const SizedBox(height: 12),
      if (isScene) ...[
        MemoCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(key: const ValueKey('scene-start-time'), contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.schedule_outlined, color: context.colors.brand700),
            title: Text('开始时间', style: context.text.label),
            subtitle: Text(sceneStart == null ? '未设置 · 选择时间' : memoTimeLabel(sceneStart!),
              style: context.text.body.copyWith(color: context.colors.brand700)),
            trailing: const Icon(Icons.chevron_right),
            onTap: saving || choosingStart || done.isNotEmpty ? null : chooseStart),
          Text(done.isNotEmpty ? '已有提醒创建，可单独调整剩余条目。'
            : needsStart ? '选择后将显示每条提醒的实际日期和时刻。' : '更改开始时间时，已单独调整的时间会保留。',
            style: context.text.caption.copyWith(color: context.colors.muted)),
        ])),
      ] else ExpansionTile(key: const ValueKey('batch-source'), tilePadding: EdgeInsets.zero,
        title: Text('查看原始内容', style: context.text.label),
        children: [Padding(padding: const EdgeInsets.only(bottom: 12), child: Align(alignment: Alignment.centerLeft,
          child: Text(widget.source, style: context.text.body)))]),
      const SizedBox(height: 16),
      for (var i = 0; i < rows.length; i++) Padding(padding: const EdgeInsets.only(bottom: 12), child: MemoCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Text('${i + 1}'.padLeft(2, '0'), style: context.text.label.copyWith(color: context.colors.muted)),
            const SizedBox(width: 8), Expanded(child: Text(done.contains(i) ? '已创建' : excluded.contains(i) ? '已跳过' : needsStart ? '待设时间' : '待创建', style: context.text.caption)),
            Checkbox(semanticLabel: '创建第 ${i + 1} 条', value: !excluded.contains(i), onChanged: saving || done.contains(i) ? null : (value) => setState(() {
            if (value == true) { excluded.remove(i); } else { excluded.add(i); }
          })),
            IconButton(tooltip: '编辑第 ${i + 1} 条', onPressed: saving || choosingStart || needsStart || done.contains(i) ? null : () => edit(i), icon: const Icon(Icons.edit_outlined))]),
          if (isScene && !needsStart) Text(relativeLabel(i), style: context.text.caption.copyWith(color: context.colors.muted)),
          Text(needsStart ? relativeLabel(i) : '${rows[i].date.year}/${rows[i].date.month}/${rows[i].date.day}  ${rows[i].time}',
            style: context.text.label.copyWith(color: context.colors.brand700)),
          const SizedBox(height: 8),
          Text(rows[i].text, style: context.text.title),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [MemoTag(rows[i].repeatLabel),
            MemoTag(rows[i].speechMode == 'on' ? '语音开启' : rows[i].speechMode == 'off' ? '语音关闭' : '语音跟随默认'),
            if (customTimes.contains(i)) const MemoTag('时间已单独调整'),
            if (done.contains(i)) const MemoTag('已创建')]),
          if (!needsStart && !done.contains(i) && error(i) != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(error(i)!, style: context.text.caption.copyWith(color: context.colors.danger))),
        ]))),
    ]),
    bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (feedback != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(feedback!, style: context.text.caption.copyWith(color: context.colors.danger))),
      FilledButton(onPressed: saving || choosingStart || needsStart || selected.isEmpty ? null : save,
        child: Text(saving ? '正在创建…' : needsStart ? '请先选择开始时间' : '创建 ${selected.length} 条提醒')),
      if (widget.voiceSource && done.isEmpty) TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('返回修改原话')),
      TextButton(onPressed: saving ? null : () => Navigator.pop(context, done.isNotEmpty), child: Text(done.isEmpty ? '取消' : '返回，保留已创建的提醒')),
    ]))),
  ));
}
