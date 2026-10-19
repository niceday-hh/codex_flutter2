import 'package:flutter/material.dart';
import 'app_style.dart';
import 'voice_flow.dart';

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

  Widget _row(String label, Widget value) => Padding(padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 2, child: Text(label, style: const TextStyle(color: muted, fontSize: 14))),
      const SizedBox(width: 12), Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: value)),
    ]));

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
    return PopScope(canPop: false, child: Dialog(backgroundColor: Colors.transparent, elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 520,
        maxHeight: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom - 48).clamp(200.0, 1000.0).toDouble()),
        child: FrostedPanel(child: Padding(padding: const EdgeInsets.fromLTRB(22, 26, 22, 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Flexible(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 44, height: 44, decoration: const BoxDecoration(color: lavender, shape: BoxShape.circle),
                  child: const Icon(Icons.schedule_rounded, color: purple, size: 27)), const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('首次提醒', style: TextStyle(color: muted, fontSize: 13)), const SizedBox(height: 7),
                  Text(validTime ? '${_dateLabel(r.date, parsed.reference)} $time' : '日期或时间待确认',
                    style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, height: 1.25, color: ink)),
                ])),
              ]),
              const SizedBox(height: 24),
              Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(
                color: lavender.withValues(alpha: .72), borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('提醒内容', style: TextStyle(color: muted, fontSize: 12)), const SizedBox(height: 9),
                  Text(r.text.isEmpty ? '没有识别到提醒正文' : r.text,
                    style: const TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700, height: 1.5)),
                ])),
              const SizedBox(height: 16), const Divider(height: 1, color: Color(0xFFE8E5EF)),
              _row('语音播报', Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(color: speechOn ? const Color(0xFFE5DEFF) : const Color(0xFFEEEDF2), borderRadius: BorderRadius.circular(11)),
                child: Text('${speechOn ? '已开启' : '已关闭'}${r.speechMode == 'inherit' ? ' · 默认' : ''}',
                  style: TextStyle(color: speechOn ? purple : muted, fontWeight: FontWeight.w600, fontSize: 13)))),
              const Divider(height: 1, color: Color(0xFFE8E5EF)),
              _row('未确认时', Text(r.totalCount <= 1 ? '仅提醒一次' : '每隔 ${r.intervalMinutes} 分钟提醒',
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 14))),
              const Divider(height: 1, color: Color(0xFFE8E5EF)),
              _row('提醒次数', Text('共 ${r.totalCount} 次（含首次）', textAlign: TextAlign.right, style: const TextStyle(fontSize: 14))),
              if (r.repeat != 'none') _row('重复安排', Text(r.repeatLabel, textAlign: TextAlign.right)),
              const Text('确认已读后停止后续提醒。', style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
              if (parsed.settings.any((s) => s.startsWith('锁屏') || s.startsWith('声音') || s.startsWith('备用铃声')))
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(parsed.settings.where((s) =>
                  s.startsWith('锁屏') || s.startsWith('声音') || s.startsWith('备用铃声')).join(' · '),
                  style: const TextStyle(color: muted, fontSize: 12))),
              if (error != null) Container(margin: const EdgeInsets.only(top: 14), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFEFE5), borderRadius: BorderRadius.circular(12)),
                child: Text(error, style: const TextStyle(color: Color(0xFFA75A28), fontSize: 13, height: 1.5))),
              const SizedBox(height: 20),
            ]))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              decoration: BoxDecoration(color: lavender, borderRadius: BorderRadius.circular(15)),
              child: Row(children: [Icon(listening ? Icons.mic_rounded : Icons.info_outline_rounded, color: purple, size: 21),
                const SizedBox(width: 9), Expanded(child: Text(status, style: const TextStyle(color: purple, fontSize: 14, fontWeight: FontWeight.w600))),
                if (listening) Text('${flow.secondsLeft} 秒', style: const TextStyle(color: purple, fontSize: 12)),
              ])),
            const Padding(padding: EdgeInsets.only(top: 9, bottom: 17), child: Text('可说“确认”“重新录音”或“取消”。',
              style: TextStyle(color: muted, fontSize: 12, height: 1.6))),
            LayoutBuilder(builder: (context, size) {
              final again = OutlinedButton.icon(onPressed: saving ? null : flow.startRecording,
                icon: const Icon(Icons.mic_none_rounded, size: 20), label: const Text('重新录音'));
              final edit = OutlinedButton.icon(onPressed: saving ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20), label: const Text('手动编辑'));
              if (size.maxWidth < 280 || MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [again, const SizedBox(height: 8), edit]);
              }
              return Row(children: [Expanded(child: again), const SizedBox(width: 10), Expanded(child: edit)]);
            }),
            const SizedBox(height: 12),
            FilledButton(onPressed: saving || error != null ? null : flow.confirm,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: Text(saving ? '正在保存…' : '确认创建', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            const SizedBox(height: 3), TextButton(onPressed: saving ? null : flow.cancel,
              child: const Text('取消', style: TextStyle(color: muted))),
          ]))))));
  });
}
