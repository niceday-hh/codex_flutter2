import 'dart:async';
import 'package:flutter/material.dart';
import 'design_tokens.dart';
import 'widgets/widgets.dart';

import 'settings_catalog.dart';
export 'settings_catalog.dart';

class SettingsPage extends StatefulWidget {
  final Future<void> Function(SettingsSection, {SettingsEntry? target}) onOpen;
  final String Function(SettingsEntry) currentValue;
  final String version;
  const SettingsPage({super.key, required this.onOpen, required this.version, required this.currentValue});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final search = TextEditingController();
  bool _previewing = false;
  @override void dispose() { search.dispose(); super.dispose(); }

  Widget _group(List<SettingsSection> sections) => MemoCard(shadow: false, padding: EdgeInsets.zero,
    child: Column(children: [for (var i = 0; i < sections.length; i++) ...[
      if (i > 0)  Divider(height: 1, indent: 76, endIndent: 18, color: context.colors.line),
      ListTile(key: ValueKey('settings-${sections[i].category.name}'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MemoRadius.xl)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(width: 40, height: 40,
          decoration: BoxDecoration(color: context.colors.brand100, borderRadius: BorderRadius.circular(MemoRadius.md)),
          child: Icon(sections[i].icon, color: context.colors.brand500, size: 22)),
        title: Text(sections[i].title, style: context.text.subtitle.copyWith(fontSize: 16)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 3), child: Text(sections[i].subtitle,
          style: context.text.caption.copyWith(height: 1.5))),
        trailing:  Icon(Icons.chevron_right_rounded, color: context.colors.muted, size: 20),
        onTap: () { FocusScope.of(context).unfocus(); widget.onOpen(sections[i]); }),
    ]]));

  Widget _label(String title) => Padding(padding: const EdgeInsets.fromLTRB(4, MemoSpace.xxl, 4, MemoSpace.sm),
    child: Text(title, style: context.text.overline));

  Future<void> _preview(SettingsEntry entry) async {
    if (_previewing) return;
    _previewing = true; FocusScope.of(context).unfocus();
    bool? open;
    try {
      open = await showDialog<bool>(context: context, builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias, backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MemoRadius.xxl)),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 440, maxHeight: MediaQuery.sizeOf(context).height * .8),
          child: SingleChildScrollView(padding: const EdgeInsets.all(MemoSpace.xxl), child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(entry.section.title, style: context.text.overline.copyWith(color: context.colors.brand700)),
              const SizedBox(height: MemoSpace.md),
              Text(entry.title, style: context.text.title),
              const SizedBox(height: MemoSpace.lg),
              Container(padding: const EdgeInsets.all(MemoSpace.lg),
                decoration: BoxDecoration(color: context.colors.brand100, borderRadius: BorderRadius.circular(MemoRadius.md)),
                child: Text('当前：${widget.currentValue(entry)}', style: context.text.subtitle.copyWith(color: context.colors.brand800))),
              const SizedBox(height: MemoSpace.lg),
              Text(entry.description, style: context.text.body.copyWith(color: context.colors.muted, height: 1.6)),
              const SizedBox(height: MemoSpace.xxl),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('前往设置')),
              TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text('关闭预览', style: context.text.subtitle.copyWith(color: context.colors.muted))),
            ])))));
    } finally { _previewing = false; }
    if (mounted && open == true) await widget.onOpen(entry.section, target: entry);
  }

  Widget _result(SettingsEntry entry) => Padding(padding: const EdgeInsets.only(bottom: 10),
    child: MemoCard(key: ValueKey('settings-result-${entry.id}'), shadow: false, padding: EdgeInsets.zero, radius: MemoRadius.lg,
      onTap: () => _preview(entry),
      child: Padding(padding: const EdgeInsets.all(MemoSpace.lg), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(entry.title, style: context.text.subtitle.copyWith(fontSize: 16))),
             Icon(Icons.preview_outlined, color: context.colors.brand500, size: 20),
          ]),
          const SizedBox(height: 6),
          Text('${entry.section.title} · 当前：${widget.currentValue(entry)}',
            style: context.text.caption.copyWith(color: context.colors.brand700)),
          const SizedBox(height: 4),
          Text(entry.description, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: context.text.caption.copyWith(height: 1.5)),
        ]))));

  @override Widget build(BuildContext context) {
    final query = search.text.trim();
    final matches = settingsEntries.where((s) => s.matches(query)).toList();
    return ListView(key: const PageStorageKey('settings-overview'),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24), children: [
      Text('设置', style: context.text.display), const SizedBox(height: 6),
      Text('让提醒，更适合你。', style: context.text.body.copyWith(color: context.colors.muted)),
      const SizedBox(height: MemoSpace.xxl),
      MemoSearchField(fieldKey: const ValueKey('settings-search'), controller: search, hint: '搜索设置',
        onChanged: (_) => setState(() {}), showClear: query.isNotEmpty,
        onClear: () { search.clear(); setState(() {}); }),
      if (query.isEmpty) ...[
        _label('偏好设置'), _group(settingsSections.take(5).toList()),
        _label('管理与支持'), _group(settingsSections.skip(5).toList()),
      ] else ...[
        _label('搜索结果 · ${matches.length} 个子项 · 点击预览'),
        if (matches.isNotEmpty) ...matches.map(_result)
        else const MemoEmptyState(icon: Icons.search_off_rounded, title: '没有找到相关设置',
          subtitle: '试试“铃声”“语音”或“振动”'),
      ],
      const SizedBox(height: MemoSpace.xxl),
      Text('超级提醒 · ${widget.version}', textAlign: TextAlign.center, style: context.text.caption),
    ]);
  }
}

