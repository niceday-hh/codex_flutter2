import 'package:flutter/material.dart';
import 'asr.dart';
import 'recording_waveform.dart';
import 'voice_flow.dart';
import 'app_style.dart';
export 'voice_confirmation.dart';

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
      const Chip(avatar: Icon(Icons.graphic_eq, size: 17, color: purple), backgroundColor: lavender, side: BorderSide.none, label: Text('离线识别'))]),
    const SizedBox(height: 8), const Text('说下时间和事情，剩下的交给提醒。', style: TextStyle(color: Color(0xFF8A859C))),
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
    ValueListenableBuilder<String>(valueListenable: asr.status, builder: (_, status, _) =>
      Text(status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF8A859C)))),
    if (flow.capturing) Text('剩余 ${flow.secondsLeft} 秒', textAlign: TextAlign.center),
    const SizedBox(height: 18), RecordingWaveform(meter: flow.meter),
    const SizedBox(height: 24),
    Card(elevation: 0, color: Colors.white, child: Padding(padding: const EdgeInsets.all(16), child:
      TextField(controller: text, enabled: !flow.busy && !flow.capturing, minLines: 3, maxLines: 6,
        onChanged: (v) { flow.text = v; flow.reference = v.trim().isEmpty ? null : flow.reference ?? DateTime.now(); setState(() {}); },
        decoration: const InputDecoration(hintText: '例如：20分钟后提醒我喝水，每隔3分钟提醒，总共提醒5次', border: InputBorder.none, filled: false)))),
    const SizedBox(height: 16),
    FilledButton(onPressed: text.text.trim().isEmpty || flow.busy || flow.capturing ? null : () { FocusScope.of(context).unfocus(); flow.reviewText(text.text); },
      child: const Text('确认并设置提醒')),
    const SizedBox(height: 12),
    OutlinedButton(onPressed: flow.busy ? null : flow.phase == VoicePhase.recording ? flow.finish : flow.startRecording,
      child: Text(flow.phase == VoicePhase.recording ? '结束录音' : '重新录音')),
    const SizedBox(height: 20),
    const Text('说完后安静片刻，会自动进入确认。也可以说“开启语音播报”“提醒间隔三分钟”“总共提醒五次”。单次录音最长45秒，切到后台会关闭麦克风。',
      textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8A859C), fontSize: 12, height: 1.6)),
  ]);
}
