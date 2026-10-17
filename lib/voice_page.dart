import 'package:flutter/material.dart';
import 'recording_waveform.dart';
import 'voice_flow.dart';

class VoicePage extends StatefulWidget {
  final VoiceFlow flow;
  const VoicePage({super.key, required this.flow});
  @override State<VoicePage> createState() => _VoicePageState();
}
class _VoicePageState extends State<VoicePage> {
  final text = TextEditingController();
  VoiceFlow get flow => widget.flow;
  void update() {
    if (!mounted) return;
    if (!flow.capturing && text.text != flow.text) text.text = flow.text;
    setState(() {});
  }
  @override void initState() { super.initState(); text.text = flow.text; flow.addListener(update); }
  @override void dispose() { flow.removeListener(update); text.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(24, 26, 24, 30), children: [
    Row(children: [Expanded(child: Text('语音新建', style: Theme.of(context).textTheme.headlineLarge)),
      const Chip(label: Text('离线识别'))]),
    const SizedBox(height: 8), const Text('说出时间和事情，安静片刻后核对提醒', style: TextStyle(color: Color(0xFF8A859C))),
    const SizedBox(height: 30),
    Center(child: Semantics(button: true, label: flow.phase == VoicePhase.recording ? '停止录音并识别' : '开始录音',
      child: InkWell(onTap: flow.busy ? null : flow.phase == VoicePhase.recording ? flow.finish : flow.startRecording,
        borderRadius: BorderRadius.circular(80),
        child: Container(width: 150, height: 150, decoration: const BoxDecoration(shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Color(0xFF9A79FF), Color(0xFF6740F2)])),
          child: flow.busy ? const Padding(padding: EdgeInsets.all(50), child: CircularProgressIndicator(color: Colors.white))
            : Icon(flow.phase == VoicePhase.recording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 56))))),
    const SizedBox(height: 20),
    Text(flow.message.isEmpty ? '点击开始说话' : flow.message, textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
    if (flow.capturing) Text('剩余 ' + flow.secondsLeft.toString() + ' 秒', textAlign: TextAlign.center),
    const SizedBox(height: 18), RecordingWaveform(meter: flow.meter),
    const SizedBox(height: 24),
    Card(elevation: 0, color: Colors.white, child: Padding(padding: const EdgeInsets.all(16), child:
      TextField(controller: text, enabled: !flow.busy && !flow.capturing, minLines: 3, maxLines: 6,
        onChanged: (v) { flow.text = v; flow.reference ??= DateTime.now(); setState(() {}); },
        decoration: const InputDecoration(hintText: '例如：二十分钟后提醒我做饭，开启语音提醒', border: InputBorder.none, filled: false)))),
    const SizedBox(height: 16),
    FilledButton(onPressed: text.text.trim().isEmpty || flow.busy || flow.capturing ? null : () => flow.reviewText(text.text),
      child: const Text('确认并设置提醒')),
    const SizedBox(height: 12),
    OutlinedButton(onPressed: flow.busy ? null : flow.phase == VoicePhase.recording ? flow.finish : flow.startRecording,
      child: Text(flow.phase == VoicePhase.recording ? '结束录音' : '重新录音')),
    const SizedBox(height: 20),
    const Text('说完后连续安静会自动识别，也可点结束录音。确认卡片支持“确认”“重新录音”“取消”，不会朗读确认内容。时间不完整或已经过去时需重录或手动编辑。单次录音最长45秒；切后台会关闭麦克风。',
      textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8A859C), fontSize: 12, height: 1.6)),
  ]);
}

class VoiceConfirmation extends StatelessWidget {
  final VoiceFlow flow;
  final Future<void> Function() onEdit;
  const VoiceConfirmation({super.key, required this.flow, required this.onEdit});
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: flow, builder: (context, _) {
    final parsed = flow.pending;
    if (parsed == null) return const SizedBox.shrink();
    final r = parsed.reminder;
    final saving = flow.phase == VoicePhase.saving;
    final date = r.date.year.toString() + '年' + r.date.month.toString() + '月' + r.date.day.toString() + '日 ';
    return PopScope(canPop: false, child: AlertDialog(
      title: const Text('确认提醒'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.dateConfirmed && r.timeConfirmed ? date + r.preciseTime : '日期或时间待确认',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10), Text(r.text.isEmpty ? '没有识别到提醒正文' : r.text),
        const SizedBox(height: 12), Text(r.repeatLabel),
        for (final setting in parsed.settings) Text(setting),
        if (flow.validationError != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(flow.validationError!, style: const TextStyle(color: Colors.deepOrange))),
        const SizedBox(height: 16), Text(flow.message),
        if (flow.capturing) Text('语音确认剩余 ' + flow.secondsLeft.toString() + ' 秒'),
        const SizedBox(height: 8), const Text('可说“确认”“重新录音”或“取消”，也可使用下方按钮。',
          style: TextStyle(fontSize: 12, color: Color(0xFF8A859C))),
      ])),
      actions: [
        TextButton(onPressed: saving ? null : flow.cancel, child: const Text('取消')),
        TextButton(onPressed: saving ? null : flow.startRecording, child: const Text('重新录音')),
        TextButton(onPressed: saving ? null : onEdit, child: const Text('手动编辑')),
        FilledButton(onPressed: saving ? null : flow.confirm, child: Text(saving ? '正在保存…' : '确认创建')),
      ]));
  });
}
