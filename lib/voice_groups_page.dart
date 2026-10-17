import 'package:flutter/material.dart';
import 'reminder.dart';
import 'app_error.dart';
import 'speech.dart';
import 'speech_voices.dart';
import 'voice_catalog.dart';
import 'voice_group.dart';

class VoiceGroupsPage extends StatefulWidget {
  final MemoStore store;
  const VoiceGroupsPage({super.key, required this.store});
  @override State<VoiceGroupsPage> createState() => _VoiceGroupsPageState();
}
class _VoiceGroupsPageState extends State<VoiceGroupsPage> {
  bool saving = false;
  String? error;
  Future<void> persist(List<VoiceGroup> groups) async {
    setState(() { saving = true; error = null; });
    try { await widget.store.saveVoiceGroups(groups); }
    catch (e) { if (mounted) setState(() => error = niceError(e)); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> edit([VoiceGroup? group]) async {
    final result = await Navigator.push<VoiceGroup>(context, MaterialPageRoute(builder: (_) => VoiceGroupEditor(group: group)));
    if (result == null || !mounted) return;
    await persist([for (final g in widget.store.voiceGroups) if (g.id != result.id) g, result]);
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的角色组')),
    floatingActionButton: FloatingActionButton(onPressed: saving ? null : () => edit(),
      tooltip: '新建角色组', child: const Icon(Icons.add)),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('选择喜欢的角色组成专属随机池。角色组会随备份导出；修改或删除组保留已创建任务的音色。'),
      const SizedBox(height: 16),
      if (error != null) Text(error!),
      if (widget.store.voiceGroups.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('还没有角色组，点击 + 创建')),
      for (final g in widget.store.voiceGroups) Card(child: ListTile(
        leading: const Icon(Icons.groups_outlined), title: Text(g.name), subtitle: Text('${g.voices.length} 个角色'),
        onTap: saving ? null : () => edit(g),
        trailing: IconButton(tooltip: '删除角色组 ${g.name}', icon: const Icon(Icons.delete_outline), onPressed: saving ? null : () async {
          final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
            title: Text('删除“${g.name}”？'), content: const Text('已创建任务保留选定音色，新建任务不再使用此组。'),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除'))]));
          if (yes == true) await persist(widget.store.voiceGroups.where((v) => v.id != g.id).toList());
        }))),
      if (saving) const LinearProgressIndicator(),
    ]));
}
class VoiceGroupEditor extends StatefulWidget {
  final VoiceGroup? group;
  const VoiceGroupEditor({super.key, this.group});
  @override State<VoiceGroupEditor> createState() => _VoiceGroupEditorState();
}
class _VoiceGroupEditorState extends State<VoiceGroupEditor> {
  late final name = TextEditingController(text: widget.group?.name ?? '');
  late final selected = <String>{...?widget.group?.voices};
  late final catalog = VoiceCatalog.load();
  String query = '', language = 'all', gender = 'all', busy = '';
  @override void dispose() { name.dispose(); speech.stopPreview(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.group == null ? '新建角色组' : '编辑角色组'), actions: [
      TextButton(onPressed: name.text.trim().isEmpty || selected.isEmpty ? null : () {
        final ids = selected.toList()..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
        Navigator.pop(context, VoiceGroup(id: widget.group?.id ?? 'group_${DateTime.now().microsecondsSinceEpoch}',
          name: name.text.trim(), voices: ids));
      }, child: const Text('保存')),
    ]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: name, maxLength: 30,
        decoration: const InputDecoration(labelText: '角色组名称'), onChanged: (_) => setState(() {}))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
        decoration: const InputDecoration(hintText: '搜索角色名或编号'),
        onChanged: (v) => setState(() => query = v.trim()))),
      Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        Expanded(child: DropdownButtonFormField<String>(initialValue: language, isExpanded: true,
          items: voiceLanguages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => setState(() => language = v ?? 'all'))),
        const SizedBox(width: 12),
        Expanded(child: DropdownButtonFormField<String>(initialValue: gender, isExpanded: true,
          items: voiceGenders.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => setState(() => gender = v ?? 'all'))),
      ])),
      Text('已选择 ${selected.length} 个角色'),
      Expanded(child: FutureBuilder<VoiceCatalog>(future: catalog, builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('音色资料加载失败，请返回重试'));
        final c = snapshot.data;
        if (c == null) return const Center(child: CircularProgressIndicator());
        final matches = c.candidates(language: language, gender: gender, query: query);
        return ListView.builder(itemCount: matches.length, itemBuilder: (_, index) {
          final id = matches[index];
          return CheckboxListTile(value: selected.contains(id), title: Text('$id · ${speechVoiceNames[int.parse(id)]}'),
            subtitle: Text(c.tags(id)), onChanged: (v) => setState(() { if (v == true) { selected.add(id); } else { selected.remove(id); } }),
            secondary: IconButton(tooltip: '试听角色 $id', icon: Icon(busy == id ? Icons.hourglass_top : Icons.play_circle_outline),
              onPressed: busy.isNotEmpty ? null : () async {
                setState(() => busy = id);
                try { await speech.preview(Reminder(speechVoice: id, speechRate: 1)); }
                catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('试听失败，请重试'))); }
                finally { if (mounted) setState(() => busy = ''); }
              }));
        });
      })),
    ]));
}
