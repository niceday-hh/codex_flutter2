import 'dart:async';
import 'package:flutter/material.dart';
import 'app_style.dart';

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
  Widget _group(List<SettingsSection> sections) => Container(
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFEFEFF4))),
    child: Column(children: [for (var i = 0; i < sections.length; i++) ...[
      if (i > 0) const Divider(height: 1, indent: 76, endIndent: 18, color: Color(0xFFF0EFF5)),
      ListTile(key: ValueKey('settings-${sections[i].category.name}'),
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(width: 43, height: 43, decoration: BoxDecoration(color: lavender, borderRadius: BorderRadius.circular(14)),
          child: Icon(sections[i].icon, color: purple, size: 24)),
        title: Text(sections[i].title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(sections[i].subtitle,
          style: const TextStyle(color: muted, fontSize: 12, height: 1.5))),
        trailing: const Icon(Icons.chevron_right_rounded, color: muted, size: 21),
        onTap: () { FocusScope.of(context).unfocus(); widget.onOpen(sections[i]); }),
    ]]));
  Widget _label(String title) => Padding(padding: const EdgeInsets.fromLTRB(4, 26, 4, 10),
    child: Text(title, style: const TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600)));
  Future<void> _preview(SettingsEntry entry) async {
    if (_previewing) return;
    _previewing = true; FocusScope.of(context).unfocus();
    bool? open;
    try {
      open = await showDialog<bool>(context: context, builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias, backgroundColor: Colors.white,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 440, maxHeight: MediaQuery.sizeOf(context).height * .8),
          child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(entry.section.title, style: const TextStyle(color: purple, fontSize: 12)),
              const SizedBox(height: 12), Text(entry.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18), Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: lavender, borderRadius: BorderRadius.circular(16)),
                child: Text('当前：${widget.currentValue(entry)}', style: const TextStyle(color: ink, fontWeight: FontWeight.w600))),
              const SizedBox(height: 18), Text(entry.description, style: const TextStyle(color: muted, height: 1.6)),
              const SizedBox(height: 24), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('前往设置')),
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('关闭预览')),
            ])))));
    } finally { _previewing = false; }
    if (mounted && open == true) await widget.onOpen(entry.section, target: entry);
  }
  Widget _result(SettingsEntry entry) => Padding(padding: const EdgeInsets.only(bottom: 10),
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(20), clipBehavior: Clip.antiAlias,
      child: ListTile(key: ValueKey('settings-result-${entry.id}'), contentPadding: const EdgeInsets.all(16),
        title: Text(entry.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${entry.section.title} · 当前：${widget.currentValue(entry)}', style: const TextStyle(color: purple, fontSize: 12)),
          const SizedBox(height: 5), Text(entry.description, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 12, height: 1.5)),
        ])), trailing: const Icon(Icons.preview_outlined, color: purple, size: 22), onTap: () => _preview(entry))));
  @override Widget build(BuildContext context) {
    final query = search.text.trim();
    final matches = settingsEntries.where((s) => s.matches(query)).toList();
    return ListView(key: const PageStorageKey('settings-overview'), padding: const EdgeInsets.fromLTRB(22, 26, 22, 24), children: [
      Text('设置', style: Theme.of(context).textTheme.headlineLarge), const SizedBox(height: 8),
      const Text('让提醒，更适合你。', style: TextStyle(color: muted)), const SizedBox(height: 24),
      TextField(key: const ValueKey('settings-search'), controller: search, onChanged: (_) => setState(() {}),
        decoration: InputDecoration(hintText: '搜索设置', prefixIcon: const Icon(Icons.search_rounded, color: muted),
          suffixIcon: query.isEmpty ? null : IconButton(tooltip: '清空搜索', icon: const Icon(Icons.close_rounded),
            onPressed: () { search.clear(); setState(() {}); }),
          contentPadding: const EdgeInsets.symmetric(vertical: 12), fillColor: const Color(0xFFEEEDF3))),
      if (query.isEmpty) ...[
        _label('偏好设置'), _group(settingsSections.take(4).toList()),
        _label('管理与支持'), _group(settingsSections.skip(4).toList()),
      ] else ...[
        _label('搜索结果 · ${matches.length} 个子项 · 点击预览'),
        if (matches.isNotEmpty) ...matches.map(_result)
        else const Padding(padding: EdgeInsets.symmetric(vertical: 36), child: Text('没有找到相关设置，试试“铃声”或“语音”。',
          textAlign: TextAlign.center, style: TextStyle(color: muted))),
      ],
      const SizedBox(height: 24), Text('超级提醒 · ${widget.version}', textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: muted)),
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
    child: RepaintBoundary(child: FrostedPanel(blur: false,
      child: ScaffoldMessenger(key: widget.messengerKey, child: Scaffold(backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false, body: SafeArea(top: false, child: Column(children: [
      Padding(padding: const EdgeInsets.only(top: 10, bottom: 10), child: Container(width: 34, height: 4,
        decoration: BoxDecoration(color: const Color(0xFFD5D2DF), borderRadius: BorderRadius.circular(4)))),
      Padding(padding: const EdgeInsets.fromLTRB(23, 0, 14, 14), child: Row(children: [
        Expanded(child: Text(widget.section.title, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800))),
        IconButton.filledTonal(tooltip: '关闭设置分类', onPressed: () {
          if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
        },
          style: IconButton.styleFrom(backgroundColor: lavender, foregroundColor: muted), icon: const Icon(Icons.close_rounded)),
      ])),
      if (widget.target != null) Padding(padding: const EdgeInsets.fromLTRB(23, 0, 23, 12),
        child: Row(children: [const Icon(Icons.search_rounded, size: 16, color: purple), const SizedBox(width: 7),
          Expanded(child: Text('已定位：${widget.target!.title}', style: const TextStyle(color: purple, fontSize: 12)))])),
      Expanded(child: AnimatedBuilder(animation: widget.changes, builder: (context, _) => ListView(
        key: ValueKey('settings-sheet-${widget.section.category.name}'), controller: controller,
        padding: const EdgeInsets.only(bottom: 28), children: widget.items(context)))),
    ])))))));
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
  @override Widget build(BuildContext context) => ListTile(
    tileColor: widget.highlighted ? lavender : null,
    leading: Icon(widget.icon, color: purple), title: Text(widget.title),
    subtitle: Text(widget.value, style: const TextStyle(color: muted, fontSize: 12)),
    trailing: busy ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2))
      : const Icon(Icons.chevron_right, color: muted), onTap: busy ? null : _run);
}
