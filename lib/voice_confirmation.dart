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

  Widget _pill(BuildContext context, String text, {required bool on}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: on ? context.colors.brand200 : context.colors.brand50,
      borderRadius: BorderRadius.circular(MemoRadius.sm),
    ),
    child: Text(text, style: context.text.caption.copyWith(
      color: on ? context.colors.brand800 : context.colors.muted, fontWeight: FontWeight.w600)),
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
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(MemoRadius.xxl),
            boxShadow: MemoShadow.float,
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 24, 22, 10),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 44, height: 44,
                  decoration:  BoxDecoration(color: context.colors.brand100, shape: BoxShape.circle),
                  child:  Icon(Icons.schedule_rounded, color: context.colors.brand500, size: 24)),
                const SizedBox(width: MemoSpace.md),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('首次提醒', style: context.text.overline),
                  const SizedBox(height: 4),
                  Text(validTime ? '${_dateLabel(r.date, parsed.reference)} $time' : '日期或时间待确认',
                    style: context.text.heroTime.copyWith(color: context.colors.ink,
                      fontSize: 26, height: 1.2)),
                ])),
              ]),
              const SizedBox(height: MemoSpace.xl),
              Container(padding: const EdgeInsets.all(MemoSpace.lg),
                decoration: BoxDecoration(color: context.colors.brand50, borderRadius: BorderRadius.circular(MemoRadius.lg)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('提醒内容', style: context.text.overline),
                  const SizedBox(height: 6),
                  Text(r.text.isEmpty ? '没有识别到提醒正文' : r.text,
                    style: context.text.title.copyWith(fontSize: 20, height: 1.5)),
                ])),
              const SizedBox(height: MemoSpace.lg),
               Divider(height: 1, color: context.colors.line),
              MemoMetaRow(label: '语音播报', value: _pill(context, 
                '${speechOn ? '已开启' : '已关闭'}${r.speechMode == 'inherit' ? ' · 默认' : ''}', on: speechOn)),
               Divider(height: 1, color: context.colors.line),
              MemoMetaRow(label: '未确认时', value: Text(
                r.totalCount <= 1 ? '仅提醒一次' : '每隔 ${r.intervalMinutes} 分钟提醒',
                textAlign: TextAlign.right, style: context.text.body)),
               Divider(height: 1, color: context.colors.line),
              MemoMetaRow(label: '提醒次数', value: Text('共 ${r.totalCount} 次（含首次）',
                textAlign: TextAlign.right, style: context.text.body)),
              if (r.repeat != 'none')
                MemoMetaRow(label: '重复安排', value: Text(r.repeatLabel, textAlign: TextAlign.right, style: context.text.body)),
              const SizedBox(height: MemoSpace.xs),
              const MemoHint('确认已读后停止后续提醒。'),
              if (extra.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: MemoHint(extra)),
              if (error != null) Container(
                margin: const EdgeInsets.only(top: MemoSpace.md),
                padding: const EdgeInsets.all(MemoSpace.md),
                decoration: BoxDecoration(color: context.colors.dangerSurface, borderRadius: BorderRadius.circular(MemoRadius.sm)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                   Icon(Icons.error_outline_rounded, size: 18, color: context.colors.danger),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error, style: context.text.label.copyWith(color: context.colors.danger, height: 1.5))),
                ])),
              const SizedBox(height: MemoSpace.xl),
              Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(color: context.colors.brand100, borderRadius: BorderRadius.circular(MemoRadius.md)),
                child: Row(children: [
                  Icon(listening ? Icons.mic_rounded : Icons.info_outline_rounded, color: context.colors.brand700, size: 20),
                  const SizedBox(width: 9),
                  Expanded(child: Text(status, style: context.text.label.copyWith(
                    color: context.colors.brand800, fontWeight: FontWeight.w600))),
                  if (listening) ValueListenableBuilder<int>(valueListenable: flow.countdown,
                    builder: (_, seconds, __) => Text('$seconds 秒',
                      style: context.text.caption.copyWith(color: context.colors.brand700, fontFeatures: MemoText.tabular))),
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
                child: Text(saving ? '正在保存…' : '确认创建', style: context.text.button.copyWith(fontSize: 16))),
              const SizedBox(height: 2),
              TextButton(onPressed: saving ? null : flow.cancel,
                child: Text('取消', style: context.text.body.copyWith(color: context.colors.muted))),
            ])),
        ),
      ),
    ));
  });
}
