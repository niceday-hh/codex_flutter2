import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_style.dart';
import 'design_tokens.dart';
import 'reminder.dart';
import 'widgets/widgets.dart';

class TaskLibraryPage extends StatefulWidget {
  final MemoStore store;

  /// The row builder is the home screen's, so a history row looks and behaves
  /// exactly like a live one. It takes the page's own selection because the
  /// builder belongs to the home state: letting it read a captured set was the
  /// reason long-press in here never repainted a checkbox.
  final Widget Function(Reminder, MemoSelection) card;

  const TaskLibraryPage({super.key, required this.store, required this.card});
  @override State<TaskLibraryPage> createState() => _TaskLibraryPageState();
}

class _TaskLibraryPageState extends State<TaskLibraryPage> {
  String query = '';

  /// 0 all, 1 done, 2 archived. A view of the same list, not a new route —
  /// which is why it is a segmented control and not a second tab bar.
  int filter = 0;
  final MemoSelection _selection = MemoSelection();

  int collectedAt(Reminder r) => (r.archived ? r.archivedAt : r.lastAck) > 0
    ? (r.archived ? r.archivedAt : r.lastAck) : r.date.millisecondsSinceEpoch;

  @override void initState() {
    super.initState();
    _selection.addListener(_selectionChanged);
  }

  @override void dispose() {
    _selection.removeListener(_selectionChanged);
    _selection.dispose();
    super.dispose();
  }

  void _selectionChanged() { if (mounted) setState(() {}); }

  Future<void> _deletePicked() async {
    final ids = [..._selection.ids];
    if (ids.isEmpty) return;
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('删除 ${ids.length} 条历史任务？'),
      content: const Text('这些记录会从历史中移除，操作不可撤销。'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除'))]));
    if (yes != true) return;
    HapticFeedback.mediumImpact();
    _selection.clear();
    try {
      await widget.store.deleteAll(ids);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(memoSnackBar('已删除 ${ids.length} 条'));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(memoSnackBar('删除失败，请重试', error: true));
    }
  }

  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (_, child) {
      final rows = widget.store.reminders.where((r) {
        if (!r.archived && !r.completed) return false;
        if (filter == 1 && r.archived) return false;
        if (filter == 2 && !r.archived) return false;
        return r.text.toLowerCase().contains(query.toLowerCase());
      }).toList()..sort((a, b) => collectedAt(b).compareTo(collectedAt(a)));
      final total = widget.store.reminders.where((r) => r.archived || r.completed).length;
      final selecting = _selection.active;
      final allPicked = rows.isNotEmpty && _selection.length == rows.length;
      return Scaffold(
        appBar: selecting ? AppBar(
          // The bar *is* the batch surface: it names the count, offers
          // select-all, and holds the one destructive verb. Before this, the
          // only way to reach those controls was to back out to the home tab,
          // which is a different screen with a different set.
          leading: IconButton(tooltip: '取消选择', icon: const Icon(Icons.close_rounded),
            onPressed: _selection.clear),
          title: Text('已选 ${_selection.length} 条'),
          actions: [
            IconButton(tooltip: allPicked ? '取消全选' : '全选', onPressed: () =>
              allPicked ? _selection.clear() : _selection.setAll(rows.map((r) => r.id)),
              icon: Icon(allPicked ? Icons.deselect_rounded : Icons.select_all_rounded)),
            IconButton(tooltip: '删除所选', onPressed: _deletePicked,
              icon: Icon(Icons.delete_outline_rounded, color: context.colors.danger)),
            const SizedBox(width: 4),
          ],
        ) : AppBar(
          backgroundColor: context.colors.canvas, surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0, centerTitle: false,
          title: Text('历史任务', style: context.text.title),
          titleSpacing: 4,
        ),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: MemoSearchField(hint: '搜索任务内容', onChanged: (s) {
              _selection.clear();
              setState(() => query = s.trim());
            })),
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: MemoSegmentBar(labels: const ['全部', '已完成', '已保留'], index: filter,
              onChanged: (i) { _selection.clear(); setState(() => filter = i); })),
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Align(alignment: Alignment.centerLeft,
              child: MemoHint(selecting
                ? '长按或点击勾选；批量删除不会影响其他记录'
                : (filter == 0 ? '共 $total 条 · 已停止提醒，内容保留；可编辑后复用'
                    : '${rows.length} / $total 条 · 已停止提醒，内容保留')))),
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
                widget.card(r, _selection),
              ]);
            })),
        ]),
      );
    },
  );
}
