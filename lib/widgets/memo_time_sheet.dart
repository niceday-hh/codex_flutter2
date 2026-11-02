import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_error.dart';
import '../asr.dart';
import '../design_tokens.dart';
import '../spoken_time.dart';
import '../voice_flow.dart';

/// One fixed step offered next to the wheels. Fixed rather than free-form so
/// the row stays four buttons wide on a 320dp screen.
class MemoTimeShift {
  final String label;
  final Duration shift;
  const MemoTimeShift(this.label, this.shift);
}

const memoTimeShifts = <MemoTimeShift>[
  MemoTimeShift('+15 分钟', Duration(minutes: 15)),
  MemoTimeShift('+30 分钟', Duration(minutes: 30)),
  MemoTimeShift('+1 小时', Duration(hours: 1)),
  MemoTimeShift('明天此时', Duration(days: 1)),
];

/// “今天 21:40”, “明天 09:15”, “11月5日 09:00”.
String memoTimeLabel(DateTime at, {DateTime? now}) => '${memoDayLabel(at, now: now)} '
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

String memoDayLabel(DateTime at, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(at.year, at.month, at.day);
  return switch (day.difference(today).inDays) {
    0 => '今天',
    1 => '明天',
    2 => '后天',
    -1 => '昨天',
    _ => at.year == current.year ? '${at.month}月${at.day}日' : '${at.year}年${at.month}月${at.day}日',
  };
}

/// A row of “move it later” buttons shared by the editor and the detail sheet.
///
/// [base] is the time currently on screen: steps stack on what the user is
/// looking at, not on now, so tapping +15 twice means +30. A base in the past
/// falls back to now — adding to a past instant would only produce another one.
class MemoQuickTimeChips extends StatelessWidget {
  final DateTime base;
  final ValueChanged<DateTime> onPicked;
  final DateTime Function()? now;
  final List<MemoTimeShift> shifts;
  final bool enabled, compact;

  const MemoQuickTimeChips({super.key, required this.base, required this.onPicked,
    this.now, this.shifts = memoTimeShifts, this.enabled = true, this.compact = false});

