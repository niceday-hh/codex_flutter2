import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'reminder.dart';
import 'widgets/widgets.dart';

class TaskLibraryPage extends StatefulWidget {
  final MemoStore store;
  final Widget Function(Reminder) card;
  const TaskLibraryPage({super.key, required this.store, required this.card});
  @override State<TaskLibraryPage> createState() => _TaskLibraryPageState();
}

class _TaskLibraryPageState extends State<TaskLibraryPage> {
  String query = '';
  int collectedAt(Reminder r) => (r.archived ? r.archivedAt : r.lastAck) > 0
    ? (r.archived ? r.archivedAt : r.lastAck) : r.date.millisecondsSinceEpoch;
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('历史任务')),
    body: AnimatedBuilder(animation: widget.store, builder: (_, child) {
      final rows = widget.store.reminders.where((r) =>
        (r.archived || r.completed) && r.text.toLowerCase().contains(query.toLowerCase())).toList()
        ..sort((a, b) => collectedAt(b).compareTo(collectedAt(a)));
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: MemoSearchField(hint: '搜索任务内容', onChanged: (s) => setState(() => query = s.trim()))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Align(alignment: Alignment.centerLeft,
            child: MemoHint('${rows.length} 条 · 已停止提醒，内容保留；可编辑后复用'))),
        Expanded(child: rows.isEmpty
          ? const Center(child: MemoEmptyState(icon: Icons.inbox_rounded, title: '还没有匹配的记录',
              subtitle: '完成或主动保留的任务会收纳到这里'))
          : ListView.builder(
            padding: const EdgeInsets.only(top: 4),
            itemCount: rows.length, itemBuilder: (_, i) {
            final r = rows[i];
            final previous = i == 0 ? null : DateTime.fromMillisecondsSinceEpoch(collectedAt(rows[i - 1]));
            final date = DateTime.fromMillisecondsSinceEpoch(collectedAt(r));
            final heading = previous == null || previous.year != date.year || previous.month != date.month || previous.day != date.day;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (heading) Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
                child: Text('${date.year}年${date.month}月${date.day}日',
                  style: context.text.overline.copyWith(color: context.colors.inkSoft))),
              widget.card(r),
            ]);
          })),
      ]);
    }),
  );
}
