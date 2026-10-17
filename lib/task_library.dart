import 'package:flutter/material.dart';
import 'reminder.dart';

class TaskLibraryPage extends StatefulWidget {
  final MemoStore store;
  final bool initialArchived;
  final Widget Function(Reminder) card;
  const TaskLibraryPage({super.key, required this.store, required this.card, this.initialArchived = false});
  @override State<TaskLibraryPage> createState() => _TaskLibraryPageState();
}

class _TaskLibraryPageState extends State<TaskLibraryPage> {
  late bool archived = widget.initialArchived;
  String query = '';
  int collectedAt(Reminder r) => (r.archived ? r.archivedAt : r.lastAck) > 0
    ? (r.archived ? r.archivedAt : r.lastAck) : r.date.millisecondsSinceEpoch;
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('任务收纳')),
    body: AnimatedBuilder(animation: widget.store, builder: (_, child) {
      final rows = widget.store.reminders.where((r) =>
        (archived ? r.archived : r.completed && !r.archived) && r.text.toLowerCase().contains(query.toLowerCase())).toList()
        ..sort((a, b) => collectedAt(b).compareTo(collectedAt(a)));
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: TextField(
          decoration: const InputDecoration(hintText: '搜索任务内容', prefixIcon: Icon(Icons.search)),
          onChanged: (s) => setState(() => query = s.trim()))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ChoiceChip(label: const Text('已完成'), selected: !archived, onSelected: (_) => setState(() => archived = false)),
          const SizedBox(width: 12), ChoiceChip(label: const Text('已归档'), selected: archived, onSelected: (_) => setState(() => archived = true)),
        ]),
        Padding(padding: const EdgeInsets.all(12), child: Text('${rows.length} 条 · ${archived ? '已停止提醒，内容保留，可编辑后复用' : '已自动收起，按完成日期排列'}',
          style: const TextStyle(color: Color(0xFF8A859C), fontSize: 12))),
        Expanded(child: rows.isEmpty ? const Center(child: Text('还没有匹配的记录')) : ListView.builder(
          itemCount: rows.length, itemBuilder: (_, i) {
            final r = rows[i];
            final previous = i == 0 ? null : DateTime.fromMillisecondsSinceEpoch(collectedAt(rows[i - 1]));
            final date = DateTime.fromMillisecondsSinceEpoch(collectedAt(r));
            final heading = previous == null || previous.year != date.year || previous.month != date.month || previous.day != date.day;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (heading) Padding(padding: const EdgeInsets.fromLTRB(24, 18, 24, 12), child: Text('${date.year}年${date.month}月${date.day}日', style: const TextStyle(fontWeight: FontWeight.w600))),
              widget.card(r),
            ]);
          })),
      ]);
    }),
  );
}
