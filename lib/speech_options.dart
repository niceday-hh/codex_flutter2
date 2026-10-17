import 'package:flutter/material.dart';
import 'reminder.dart';
import 'speech.dart';
import 'speech_voices.dart';
import 'voice_catalog.dart';

const _purple = Color(0xFF7252F6);
String speechModeLabel(String value) => switch (value) {
  'on' => '开启语音播报', 'inherit' => '跟随默认设置', _ => '关闭语音播报',
};
String speechVoiceLabel(String value) {
  final id = int.tryParse(value);
  return id == null || id < 0 || id >= speechVoiceNames.length ? '跟随默认音色' : '$id · ${speechVoiceNames[id]}';
}

class SpeechOptions extends StatefulWidget {
  final Reminder reminder;
  final Map<String, dynamic> defaults;
  final bool defaultSettings;
  final Future<void> Function() onChanged;
  const SpeechOptions({super.key, required this.reminder, required this.defaults,
    required this.onChanged, this.defaultSettings = false});
  @override State<SpeechOptions> createState() => _SpeechOptionsState();
}
class _SpeechOptionsState extends State<SpeechOptions> {
  bool previewing = false;
  Reminder get r => widget.reminder;
  Future<void> changed() async {
    setState(() {});
    try { await widget.onChanged(); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置保存失败，请重试'))); }
  }
  Future<void> previewCurrent() async {
    final config = Reminder.fromJson(r.toJson());
    if (r.speechRandom && (widget.defaultSettings || r.speechVoice.isEmpty)) {
      final catalog = await VoiceCatalog.load();
      final id = catalog.pick(language: r.speechRandomLanguage, gender: r.speechRandomGender);
      if (id == null) throw StateError('此分组没有可用音色');
      config.speechVoice = id;
      if (!widget.defaultSettings && mounted) { r.speechVoice = id; await changed(); }
    }
    if (mounted) await speech.preview(config);
  }
  Future<void> reroll() async {
    try {
      final catalog = await VoiceCatalog.load();
      final id = catalog.pick(language: r.speechRandomLanguage, gender: r.speechRandomGender);
      if (id != null && mounted) { r.speechVoice = id; await changed(); }
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('音色分组加载失败，请重试'))); }
  }
  @override void dispose() { speech.stopPreview(); super.dispose(); }
  @override Widget build(BuildContext context) => Column(children: [
    ListTile(leading: const Icon(Icons.record_voice_over_outlined, color: _purple),
      title: Text(widget.defaultSettings ? '默认语音播报' : '语音播报'),
      subtitle: Text(speechModeLabel(r.speechMode)), trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final mode = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!widget.defaultSettings) ListTile(title: const Text('跟随默认设置'), onTap: () => Navigator.pop(c, 'inherit')),
            ListTile(title: const Text('开启语音播报'), onTap: () => Navigator.pop(c, 'on')),
            ListTile(title: const Text('关闭语音播报'), onTap: () => Navigator.pop(c, 'off')),
          ])));
        if (mode != null && mounted) { r.speechMode = mode; await changed(); }
      }),
    ListTile(leading: const Icon(Icons.person_outline, color: _purple), title: const Text('播报音色'),
      subtitle: Text(r.speechRandom && !widget.defaultSettings && r.speechVoice.isEmpty ? '保存时从所选分组抽取一次' : '${speechVoiceLabel(r.speechVoice)} · VITS-MNN 共804个音色条目'), trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final voice = await chooseSpeechVoice(context, r.speechVoice, allowDefault: !widget.defaultSettings,
          language: r.speechRandomLanguage, gender: r.speechRandomGender,
          preview: (id) => speech.preview(Reminder.fromJson(r.toJson())..speechVoice = id));
        if (voice != null && mounted) { r.speechVoice = voice; r.speechRandom = false; await changed(); }
      }),
    SwitchListTile(title: Text(widget.defaultSettings ? '新建任务随机音色' : '此任务随机选音色'),
      subtitle: const Text('创建时抽取并保存；改时间、循环和重提醒保持同一音色。关闭后使用所选或默认音色。'),
      value: r.speechRandom, onChanged: (v) async {
        r.speechRandom = v;
        if (v && !widget.defaultSettings) r.speechVoice = '';
        await changed();
      }),
    if (r.speechRandom) ...[
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
        Expanded(child: DropdownButtonFormField<String>(initialValue: r.speechRandomLanguage, isExpanded: true,
          decoration: const InputDecoration(labelText: '配音来源'),
          items: voiceLanguages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) async { if (v == null) return; r.speechRandomLanguage = v; if (!widget.defaultSettings) r.speechVoice = ''; await changed(); })),
        const SizedBox(width: 12),
        Expanded(child: DropdownButtonFormField<String>(initialValue: r.speechRandomGender, isExpanded: true,
          decoration: const InputDecoration(labelText: '角色性别'),
          items: voiceGenders.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) async { if (v == null) return; r.speechRandomGender = v; if (!widget.defaultSettings) r.speechVoice = ''; await changed(); })),
      ])),
      const Padding(padding: EdgeInsets.all(16), child: Text('分组指角色配音来源，不会自动翻译；当前按中文文本朗读。未确认性别的角色只参与“不限角色性别”随机。',
        style: TextStyle(fontSize: 12, color: Color(0xFF8A859C)))),
      if (!widget.defaultSettings) TextButton.icon(onPressed: reroll, icon: const Icon(Icons.shuffle), label: const Text('重新抽取一个音色')),
    ],
    ListTile(leading: const Icon(Icons.speed, color: _purple), title: const Text('播报语速'),
      subtitle: Text(r.speechRate == 0 ? '跟随默认语速' : '${r.speechRate.toStringAsFixed(1)} 倍'), trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final rate = await chooseSpeechRate(context, r.speechRate, allowDefault: !widget.defaultSettings);
        if (rate != null && mounted) { r.speechRate = rate; await changed(); }
      }),
    SwitchListTile(title: const Text('锁屏时隐藏播报正文'),
      subtitle: Text(r.speechHideLocked ? '锁屏时只说“你有一条待办提醒”；解锁后的下一轮可朗读正文' : '锁屏时也允许朗读完整内容，请留意周围环境'),
      value: r.speechHideLocked, onChanged: (v) async { r.speechHideLocked = v; await changed(); }),
    SwitchListTile(title: const Text('重提醒时再次朗读'),
      subtitle: const Text('关闭后仅首次朗读；后续仍显示通知和振动，播放结束不算已读'),
      value: r.speechRepeat, onChanged: (v) async { r.speechRepeat = v; await changed(); }),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: OutlinedButton.icon(
      onPressed: previewing ? null : () async {
        setState(() => previewing = true);
        try { await previewCurrent(); }
        catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('试听暂未成功，请重试并检查媒体音量'))); }
        finally { if (mounted) setState(() => previewing = false); }
      }, icon: const Icon(Icons.play_circle_outline), label: Text(previewing ? '正在生成试听…' : r.speechRandom && widget.defaultSettings ? '试听随机音色' : '试听当前音色'))),
    const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text(
      '保存后异步生成离线语音；请确认“语音已就绪”。到点未就绪时使用原铃声／振动，不会稍后自动补播这一轮。修改正文、音色或语速后需重新生成。试听使用固定短句；锁屏播报与通知显示分别控制。',
      style: TextStyle(fontSize: 12, color: Color(0xFF8A859C)))),
  ]);
}

