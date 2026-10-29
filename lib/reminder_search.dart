import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'reminder.dart';
import 'widgets/widgets.dart';

/// Full-screen search over every reminder, including finished ones.
///
/// It runs on the in-memory list, so there is no query round-trip and no
/// debounce: at a few hundred reminders a substring scan per keystroke stays
/// well inside a frame. Results are ordered by "still actionable" first, then
/// by time, which is what people are actually looking for.
class ReminderSearchPage extends StatefulWidget {
  final List<Reminder> reminders;
  const ReminderSearchPage({super.key, required this.reminders});

  @override State<ReminderSearchPage> createState() => _ReminderSearchPageState();
}

class _ReminderSearchPageState extends State<ReminderSearchPage> {
  String query = '';

  static String _date(DateTime d) => '${d.month}月${d.day}日';

  bool _hit(Reminder r) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    final haystack = [
      r.text,
      r.time,
      '${r.date.year}-${r.date.month}-${r.date.day}',
      _date(r.date),
      if (r.repeat != 'none') r.repeatLabel,
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  List<Reminder> get results {
    final list = widget.reminders.where(_hit).toList()
      ..sort((a, b) {
        final aDone = a.completed || a.archived, bDone = b.completed || b.archived;
        if (aDone != bDone) return aDone ? 1 : -1;
        return a.displayDate.compareTo(b.displayDate);
      });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final found = results;
    return Scaffold(
      appBar: AppBar(title: const Text('搜索提醒')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: MemoSearchField(
            hint: '搜索内容、日期或重复规则',
            showClear: query.isNotEmpty,
            onChanged: (v) => setState(() => query = v),
            onClear: () => setState(() => query = ''),
          ),
        ),
        Expanded(child: switch ((query.trim().isEmpty, found.isEmpty)) {
          (true, _) => const MemoEmptyState(icon: Icons.search_rounded, title: '输入关键词开始搜索',
            subtitle: '可以搜提醒内容、日期，或“每周”“每天”这类重复规则'),
          (_, true) => MemoEmptyState(icon: Icons.search_off_rounded, title: '没有找到相关提醒',
            subtitle: '试试更短的关键词，或换一个日期'),
          _ => ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            itemCount: found.length,
            itemBuilder: (_, i) {
              final r = found[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MemoCard(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  onTap: () => Navigator.pop(context, r),
                  child: Row(children: [
                    SizedBox(width: 54, child: Text(r.time, style: context.text.cardTime.copyWith(fontSize: 20))),
                    const SizedBox(width: MemoSpace.sm),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.cardTitle),
                      const SizedBox(height: 4),
                      Text([
                        _date(r.date),
                        if (r.repeat != 'none') r.repeatLabel,
                        if (r.completed) '已完成',
                        if (r.archived && !r.completed) '已归档',
                      ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.caption),
                    ])),
                     Icon(Icons.chevron_right_rounded, color: context.colors.muted, size: 20),
                  ]),
                ),
              );
            }),
        }),
      ]),
    );
  }
}
