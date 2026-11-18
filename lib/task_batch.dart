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
  late final metadata = List<ParsedVoice>.of(widget.drafts);
  late final rows = widget.drafts.map((p) => p.reminder).toList();
  late final warnings = widget.drafts.map((p) => p.warning).toList();
  final done = <int>{}, excluded = <int>{};
  final listKey = GlobalKey<AnimatedListState>();
  late final rowKeys = List.generate(rows.length, (_) => GlobalKey());
  Duration get motion => MediaQuery.disableAnimationsOf(context) ? Duration.zero : MemoMotion.base;
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
    if (metadata[i].issue != null && warnings[i] != null) return warnings[i];
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
        rows[i] = updated; warnings[i] = null;
        metadata[i] = ParsedVoice(updated, updated.timeConfirmed, null, metadata[i].reference, original: metadata[i].original);
        feedback = null;
      });
    }
  }
  void resolve(int i, {bool split = false, bool previous = false}) {
    if (saving || done.isNotEmpty) return;
    final p = metadata[i];
    setState(() {
      if (split && p.alternatives.isNotEmpty) {
        final skipped = excluded.contains(i);
        final shifted = <int>{for (final n in excluded) if (n != i) n > i ? n + p.alternatives.length - 1 : n};
        excluded..clear()..addAll(shifted);
        for (var offset = 1; offset < p.alternatives.length; offset++) {
          rowKeys.insert(i + offset, GlobalKey());
          listKey.currentState!.insertItem(i + offset, duration: motion);
        }
        rows.replaceRange(i, i + 1, p.alternatives.map((p) => p.reminder));
        warnings.replaceRange(i, i + 1, p.alternatives.map((p) => p.warning));
        metadata.replaceRange(i, i + 1, p.alternatives);
        if (skipped) excluded.addAll(List.generate(p.alternatives.length, (n) => i + n));
        if (rows.length > 10) feedback = '最多创建10条，请返回减少条数。';
      } else {
        if (p.issue == VoiceIssue.relativeReference && p.relativeDelay != null) {
          rows[i].date = (previous && i > 0 ? rows[i - 1].date : p.reference).add(p.relativeDelay!);
        }
        warnings[i] = null;
        metadata[i] = ParsedVoice(rows[i], rows[i].timeConfirmed, null, p.reference, original: p.original);
      }
    });
  }
  Future<void> merge(int i) async {
    if (saving || done.isNotEmpty || i == 0) return;
    final copy = Reminder.fromJson(rows[i - 1].toJson())
      ..dateConfirmed = rows[i - 1].dateConfirmed ..timeConfirmed = rows[i - 1].timeConfirmed;
    copy.text = '${rows[i - 1].text}，${metadata[i].original ?? rows[i].text}';
    final updated = await widget.edit(context, copy);
    if (!mounted || updated == null) return;
    setState(() {
      final original = '${metadata[i - 1].original ?? rows[i - 1].text}，${metadata[i].original ?? rows[i].text}';
      final removed = rows[i].text;
      rowKeys.removeAt(i);
      listKey.currentState!.removeItem(i, (context, animation) => SizeTransition(
        sizeFactor: animation, axisAlignment: -1, child: ListTile(title: Text(removed))), duration: motion);
      rows[i - 1] = updated; rows.removeAt(i); warnings[i - 1] = null; warnings.removeAt(i);
      metadata[i - 1] = ParsedVoice(updated, updated.timeConfirmed, null, metadata[i - 1].reference, original: original);
      metadata.removeAt(i);
      final shifted = <int>{for (final n in excluded) if (n != i) n > i ? n - 1 : n};
      excluded..clear()..addAll(shifted); feedback = null;
    });
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
    if (rows.length > 10) { setState(() => feedback = '最多核对10条，请返回减少条数。'); return; }
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
  Widget draftRow(BuildContext context, int i, Animation<double> animation) {
    final row = rows[i];
    final committed = done.contains(i);
    final skipped = excluded.contains(i);
    final issue = needsStart || committed || skipped ? null : error(i);
    final previous = i == 0 ? null : rows[i - 1];
    final showDate = !needsStart && row.dateConfirmed &&
        (previous == null || !previous.dateConfirmed || !DateUtils.isSameDay(previous.date, row.date));
    final editing = !saving && !choosingStart && !needsStart && !committed;
    final canMerge = widget.voiceSource && i > 0 && done.isEmpty && !saving;
    final time = needsStart ? relativeLabel(i) : row.timeConfirmed && row.dateConfirmed ? row.time : '待补时间';
    final notes = [
      if (committed) '已创建' else if (skipped) '已跳过',
      if (row.repeat != 'none') row.repeatLabel,
      if (row.speechMode == 'on') '语音开启',
      if (row.speechMode == 'off' && widget.store.defaults['speechMode'] == 'on') '语音关闭',
      if (isScene && !needsStart && !customTimes.contains(i)) relativeLabel(i),
      if (customTimes.contains(i)) '时间已单独调整',
    ];
    final repair = widget.voiceSource && issue != null && !saving && done.isEmpty;
    return SizeTransition(sizeFactor: animation, axisAlignment: -1,
      child: Column(key: rowKeys[i], crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showDate) Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text('${row.date.year}年${row.date.month}月${row.date.day}日', style: context.text.caption)),
        Material(color: issue == null ? context.colors.surface : context.colors.warningSurface,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Checkbox(semanticLabel: '创建第 ${i + 1} 条', value: !skipped,
                onChanged: saving || committed ? null : (v) => setState(() {
                  if (v == true) { excluded.remove(i); } else { excluded.add(i); }
                })),
              Expanded(child: Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center,
                children: [Text(time, style: context.text.label.copyWith(color: context.colors.brand700)),
                  Text(row.text, style: context.text.subtitle)])),
              IconButton(tooltip: '编辑第 ${i + 1} 条', onPressed: editing ? () => edit(i) : null,
                icon: const Icon(Icons.edit_outlined)),
              if (canMerge) PopupMenuButton<String>(tooltip: '第 ${i + 1} 条更多操作',
                onSelected: (_) => merge(i), itemBuilder: (_) => const [
                  PopupMenuItem(value: 'merge', child: Text('与上一条合并并编辑'))]),
            ]),
            if (notes.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Wrap(spacing: 8, children: [for (final note in notes) Text(note, style: context.text.caption)])),
            if (issue != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(issue, style: context.text.label.copyWith(color: context.colors.danger)),
                if (repair && metadata[i].issue == VoiceIssue.boundary) ...[
                  Text('疑似下一条：${metadata[i].evidence ?? ""}', style: context.text.body),
                  Wrap(children: [
                    TextButton(onPressed: () => resolve(i), child: const Text('保留一条')),
                    OutlinedButton(onPressed: rows.length - 1 + metadata[i].alternatives.length > 10
                      ? null : () => resolve(i, split: true), child: const Text('拆成两条')),
                  ]),
                ],
                if (repair && metadata[i].issue == VoiceIssue.relativeReference) Wrap(children: [
                  TextButton(onPressed: () => resolve(i), child: const Text('从录音时刻起算')),
                  if (metadata[i].previousTime != null) OutlinedButton(onPressed: () => resolve(i, previous: true),
                    child: const Text('从上一条计划时间起算')),
                ]),
              ])),
          ]))),
        Divider(height: 1, color: context.colors.line),
      ]));
  }

  @override Widget build(BuildContext context) {
    final selection = selected;
    final unresolved = needsStart ? <int>[] : selection.where((i) => error(i) != null).toList();
    return PopScope(canPop: !saving, child: Scaffold(
    appBar: AppBar(title: Text(widget.sceneName ?? '核对 ${rows.length} 条提醒', maxLines: 1, overflow: TextOverflow.ellipsis)),
    body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(needsStart ? '先看安排，再选择开始时间'
        : widget.voiceSource && rows.length == 1 ? '仅识别到 1 条，请核对' : '逐条核对后，再一起创建', style: context.text.title),
      const SizedBox(height: 8),
      Text(needsStart ? '共 ${rows.length} 条提醒。先预览相对安排，选择开始时间后可逐条编辑。'
        : widget.voiceSource && rows.length == 1 ? '可说“下一条”分开任务；正文中的时间会保留，请核对。' : '点铅笔单独调整时间、正文和提醒方式；取消勾选即可跳过。',
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
      AnimatedList(key: listKey, primary: false, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero, initialItemCount: rows.length, itemBuilder: draftRow),
    ])),
    bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (feedback != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(feedback!, style: context.text.caption.copyWith(color: context.colors.danger))),
      if (unresolved.isNotEmpty) TextButton.icon(icon: const Icon(Icons.rule_rounded),
        label: Text('${selection.length} 条已选，${unresolved.length} 条待核对'),
        onPressed: saving ? null : () {
          final target = rowKeys[unresolved.first].currentContext;
          if (target != null) Scrollable.ensureVisible(target, alignment: .2, duration: motion);
        }),
      FilledButton(onPressed: saving || choosingStart ? null : needsStart ? chooseStart
        : selection.isEmpty || unresolved.isNotEmpty ? null : save,
        child: Text(saving ? '正在创建…' : needsStart ? '选择开始时间' : '创建 ${selection.length} 条提醒')),
      Wrap(alignment: WrapAlignment.center, spacing: 16, children: [
        if (widget.voiceSource && done.isEmpty) TextButton(onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('返回修改原话')),
        TextButton(onPressed: saving ? null : () => Navigator.pop(context, done.isNotEmpty),
          child: Text(done.isEmpty ? '取消' : '返回，保留已创建的提醒')),
      ]),
    ]))),
  ));
  }
}
