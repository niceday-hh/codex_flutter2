import 'dart:async';
import 'package:flutter/material.dart';
import 'design_tokens.dart';
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
  Map<String, dynamic>? _candidate;
  String _playingMessage = '正在试听本条提醒。';
  String _message = '使用本条提醒的正文、音色和语速，可保存为 WAV 音频。';
  bool _failed = false;
  int _operation = 0;
  @override void dispose() {
    _operation++; session.stopPreview(owner: _owner);
    if (_candidate != null) unawaited(session.releaseAudio(_candidate!));
    super.dispose();
  }
  void _stop() {
    _operation++; session.stopPreview(owner: _owner);
    setState(() { _busy = null; _failed = false; _message = '已停止试听。'; });
  }
  Future<void> _listen({bool candidate = false}) async {
    final operation = ++_operation;
    setState(() { _busy = 'play'; _failed = false; _message = '正在准备本条提醒的音频…';
      _playingMessage = candidate ? '正在试听新版本，尚未替换当前音频。' : '正在试听本条提醒。'; });
    try {
      final started = candidate && _candidate != null
        ? await session.previewCandidate(_candidate!, owner: _owner)
        : await session.previewReminder(widget.reminder.id, owner: _owner);
      if (!mounted || operation != _operation) return;
      setState(() { _message = started ? '音频已就绪，可以再次试听或保存。' : '已取消试听。'; });
    } catch (e) {
      if (mounted && operation == _operation) setState(() { _failed = true; _message = niceError(e); });
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = null);
    }
  }
  Future<void> _save() async {
    session.stopPreview(owner: _owner);
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
  Future<void> _newVariant() async {
    session.stopPreview(owner: _owner);
    final operation = ++_operation;
    setState(() { _busy = 'variant'; _failed = false; _message = '正在为同一音色准备新版本，当前音频继续保留…'; });
    try {
      final job = await session.prepareCandidate(widget.reminder.id);
      if (!mounted || operation != _operation) { await session.releaseAudio(job); return; }
      setState(() { _candidate = job; _message = '新版本已准备好。试听后，点击“使用此版本”才会替换当前音频。'; });
    } catch (e) {
      if (mounted && operation == _operation) setState(() { _failed = true; _message = niceError(e); });
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = null);
    }
  }
  void _discard() {
    final job = _candidate; _operation++; session.stopPreview(owner: _owner);
    setState(() { _candidate = null; _busy = null; _failed = false; _message = '已放弃新版本，继续使用原音频。'; });
    if (job != null) unawaited(session.releaseAudio(job));
  }
  Future<void> _select() async {
    final job = _candidate; if (job == null) return;
    final operation = ++_operation; session.stopPreview(owner: _owner);
    setState(() { _busy = 'select'; _failed = false; _message = '正在保存音频版本…'; });
    try {
      await session.useCandidate(job);
      if (!mounted || operation != _operation) return;
      setState(() { _candidate = null; _message = '已使用此版本。提醒、试听和保存音频将复用它。'; });
      await session.releaseAudio(job);
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
      final message = failure ? preview.error! : playing ? _playingMessage : _message;
      return Container(width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.colors.brand100, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('提醒音频', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(message, key: const ValueKey('reminder-audio-feedback'),
            style: TextStyle(color: _failed || failure ? context.colors.danger : context.colors.muted, fontSize: 13, height: 1.5))),
          if (widget.reminder.speechState == 'off')  Padding(padding: EdgeInsets.only(top: 8), child: Text(
            '到点语音播报当前关闭；试听和保存不会开启它。', style: TextStyle(color: context.colors.muted, fontSize: 12))),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(key: const ValueKey('preview-reminder-audio'),
              onPressed: _busy != null && _busy != 'play' ? null : playing || _busy == 'play' ? _stop : () => _listen(),
              icon: Icon(playing || _busy == 'play' ? Icons.stop_rounded : Icons.play_arrow_rounded),
              label: Text(playing ? '停止试听' : _busy == 'play' ? '取消试听' : '试听提醒')),
            OutlinedButton.icon(key: const ValueKey('new-reminder-audio'),
              onPressed: _busy == 'variant' ? _stop : _busy == null && _candidate == null ? _newVariant : null,
              icon: const Icon(Icons.refresh_rounded), label: Text(_busy == 'variant' ? '取消准备' : '换一版')),
            OutlinedButton.icon(key: const ValueKey('save-reminder-audio'), onPressed: _busy == null && _candidate == null ? _save : null,
              icon: _busy == 'save' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded), label: const Text('保存音频')),
          ]),
          if (_candidate != null) ...[
            const SizedBox(height: 16), const Divider(), const SizedBox(height: 10),
            const Text('新版本 · 选择后才用于提醒', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: _busy == null ? () => _listen(candidate: true) : null,
                icon: const Icon(Icons.play_arrow_rounded), label: const Text('试听新版本')),
              FilledButton(onPressed: _busy == null ? _select : null, child: const Text('使用此版本')),
              TextButton(onPressed: _busy == null ? _discard : null, child: const Text('放弃新版本')),
            ]),
          ],
        ]));
    });
}
