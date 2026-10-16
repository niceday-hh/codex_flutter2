import 'package:flutter/material.dart';
import 'reminder.dart';
import 'speech.dart';

const _purple = Color(0xFF7252F6);
String speechModeLabel(String value) => switch (value) {
  'on' => '开启语音播报', 'inherit' => '跟随默认设置', _ => '关闭语音播报',
};
String speechVoiceLabel(String value) => value.isEmpty ? '跟随默认音色' : '音色 $value';

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
      subtitle: Text('${speechVoiceLabel(r.speechVoice)} · AISHELL-3 共174个音色'), trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final voice = await chooseSpeechVoice(context, r.speechVoice, allowDefault: !widget.defaultSettings,
          preview: (id) => speech.preview(Reminder.fromJson(r.toJson())..speechVoice = id));
        if (voice != null && mounted) { r.speechVoice = voice; await changed(); }
      }),
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
        try { await speech.preview(r); }
        catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('试听暂未成功，请重试并检查媒体音量'))); }
        finally { if (mounted) setState(() => previewing = false); }
      }, icon: const Icon(Icons.play_circle_outline), label: Text(previewing ? '正在生成试听…' : '试听当前音色'))),
    const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text(
      '开启后提前生成离线语音，到点直接播放；正常播报不叠加铃声。未准备成功时按原铃声／振动设置提醒。锁屏播报与锁屏通知显示分别控制。',
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

Future<String?> chooseSpeechVoice(BuildContext context, String current, {required bool allowDefault, required Future<void> Function(String) preview}) {
  var query = '', busy = '';
  String? message;
  return showModalBottomSheet<String>(context: context, showDragHandle: true, isScrollControlled: true,
    builder: (c) => StatefulBuilder(builder: (c, update) => SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(c).bottom),
      child: SizedBox(height: MediaQuery.sizeOf(c).height * 0.75, child: Column(children: [
        const Text('选择播报音色', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Text('174个说话人 · 编号0～173 · 点击播放按钮试听', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12), TextField(keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '搜索音色编号'), onChanged: (v) => update(() => query = v.trim())),
        if (allowDefault) ListTile(title: const Text('跟随默认音色'), onTap: () { speech.stopPreview(); Navigator.pop(c, ''); }),
        if (message != null) Text(message!, style: const TextStyle(fontSize: 12)),
        Expanded(child: ListView(children: List.generate(174, (i) => '$i').where((id) => id.contains(query)).map((id) => ListTile(
          title: Text('音色 $id'), leading: id == current ? const Icon(Icons.check_circle, color: _purple) : const Icon(Icons.person_outline),
          trailing: IconButton(tooltip: '试听音色$id', icon: busy == id ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_circle_outline),
            onPressed: busy.isNotEmpty ? null : () async {
              update(() { busy = id; message = '正在准备音色 $id…'; });
              try { await preview(id); if (c.mounted) update(() => message = '正在试听音色 $id'); }
              catch (_) { if (c.mounted) update(() => message = '试听未成功，请检查媒体音量后重试'); }
              finally { if (c.mounted) update(() => busy = ''); }
            }), onTap: () { speech.stopPreview(); Navigator.pop(c, id); })).toList())),
      ])))))).whenComplete(speech.stopPreview);
}
