import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_error.dart';
import 'design_tokens.dart';
import 'reminder.dart';
import 'task_batch.dart';
import 'voice_parser.dart';
import 'widgets/widgets.dart';

class SceneTemplate {
  final String name;
  final List<Map<String, dynamic>> items;
  const SceneTemplate(this.name, this.items);
  Map<String, dynamic> toJson() => {'name': name, 'items': items};
  List<ParsedVoice> instantiate(DateTime start, MemoStore store) => items.map((item) {
    final config = item['config'];
    final r = config is Map ? Reminder.fromJson(Map<String, dynamic>.from(config)) : store.draft();
    r.id = 0; r.text = item['text'] as String;
    r.date = start.add(Duration(minutes: item['offset'] as int));
    r.enabled = true; r.completed = false; r.archived = false;
    r.repeat = 'none'; r.days = []; r.speechSeed = 0;
    return ParsedVoice(r, true, null, start);
  }).toList();
}
const builtInScenes = [
  SceneTemplate('晚间学习', [{'text': '阅读', 'offset': 0}, {'text': '休息一下', 'offset': 30}, {'text': '复习与整理', 'offset': 40}]),
  SceneTemplate('喝水提醒', [{'text': '喝一杯水', 'offset': 0}, {'text': '喝一杯水', 'offset': 120}, {'text': '喝一杯水', 'offset': 240}, {'text': '喝一杯水', 'offset': 360}]),
  SceneTemplate('睡前整理', [{'text': '收拾物品', 'offset': 0}, {'text': '安排明天的事情', 'offset': 10}]),
];

class SceneTemplatesPage extends StatefulWidget {
  final MemoStore store;
  final EditBatchDraft edit;
  const SceneTemplatesPage({super.key, required this.store, required this.edit});
  @override State<SceneTemplatesPage> createState() => _SceneTemplatesPageState();
}
class _SceneTemplatesPageState extends State<SceneTemplatesPage> {
  List<SceneTemplate> custom = [];
  bool loading = true, busy = false;
  String? error;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final raw = await native.invokeMethod<String>('getSceneTemplates');
      final list = jsonDecode(raw ?? '[]') as List;
      final loaded = list.map((v) => SceneTemplate(v['name'] as String,
        (v['items'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList())).toList();
      if (mounted) setState(() { custom = loaded; loading = false; });
    } catch (e) { if (mounted) setState(() { loading = false; error = niceError(e); }); }
  }
  Future<void> preview(SceneTemplate scene) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final initial = DateTime.now().add(const Duration(minutes: 5));
      final start = await showMemoTimeSheet(context, initial: initial);
      if (!mounted || start == null) return;
      await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => TaskBatchPage(
        drafts: scene.instantiate(start, widget.store), source: '${scene.name} · 可逐条调整时间与设置', store: widget.store, edit: widget.edit)));
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> saveCurrent() async {
    if (busy || custom.length >= 20) return;
    final active = widget.store.reminders.where((r) => r.enabled && !r.completed && !r.archived && !r.unread).toList()
      ..sort((a, b) => a.displayDate.compareTo(b.displayDate));
    if (active.isEmpty || active.length > 10) {
      setState(() => error = '请保留 1—10 条待触发提醒后再保存为模板。'); return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('保存当前安排'), content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('将 ${active.length} 条待触发提醒保存为模板；再次使用时按新起点安排，不继承循环。'),
        TextField(controller: controller, maxLength: 30, decoration: const InputDecoration(labelText: '模板名称'))]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(onPressed: () { if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim()); }, child: const Text('保存'))]));
    // Dialog exit animation may still reference its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300)); controller.dispose();
    if (name == null || !mounted) return;
    final first = active.first.displayDate;
    final template = SceneTemplate(name, active.map((r) => <String, dynamic>{
      'text': r.text, 'offset': r.displayDate.difference(first).inMinutes, 'config': r.toJson(),
    }).toList());
    await persist([...custom, template]);
  }
  Future<void> persist(List<SceneTemplate> next) async {
    setState(() { busy = true; error = null; });
    try {
      await native.invokeMethod('saveSceneTemplates', jsonEncode(next.map((s) => s.toJson()).toList()));
      if (mounted) setState(() => custom = next);
    } catch (e) { if (mounted) setState(() => error = niceError(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('场景模板')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('把常用安排，变成一键开始。', style: context.text.title),
      const SizedBox(height: 8), const MemoHint('先选择开始时间，再核对每条提醒。不会自动重复创建。'),
      const SizedBox(height: 20),
      for (final scene in [...builtInScenes, ...custom]) Padding(padding: const EdgeInsets.only(bottom: 14), child: MemoCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.auto_awesome_outlined, color: context.colors.brand700), const SizedBox(width: 12),
            Expanded(child: Text(scene.name, style: context.text.title)),
            if (custom.contains(scene)) IconButton(tooltip: '删除模板', onPressed: busy ? null : () async {
              final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('删除此模板？'),
                content: const Text('已经创建的提醒不受影响。'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除'))]));
              if (yes == true && mounted) await persist(custom.where((s) => s != scene).toList());
            }, icon: const Icon(Icons.delete_outline))]),
          const SizedBox(height: 12),
          Text(scene.items.map((i) => '${i['offset'] == 0 ? '开始时' : '${i['offset']} 分钟后'} · ${i['text']}').join('\n'), style: context.text.body),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: busy ? null : () => preview(scene), child: Text('预览 ${scene.items.length} 条提醒')),
        ]))),
      if (loading) const LinearProgressIndicator(),
      if (error != null) Text(error!, style: context.text.body.copyWith(color: context.colors.danger)),
      OutlinedButton.icon(onPressed: busy || loading || error != null ? null : saveCurrent, icon: const Icon(Icons.add), label: const Text('保存当前安排为模板')),
      const MemoHint('自定义模板仅保存在本机，暂不包含在备忘录备份中。'),
    ]),
  );
}