class SettingsSheet extends StatefulWidget {
  final SettingsSection section;
  final Listenable changes;
  final List<Widget> Function(BuildContext) items;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final GlobalKey? targetKey;
  final SettingsEntry? target;
  const SettingsSheet({super.key, required this.section, required this.changes, required this.items,
    required this.messengerKey, this.targetKey, this.target});
  @override State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final controller = ScrollController();
  @override void initState() {
    super.initState();
    if (widget.targetKey != null) WidgetsBinding.instance.addPostFrameCallback((_) { unawaited(_reveal()); });
  }
  Future<void> _reveal() async {
    if (!mounted) return;
    if (widget.targetKey?.currentContext == null && controller.hasClients) {
      controller.jumpTo(controller.position.maxScrollExtent);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    final target = widget.targetKey?.currentContext;
    if (target != null && target.mounted) await Scrollable.ensureVisible(target, alignment: .15);
  }
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => FractionallySizedBox(heightFactor: .92,
    child: RepaintBoundary(child: MemoSheetShell(
      title: widget.section.title,
      hint: widget.target == null ? null : '已定位：${widget.target!.title}',
      onClose: () { if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context); },
      child: ScaffoldMessenger(key: widget.messengerKey, child: Scaffold(backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false, body: AnimatedBuilder(animation: widget.changes, builder: (context, _) => ListView(
          key: ValueKey('settings-sheet-${widget.section.category.name}'), controller: controller,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 28), children: widget.items(context)))),
    ))));
}

class SettingsActionTile extends StatefulWidget {
  final IconData icon;
  final String title, value;
  final Future<void> Function() action;
  final bool highlighted;
  const SettingsActionTile({super.key, required this.icon, required this.title, required this.value,
    required this.action, this.highlighted = false});
  @override State<SettingsActionTile> createState() => _SettingsActionTileState();
}
class _SettingsActionTileState extends State<SettingsActionTile> {
  bool busy = false;
  Future<void> _run() async {
    if (busy) return;
    setState(() => busy = true);
    try { await widget.action(); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Material(
    color: widget.highlighted ? context.colors.brand50 : Colors.transparent,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(widget.icon, color: context.colors.brand500, size: 22),
      title: Text(widget.title, style: context.text.body.copyWith(fontWeight: FontWeight.w500)),
      subtitle: widget.value.isEmpty ? null : Padding(padding: const EdgeInsets.only(top: 3),
        child: Text(widget.value, style: context.text.caption.copyWith(height: 1.45))),
      trailing: busy
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        :  Icon(Icons.chevron_right_rounded, color: context.colors.muted, size: 20),
      onTap: busy ? null : _run));
}