Future<double?> chooseSpeechRate(BuildContext context, double current, {required bool allowDefault}) async {
  var rate = current == 0 ? 1.0 : current;
  return showModalBottomSheet<double>(context: context, showDragHandle: true, builder: (c) => StatefulBuilder(
    builder: (c, update) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('播报语速 ${rate.toStringAsFixed(1)} 倍', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      Slider(min: 0.8, max: 1.3, divisions: 5, value: rate, label: rate.toStringAsFixed(1), onChanged: (v) => update(() => rate = v)),
      if (allowDefault) TextButton(onPressed: () => Navigator.pop(c, 0.0), child: const Text('跟随默认语速')),
      FilledButton(onPressed: () => Navigator.pop(c, (rate * 10).round() / 10), child: const Text('使用此语速')),
    ])))));
}

Future<String?> chooseSpeechVoice(BuildContext context, String current, {required bool allowDefault,
  required Future<void> Function(String) preview, String language = 'all', String gender = 'all'}) async {
  final catalog = await VoiceCatalog.load();
  if (!context.mounted) return null;
  var query = '', busy = '', source = language, role = gender;
  String? message;
  return showModalBottomSheet<String>(context: context, showDragHandle: true, isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, update) {
      final matches = catalog.candidates(language: source, gender: role, query: query);
      return SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(c).bottom),
      child: SizedBox(height: (MediaQuery.sizeOf(c).height - MediaQuery.viewInsetsOf(c).bottom) * 0.8,
      child: Column(children: [
        const Text('选择播报音色', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Text('VITS-MNN · 804个音色条目', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12), Row(children: [
          Expanded(child: DropdownButtonFormField<String>(initialValue: source, isExpanded: true,
            decoration: const InputDecoration(labelText: '配音来源'),
            items: voiceLanguages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => update(() => source = v ?? 'all'))),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<String>(initialValue: role, isExpanded: true,
            decoration: const InputDecoration(labelText: '角色性别'),
            items: voiceGenders.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => update(() => role = v ?? 'all'))),
        ]),
        const SizedBox(height: 8), TextField(decoration: const InputDecoration(hintText: '搜索角色名或编号'),
          onChanged: (v) => update(() => query = v.trim().toLowerCase())),
        Row(children: [Expanded(child: Text('${matches.length} 个匹配音色', style: const TextStyle(fontSize: 12))),
          TextButton.icon(onPressed: matches.isEmpty ? null : () {
            final id = catalog.pick(language: source, gender: role, query: query);
            speech.stopPreview(); Navigator.pop(c, id);
          }, icon: const Icon(Icons.shuffle), label: const Text('随机挑一个'))]),
        if (allowDefault) ListTile(title: const Text('跟随默认音色'), onTap: () { speech.stopPreview(); Navigator.pop(c, ''); }),
        if (message != null) Text(message!, style: const TextStyle(fontSize: 12)),
        const Text('按配音来源和角色性别分组；性别未标注的角色仅在“不限角色性别”中显示。', style: TextStyle(fontSize: 11, color: Color(0xFF8A859C))),
        Expanded(child: matches.isEmpty ? const Center(child: Text('没有匹配的音色，请调整分组或搜索词')) : ListView.builder(
          itemCount: matches.length, itemBuilder: (_, index) {
            final id = matches[index];
            return ListTile(title: Text(speechVoiceLabel(id)), subtitle: Text(catalog.tags(id), style: const TextStyle(fontSize: 11)),
              leading: id == current ? const Icon(Icons.check_circle, color: _purple) : const Icon(Icons.person_outline),
              trailing: IconButton(tooltip: '试听音色$id', icon: busy == id
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_circle_outline),
                onPressed: busy.isNotEmpty ? null : () async {
                  update(() { busy = id; message = '正在准备音色 $id…'; });
                  try { await preview(id); if (c.mounted) update(() => message = '正在试听音色 $id'); }
                  catch (_) { if (c.mounted) update(() => message = '试听未成功，请检查媒体音量后重试'); }
                  finally { if (c.mounted) update(() => busy = ''); }
                }), onTap: () { speech.stopPreview(); Navigator.pop(c, id); });
          })),
      ]))));
    })).whenComplete(speech.stopPreview);
}
