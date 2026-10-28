import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_tokens.dart';
import 'voice_flow.dart';
import 'widgets/widgets.dart';

/// Confirmation surface for a voice-parsed reminder.
///
/// Was a `FrostedPanel`: a 16px `BackdropFilter` covering the whole dialog,
/// sitting above a scrim, on top of an already-blurred background. Every open
/// forced an offscreen pass of the full screen before the first frame — the
/// single most expensive thing in the voice flow and the reason the dialog felt
/// a beat late. It is now an opaque sheet: same visual weight (white on a 20%
/// scrim with one tinted shadow), zero offscreen compositing.
class VoiceConfirmation extends StatelessWidget {
  final VoiceFlow flow;
  final Future<void> Function() onEdit;
  const VoiceConfirmation({super.key, required this.flow, required this.onEdit});

  String _dateLabel(DateTime date, DateTime reference) {
    final day = DateUtils.dateOnly(date).difference(DateUtils.dateOnly(reference)).inDays;
    if (day == 0) return '今天';
    if (day == 1) return '明天';
    if (day == 2) return '后天';
    return '${date.year == reference.year ? '' : '${date.year}年'}${date.month}月${date.day}日';
  }

  Widget _pill(String text, {required bool on}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: on ? MemoColor.brand200 : MemoColor.brand50,
      borderRadius: BorderRadius.circular(MemoRadius.sm),
    ),
    child: Text(text, style: MemoText.caption.copyWith(
      color: on ? MemoColor.brand800 : MemoColor.muted, fontWeight: FontWeight.w600)),
  );

  @override Widget build(BuildContext context) => AnimatedBuilder(animation: flow, builder: (context, _) {
    final parsed = flow.pending;
    if (parsed == null) return const SizedBox.shrink();
    final r = parsed.reminder;
    final saving = flow.phase == VoicePhase.saving;
    final validTime = r.dateConfirmed && r.timeConfirmed;
    final speechOn = r.speechMode == 'on' || r.speechMode == 'inherit' && flow.store.defaults['speechMode'] == 'on';
    final time = r.date.second == 0 && r.date.millisecond == 0 ? r.time : r.preciseTime;
    final error = flow.validationError;
    final listening = flow.phase == VoicePhase.confirming;
    final status = saving ? '正在创建提醒…' : listening ? '正在聆听确认'
      : flow.phase == VoicePhase.processing ? '正在识别确认指令…'
      : flow.phase == VoicePhase.preparing ? '正在准备语音确认…' : '可使用下方按钮继续';
    final extra = parsed.settings.where((s) =>
      s.startsWith('锁屏') || s.startsWith('声音') || s.startsWith('备用铃声')).join(' · ');

    return PopScope(canPop: false, child: Dialog(
      backgroundColor: Colors.transparent, elevation: 0, insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520,
          maxHeight: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom - 48).clamp(200.0, 1000.0).toDouble()),
        child: Container(
          decoration: BoxDecoration(
            color: MemoColor.surface,
            borderRadius: BorderRadius.circular(MemoRadius.xxl),
            boxShadow: MemoShadow.float,
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 24, 22, 10),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 44, height: 44,
                  decoration: const BoxDecoration(color: MemoColor.brand100, shape: BoxShape.circle),
                  child: const Icon(Icons.schedule_rounded, color: MemoColor.brand500, size: 24)),
                const SizedBox(width: MemoSpace.md),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('首次提醒', style: MemoText.overline),
                  const SizedBox(height: 4),
                  Text(validTime ? '${_dateLabel(r.date, parsed.reference)} $time' : '日期或时间待确认',
                    style: const TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w800,
                      color: MemoColor.ink, fontFeatures: MemoText.tabular)),
                ])),
              ]),
              const SizedBox(height: MemoSpace.xl),
              Container(padding: const EdgeInsets.all(MemoSpace.lg),
                decoration: BoxDecoration(color: MemoColor.brand50, borderRadius: BorderRadius.circular(MemoRadius.lg)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('提醒内容', style: MemoText.overline),
                  const SizedBox(height: 6),
                  Text(r.text.isEmpty ? '没有识别到提醒正文' : r.text,
                    style: MemoText.title.copyWith(fontSize: 20, height: 1.5)),
                ])),
              const SizedBox(height: MemoSpace.lg),
              const Divider(height: 1, color: MemoColor.line),
              MemoMetaRow(label: '语音播报', value: _pill(
                '${speechOn ? '已开启' : '已关闭'}${r.speechMode == 'inherit' ? ' · 默认' : ''}', on: speechOn)),
              const Divider(height: 1, color: MemoColor.line),
              MemoMetaRow(label: '未确认时', value: Text(
                r.totalCount <= 1 ? '仅提醒一次' : '每隔 ${r.intervalMinutes} 分钟提醒',
                textAlign: TextAlign.right, style: MemoText.body)),
              const Divider(height: 1, color: MemoColor.line),
              MemoMetaRow(label: '提醒次数', value: Text('共 ${r.totalCount} 次（含首次）',
                textAlign: TextAlign.right, style: MemoText.body)),
              if (r.repeat != 'none')
                MemoMetaRow(label: '重复安排', value: Text(r.repeatLabel, textAlign: TextAlign.right, style: MemoText.body)),
              const SizedBox(height: MemoSpace.xs),
              const MemoHint('确认已读后停止后续提醒。'),
              if (extra.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: MemoHint(extra)),
              if (error != null) Container(
                margin: const EdgeInsets.only(top: MemoSpace.md),
                padding: const EdgeInsets.all(MemoSpace.md),
                decoration: BoxDecoration(color: MemoColor.dangerSurface, borderRadius: BorderRadius.circular(MemoRadius.sm)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline_rounded, size: 18, color: MemoColor.danger),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error, style: MemoText.label.copyWith(color: MemoColor.danger, height: 1.5))),
                ])),
              const SizedBox(height: MemoSpace.xl),
              Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(color: MemoColor.brand100, borderRadius: BorderRadius.circular(MemoRadius.md)),
                child: Row(children: [
                  Icon(listening ? Icons.mic_rounded : Icons.info_outline_rounded, color: MemoColor.brand700, size: 20),
                  const SizedBox(width: 9),
                  Expanded(child: Text(status, style: MemoText.label.copyWith(
                    color: MemoColor.brand800, fontWeight: FontWeight.w600))),
                  if (listening) ValueListenableBuilder<int>(valueListenable: flow.countdown,
                    builder: (_, seconds, __) => Text('$seconds 秒',
                      style: MemoText.caption.copyWith(color: MemoColor.brand700, fontFeatures: MemoText.tabular))),
                ])),
              const Padding(padding: EdgeInsets.only(top: 8, bottom: 14),
                child: MemoHint('可说“确认”“重新录音”或“取消”。', align: TextAlign.center)),
              LayoutBuilder(builder: (context, size) {
                final again = OutlinedButton.icon(onPressed: saving ? null : flow.startRecording,
                  icon: const Icon(Icons.mic_none_rounded, size: 19), label: const Text('重新录音'));
                final edit = OutlinedButton.icon(onPressed: saving ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 19), label: const Text('手动编辑'));
                if (size.maxWidth < 280 || MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [again, const SizedBox(height: 8), edit]);
                }
                return Row(children: [Expanded(child: again), const SizedBox(width: 10), Expanded(child: edit)]);
              }),
              const SizedBox(height: MemoSpace.md),
              FilledButton(onPressed: saving || error != null ? null : () { HapticFeedback.lightImpact(); flow.confirm(); },
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                child: Text(saving ? '正在保存…' : '确认创建', style: MemoText.button.copyWith(fontSize: 16))),
              const SizedBox(height: 2),
              TextButton(onPressed: saving ? null : flow.cancel,
                child: Text('取消', style: MemoText.body.copyWith(color: MemoColor.muted))),
            ])),
        ),
      ),
    ));
  });
}
