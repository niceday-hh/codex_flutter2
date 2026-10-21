import 'package:flutter/material.dart';
import 'app_style.dart';
import 'app_error.dart';
import 'reminder.dart';
import 'speech.dart';

class ReminderAudioPanel extends StatefulWidget {
  final Reminder reminder;
  final SpeechSession? session;
  const ReminderAudioPanel({super.key, required this.reminder, this.session});
  @override State<ReminderAudioPanel> createState() => _ReminderAudioPanelState();
}
class _ReminderAudioPanelState extends State<ReminderAudioPanel> {
  final _owner = Object();
  SpeechSession get session => widget.session ?? speech;
  String? _busy;
  String _message = '使用本条提醒的正文、音色和语速，可保存为 WAV 音频。';
  bool _failed = false;
  int _operation = 0;
  @override void dispose() { _operation++; session.stopPreview(owner: _owner); super.dispose(); }
  void _stop() {
    _operation++; session.stopPreview(owner: _owner);
    setState(() { _busy = null; _failed = false; _message = '已停止试听。'; });
  }
  Future<void> _listen() async {
    final operation = ++_operation;
    setState(() { _busy = 'play'; _failed = false; _message = '正在准备本条提醒的音频…'; });
    try {
      final started = await session.previewReminder(widget.reminder.id, owner: _owner);
      if (!mounted || operation != _operation) return;
      setState(() { _message = started ? '音频已就绪，可以再次试听或保存。' : '已取消试听。'; });
    } catch (e) {
      if (mounted && operation == _operation) setState(() { _failed = true; _message = niceError(e); });
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = null);
    }
  }
  Future<void> _save() async {
    final operation = ++_operation;
    setState(() { _busy = 'save'; _failed = false; _message = '正在准备音频，随后选择保存位置…'; });
    try {
      final saved = await session.withReminderAudio<bool?>(widget.reminder.id, (job) async {
        if (!mounted || operation != _operation) return null;
        return native.invokeMethod<bool>('exportReminderAudio', job['lease']);
      });
      if (!mounted || operation != _operation) return;
      setState(() { _message = saved == true ? '音频已保存到所选位置。' : '已取消保存。'; });
    } catch (e) {
      if (mounted && operation == _operation) setState(() { _failed = true; _message = niceError(e); });
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = null);
    }
  }
  @override Widget build(BuildContext context) => ValueListenableBuilder<SpeechPreviewState>(
    valueListenable: session.previewState, builder: (_, preview, _) {
      final own = identical(preview.owner, _owner);
      final playing = own && preview.playing;
      final failure = own && preview.error != null;
      final message = failure ? preview.error! : playing ? '正在试听本条提醒。' : _message;
      return Container(width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: lavender, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('提醒音频', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(message, key: const ValueKey('reminder-audio-feedback'),
            style: TextStyle(color: _failed || failure ? const Color(0xFFA75A28) : muted, fontSize: 13, height: 1.5))),
          if (widget.reminder.speechState == 'off') const Padding(padding: EdgeInsets.only(top: 8), child: Text(
            '到点语音播报当前关闭；试听和保存不会开启它。', style: TextStyle(color: muted, fontSize: 12))),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(key: const ValueKey('preview-reminder-audio'),
              onPressed: _busy == 'save' ? null : playing || _busy == 'play' ? _stop : _listen,
              icon: Icon(playing || _busy == 'play' ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(playing ? '停止试听' : _busy == 'play' ? '取消试听' : '试听提醒')),
            OutlinedButton.icon(key: const ValueKey('save-reminder-audio'), onPressed: _busy == null ? _save : null,
              icon: _busy == 'save' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded), label: const Text('保存音频')),
          ]),
        ]));
    });
}
