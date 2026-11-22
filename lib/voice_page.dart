import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'asr.dart';
import 'recording_waveform.dart';
import 'voice_flow.dart';
import 'design_tokens.dart';
import 'widgets/widgets.dart';
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final auraTint = dark ? MemoColor.voiceAuraCyan : c.brand400;

    return ListView(padding: const EdgeInsets.fromLTRB(24, 26, 24, 30), children: [
      Row(children: [
        Expanded(child: Text('语音新建', style: context.text.display)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: dark ? c.surfaceAlt : c.brand100,
            borderRadius: BorderRadius.circular(MemoRadius.pill),
            border: dark ? Border.all(color: Colors.white.withValues(alpha: 0.10)) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.graphic_eq, size: 14, color: c.brand700),
            const SizedBox(width: 5),
            Text('离线识别', style: context.text.overline.copyWith(color: c.brand700)),
          ]),
        ),
      ]),
      const SizedBox(height: 6),
      Text('说下时间和事情，剩下的交给提醒。', style: context.text.body.copyWith(color: c.muted)),
      const SizedBox(height: 20),
      SegmentedButton<VoiceTaskMode>(
        key: const ValueKey('voice-task-mode'),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: VoiceTaskMode.single, icon: Icon(Icons.note_alt_outlined), label: Text('单任务')),
          ButtonSegment(value: VoiceTaskMode.multiple, icon: Icon(Icons.library_books_outlined), label: Text('多任务')),
        ],
        selected: {flow.taskMode},
        onSelectionChanged: flow.canSelectTaskMode ? (selection) => flow.selectTaskMode(selection.first) : null,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.brand100 : c.surface),
          foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.brand700 : c.muted),
          side: WidgetStatePropertyAll(BorderSide(color: dark ? Colors.white.withValues(alpha: 0.10) : c.line)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 14, horizontal: 12)),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        flow.taskMode == VoiceTaskMode.single ? '一次创建一条提醒' : '一次说多件事，逐条核对后创建',
        textAlign: TextAlign.center,
        style: context.text.caption.copyWith(color: c.muted),
      ),
      const SizedBox(height: 18),
      Center(
        child: SizedBox(
          width: 156,
          height: 156,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Static ambient glow behind the mic trigger (Clip.none avoids pushing fold).
              Positioned(
                left: -30,
                right: -30,
                top: -30,
                bottom: -30,
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            c.brand500.withValues(alpha: dark ? (flow.capturing ? 0.34 : 0.22) : (flow.capturing ? 0.20 : 0.12)),
                            auraTint.withValues(alpha: dark ? (flow.capturing ? 0.14 : 0.08) : 0.04),
                            Colors.transparent,
                          ],
                          stops: const [0.25, 0.62, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: MemoMotion.base,
                curve: MemoMotion.curve,
                width: flow.capturing ? 178 : 168,
                height: flow.capturing ? 178 : 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (flow.capturing ? auraTint : c.brand400)
                        .withValues(alpha: dark ? (flow.capturing ? 0.36 : 0.18) : (flow.capturing ? 0.28 : 0.16)),
                    width: 1.2,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: flow.phase == VoicePhase.recording ? '停止录音并识别' : '开始录音',
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: c.brand500.withValues(alpha: dark ? 0.36 : 0.24),
                        blurRadius: 26,
                        spreadRadius: -4,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Ink(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: dark
                              ? [c.brand400, c.brand600]
                              : [c.brand400, c.brand600],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: dark ? 0.24 : 0.30),
                          width: 1.5,
                        ),
                      ),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: flow.busy && flow.phase != VoicePhase.preparing
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                if (flow.phase == VoicePhase.recording) {
                                  flow.finish();
                                } else {
                                  flow.startRecording();
                                }
                              },
                        child: Center(
                          child: flow.busy
                              ? const SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                )
                              : Icon(
                                  flow.phase == VoicePhase.recording ? Icons.stop_rounded : Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 54,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(flow.message.isEmpty ? '点击开始说话' : flow.message, textAlign: TextAlign.center, style: context.text.headline),
      if (flow.capturing) ...[
        RecordingWaveform(meter: flow.meter),
        const SizedBox(height: 4),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: dark ? c.surfaceAlt : c.brand50,
              borderRadius: BorderRadius.circular(MemoRadius.pill),
              border: Border.all(color: dark ? Colors.white.withValues(alpha: 0.08) : c.line),
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: flow.countdown,
              builder: (_, seconds, __) => Text(
                '剩余 $seconds 秒',
                textAlign: TextAlign.center,
                style: context.text.caption.copyWith(fontFeatures: MemoText.tabular),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        ValueListenableBuilder<String>(
          valueListenable: asr.status,
          builder: (_, status, _) => Text(
            status.startsWith('正在准备') || status.startsWith('正在加载')
                ? '已开始收音，识别模型准备中'
                : status,
            textAlign: TextAlign.center,
            style: context.text.caption,
          ),
        ),
      ] else if (!flow.busy && text.text.trim().isEmpty) ...[
        const SizedBox(height: 8),
        Text(
          flow.taskMode == VoiceTaskMode.single
              ? '试着说“二十分钟后提醒我喝水”'
              : '试着说“明天九点提醒我起床，下一条十点提醒我出门”',
          textAlign: TextAlign.center,
          style: context.text.body,
        ),
      ],
      const SizedBox(height: 22),
      Card(
        elevation: 0,
        color: dark ? c.surfaceAlt : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MemoRadius.xl),
          side: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.09) : c.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: text,
            enabled: !flow.busy && !flow.capturing,
            minLines: 3,
            maxLines: 6,
            onChanged: (v) {
              flow.text = v;
              flow.reference = v.trim().isEmpty ? null : flow.reference ?? DateTime.now();
              setState(() {});
            },
            decoration: const InputDecoration(
              hintText: '也可以直接输入时间和事情',
              border: InputBorder.none,
              filled: false,
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: text.text.trim().isEmpty || flow.busy || flow.capturing
            ? null
            : () {
                FocusScope.of(context).unfocus();
                flow.reviewText(text.text);
              },
        child: Text(flow.taskMode == VoiceTaskMode.single ? '确认并设置提醒' : '核对多条提醒'),
      ),
      const SizedBox(height: 12),
      if (flow.active || (flow.hasRecordedDraft && text.text.trim().isNotEmpty))
        OutlinedButton(
          onPressed: flow.phase == VoicePhase.saving
              ? null
              : flow.busy
                  ? flow.cancel
                  : flow.phase == VoicePhase.recording
                      ? flow.finish
                      : flow.startRecording,
          child: Text(
            flow.busy ? '取消录音' : flow.phase == VoicePhase.recording ? '结束录音' : '重新录音',
          ),
        ),
      const SizedBox(height: 20),
      ExpansionTile(
        title: const Text('语音用法'),
        children: [
          MemoHint(
            flow.taskMode == VoiceTaskMode.single
                ? '单次录音最长45秒，切到后台会关闭麦克风。首页可说“开始录音，多任务模式”再说多件事。'
                : '说“下一条”分开任务，最多10条。省略日期时沿用前一条日期。还可说“开启语音播报”“提醒间隔三分钟”“总共提醒五次”。',
          ),
        ],
      ),
    ]);
  }
}