  @override Widget build(BuildContext context) {
    final current = (now ?? DateTime.now)();
    final from = base.isAfter(current) ? base : current;
    return Wrap(spacing: compact ? 6 : 8, runSpacing: 8, children: [
      for (final shift in shifts) TextButton(
        onPressed: enabled ? () {
          HapticFeedback.selectionClick();
          final target = from.add(shift.shift);
          // Minute precision: the caller writes this into a reminder whose
          // time is shown as HH:mm, so carrying now's seconds into it would
          // make the sheet say 21:40 and the alarm fire at 21:40:53.
          onPicked(DateTime(target.year, target.month, target.day, target.hour, target.minute));
        } : null,
        style: TextButton.styleFrom(
          backgroundColor: context.colors.brand50,
          foregroundColor: context.colors.brand800,
          disabledBackgroundColor: context.colors.surfaceAlt,
          minimumSize: const Size(0, 44),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          textStyle: compact ? context.text.caption.copyWith(fontWeight: FontWeight.w600) : null,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
        ),
        child: Text(shift.label, style: context.text.label.copyWith(
          color: enabled ? context.colors.brand800 : context.colors.muted,
          fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

/// Opens the time picker.
///
/// Returns the instant to move to, or null when dismissed. The sheet deliberately
/// replaces `showTimePicker`: its dial required dragging a needle, the drag was
/// easy to lose to the surrounding gesture, and minutes moved in visible jumps.
Future<DateTime?> showMemoTimeSheet(BuildContext context, {required DateTime initial,
    String title = '调整时间', bool allowVoice = true, DateTime Function()? now}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // The wheels are a vertical drag and so is dismissal. Whoever wins, the
    // other one feels broken — this is exactly the complaint the sheet fixes,
    // so dismissal is explicit (取消 / 点外部).
    enableDrag: false,
    builder: (_) => MemoTimeSheet(initial: initial, title: title, allowVoice: allowVoice, now: now),
  );
}

enum _Voice { idle, preparing, listening, processing }

class MemoTimeSheet extends StatefulWidget {
  final DateTime initial;
  final String title;
  final bool allowVoice;
  final DateTime Function()? now;

  const MemoTimeSheet({super.key, required this.initial, this.title = '调整时间',
    this.allowVoice = true, this.now});

  @override State<MemoTimeSheet> createState() => _MemoTimeSheetState();
}

class _MemoTimeSheetState extends State<MemoTimeSheet> {
  late DateTime _day;
  late int _hour, _minute;
  _Voice _voice = _Voice.idle;
  String? _heard, _error;
  OfflineVoiceCapture? _capture;
  Timer? _limit;
  bool _stopping = false;

  DateTime get _now => (widget.now ?? DateTime.now)();
  DateTime get _preview => DateTime(_day.year, _day.month, _day.day, _hour, _minute);

  @override void initState() {
    super.initState();
    final initial = widget.initial;
    _day = DateTime(initial.year, initial.month, initial.day);
    _hour = initial.hour;
    _minute = initial.minute;
  }

  @override void dispose() {
    _limit?.cancel();
    final capture = _capture;
    _capture = null;
    if (capture != null) { unawaited(capture.cancel()); capture.release(); }
    super.dispose();
  }

  void _apply(DateTime at) {
    setState(() {
      _day = DateTime(at.year, at.month, at.day);
      _hour = at.hour;
      _minute = at.minute;
      _heard = null;
      _error = null;
    });
  }

  void _snapHour() {
    // "整点" is a shortcut to the hour, not a reset: if the hour has already
    // passed, the next meaningful one is the coming hour's :00.
    var at = DateTime(_day.year, _day.month, _day.day, _hour);
    if (!at.isAfter(_now)) at = at.add(const Duration(hours: 1));
    _apply(at);
  }

  void _snapNow() {
    final now = _now;
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(const Duration(minutes: 1));
    _apply(next);
  }

  Future<void> _startVoice() async {
    if (_voice != _Voice.idle) return;
    setState(() { _voice = _Voice.preparing; _error = null; _heard = null; });
    final capture = OfflineVoiceCapture(asr);
    _capture = capture;
    try {
      await capture.open();
      if (!mounted || _capture != capture) { capture.release(); return; }
      setState(() => _voice = _Voice.listening);
      await capture.start(1.6, (end) {
        if (!mounted || _capture != capture) return;
        if (end < 0) { _failVoice('人声检测中断，请再说一次'); }
        else { unawaited(_finishVoice()); }
      }, (_) {});
      if (!mounted || _capture != capture) return;
      _limit = Timer(const Duration(seconds: 15), () {
        if (mounted) unawaited(_finishVoice());
      });
    } catch (e) {
      if (mounted) { _failVoice(niceError(e)); }
      else { capture.release(); }
    }
  }

  Future<void> _finishVoice() async {
    final capture = _capture;
    if (capture == null || _stopping) return;
    _stopping = true;
    _limit?.cancel();
    if (mounted) setState(() => _voice = _Voice.processing);
    try {
      final result = await capture.stop();
      if (!mounted) return;
      final text = result.text.trim();
      final parsed = text.isEmpty ? null : parseSpokenTime(text, now: _now,
        from: _preview, preferDate: _day);
      if (parsed == null) {
        setState(() {
          _voice = _Voice.idle;
          _error = text.isEmpty ? '没有听清，请再说一次' : '没听出时间：$text';
        });
      } else {
        _apply(parsed.at);
        setState(() {
          _voice = _Voice.idle;
          _heard = text;
          _error = parsed.warning;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _voice = _Voice.idle; _error = niceError(e); });
    } finally {
      _capture = null;
      capture.release();
      _stopping = false;
    }
  }

  void _failVoice(String message) {
    final capture = _capture;
    _capture = null;
    _limit?.cancel();
    if (capture != null) { unawaited(capture.cancel()); capture.release(); }
    if (mounted) setState(() { _voice = _Voice.idle; _error = message; });
  }

  @override Widget build(BuildContext context) {
    final now = _now;
    final at = _preview;
    // Compared by the minute, not the second: the wheel has no seconds, and
    // opening the sheet a few seconds after the selected minute would
    // otherwise label a perfectly usable time as already past.
    final nowMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final valid = !at.isBefore(nowMinute);
    // A 320dp phone at 1.6x has no room for the full-height wheel. Shrinking
    // it beats letting the sheet run off the top of the screen.
    final compact = MediaQuery.sizeOf(context).height < 640;
    return ConstrainedBox(
      // Scrolls only when it has to: at 1.6x on a 320dp phone the wheels plus
      // two rows of chips do not fit, and clipping the confirm button is worse
      // than asking for one short scroll.
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      child: Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(MemoRadius.xxl)),
        boxShadow: MemoShadow.sheet,
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(top: false, child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(
            color: context.colors.lineStrong, borderRadius: BorderRadius.circular(MemoRadius.pill))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(widget.title, style: context.text.title)),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(backgroundColor: context.colors.brand100,
                foregroundColor: context.colors.muted),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
          ]),
          const SizedBox(height: 4),
          // Wrap, not Row: at 1.6x the 40px clock and the day label no longer
          // fit on one line on a 320dp screen, and a Row would clip them.
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, runSpacing: 2, children: [
            Text('${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
              style: context.text.display.copyWith(fontSize: 40,
                fontFeatures: MemoText.tabular)),
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(
              memoDayLabel(at, now: now), style: context.text.body.copyWith(color: context.colors.muted))),
            if (_voice != _Voice.idle) _voiceBadge(context),
          ]),
          const SizedBox(height: 4),
          _wheels(context, height: compact ? 116 : 150),
          const SizedBox(height: 10),
          MemoQuickTimeChips(base: at, now: () => _now, onPicked: _apply),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _snap(context, '整点', _snapHour),
            _snap(context, '现在', _snapNow),
            if (widget.allowVoice) _snap(context, _voice == _Voice.listening ? '停止' : '说时间',
              _voice == _Voice.listening ? () => unawaited(_finishVoice()) : () => unawaited(_startVoice()),
              icon: _voice == _Voice.listening ? Icons.stop_rounded : Icons.mic_none_rounded,
              emphasized: _voice == _Voice.listening),
          ]),
          if (_heard != null || _error != null || _voice == _Voice.preparing ||
              _voice == _Voice.processing) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_error != null ? Icons.error_outline_rounded : Icons.graphic_eq_rounded,
                size: 16, color: _error != null ? context.colors.danger : context.colors.brand700),
              const SizedBox(width: 6),
              Expanded(child: Text(
                _error ?? (_heard != null ? '听到「$_heard」，已填入下方时间'
                  : _voice == _Voice.preparing ? '正在准备离线模型…' : '正在识别…'),
                style: context.text.caption.copyWith(
                  color: _error != null ? context.colors.danger : context.colors.brand700))),
            ])),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text('取消', style: context.text.button.copyWith(color: context.colors.muted)))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: FilledButton(
              onPressed: valid ? () { HapticFeedback.lightImpact(); Navigator.pop(context, at); } : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(valid ? '确定' : '这个时间已经过去'))),
          ]),
        ]),
      )),
    ));
  }

  Widget _voiceBadge(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: context.colors.brand50,
      borderRadius: BorderRadius.circular(MemoRadius.pill)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(
        color: _voice == _Voice.listening ? context.colors.danger : context.colors.brand500,
        shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(_voice == _Voice.listening ? '正在听' : _voice == _Voice.preparing ? '准备中' : '识别中',
        style: context.text.caption.copyWith(color: context.colors.brand800, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _snap(BuildContext context, String label, VoidCallback onTap, {IconData? icon, bool emphasized = false}) {
    final text = Text(label, style: context.text.label.copyWith(
      color: emphasized ? context.colors.danger : context.colors.brand800,
      fontWeight: FontWeight.w600));
    final style = TextButton.styleFrom(
      backgroundColor: emphasized ? context.colors.dangerSurface : context.colors.surfaceAlt,
      foregroundColor: emphasized ? context.colors.danger : context.colors.brand800,
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const StadiumBorder(),
    );
    if (icon == null) return TextButton(onPressed: onTap, style: style, child: text);
    return TextButton.icon(onPressed: onTap, style: style,
      icon: Icon(icon, size: 17), label: text);
  }

  Widget _wheels(BuildContext context, {double height = 150}) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(MemoRadius.lg)),
      child: Stack(alignment: Alignment.center, children: [
        // The selection band sits behind the wheels and intercepts nothing, so
        // it cannot steal the drag that the wheel is already handling.
        Positioned(left: 18, right: 18, child: IgnorePointer(child: Container(
          height: 46, decoration: BoxDecoration(color: context.colors.brand50,
            borderRadius: BorderRadius.circular(MemoRadius.md)),
        ))),
        Row(children: [
          Expanded(child: _Wheel(value: _hour, max: 23, semantics: '小时',
            onChanged: (v) => setState(() => _hour = v))),
          Text(':', style: context.text.display.copyWith(fontSize: 30,
            color: context.colors.muted, fontFeatures: MemoText.tabular)),
          Expanded(child: _Wheel(value: _minute, max: 59, semantics: '分钟',
            onChanged: (v) => setState(() => _minute = v))),
        ]),
      ]),
    );
  }
}

/// A single digit column. One item = one unit, so minutes are exact rather than
/// rounded to a five-minute detent.
class _Wheel extends StatefulWidget {
  final int value;
  final int max;
  final String semantics;
  final ValueChanged<int> onChanged;

  const _Wheel({required this.value, required this.max, required this.semantics, required this.onChanged});

  @override State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: widget.value);

  @override void didUpdateWidget(covariant _Wheel old) {
    super.didUpdateWidget(old);
    if (!_controller.hasClients || _controller.selectedItem == widget.value) return;
    final target = widget.value;
    // Deferred: jumping also emits a scroll notification, and answering it with
    // setState during a build is exactly the kind of feedback loop that turns a
    // shortcut into a crash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || _controller.selectedItem == target) return;
      final distance = (target - _controller.selectedItem).abs();
      // Jump for a big step: 45 items in 160ms reads as a glitch, not a scroll.
      if (distance > 6) { _controller.jumpToItem(target); }
      else {
        _controller.animateToItem(target,
          duration: const Duration(milliseconds: 160), curve: Curves.easeOutCubic);
      }
    });
  }

  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Semantics(
    label: widget.semantics,
    child: ListWheelScrollView.useDelegate(
      controller: _controller,
      itemExtent: 46,
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 1.8,
      perspective: 0.002,
      squeeze: 1.02,
      onSelectedItemChanged: widget.onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: widget.max + 1,
        builder: (context, index) => Center(child: Text(
          index.toString().padLeft(2, '0'),
          style: TextStyle(
            fontSize: index == widget.value ? 26 : 22,
            height: 1.2,
            fontWeight: index == widget.value ? FontWeight.w600 : FontWeight.w500,
            color: index == widget.value ? context.colors.ink : context.colors.muted,
            fontFeatures: MemoText.tabular,
          ),
        )),
      ),
    ),
  );
}
