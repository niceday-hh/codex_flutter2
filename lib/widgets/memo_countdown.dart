import 'dart:async';

import 'package:flutter/material.dart';

/// A span, not a timestamp: "2 小时 15 分钟".
///
/// Minute precision inside a day; hours once it is further out. "2 天 0 小时
/// 15 分钟" is a measurement, not a plan — and on a card that answers "how long
/// until the next one", the days are what matter.
String memoDistance(Duration d) {
  final span = d.abs();
  if (span.inMinutes < 1) return '不到 1 分钟';
  if (span.inHours < 1) return '${span.inMinutes} 分钟';
  if (span.inDays < 1) {
    final minutes = span.inMinutes % 60;
    return minutes == 0 ? '${span.inHours} 小时' : '${span.inHours} 小时 $minutes 分钟';
  }
  final hours = span.inHours % 24;
  return hours == 0 ? '${span.inDays} 天' : '${span.inDays} 天 $hours 小时';
}

/// Distance from now to [target], repainted on the minute.
///
/// It owns its timer on purpose: the hero card also holds buttons, a title and
/// a gradient, and rebuilding all of that once a minute to move one number is
/// how a static screen starts costing frames. The tick is aligned to the wall
/// clock, so "3 分钟" flips to "2 分钟" when the clock does, not 43 seconds
/// after the widget was built.
class MemoCountdown extends StatefulWidget {
  final DateTime target;
  final TextStyle style;

  /// Reads "已提醒 12 分钟" under an unread card; "已过 …" for a paused one.
  final String pastPrefix;

  /// "后" for the future; empty turns it into a plain span.
  final String futureSuffix;

  /// Used instead of "不到 1 分钟后".
  final String imminentLabel;

  const MemoCountdown({
    super.key,
    required this.target,
    required this.style,
    this.pastPrefix = '已过 ',
    this.futureSuffix = '后',
    this.imminentLabel = '即将提醒',
  });

  @override
  State<MemoCountdown> createState() => _MemoCountdownState();
}

class _MemoCountdownState extends State<MemoCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant MemoCountdown old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      _timer?.cancel();
      _arm();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _arm() {
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute)
      .add(const Duration(minutes: 1));
    _timer = Timer(nextMinute.difference(now) + const Duration(milliseconds: 40), () {
      if (!mounted) return;
      setState(() {});
      _arm();
    });
  }

  String _label(DateTime now) {
    final d = widget.target.difference(now);
    if (d.isNegative) return '${widget.pastPrefix}${memoDistance(d)}';
    if (d.inMinutes < 1) return widget.imminentLabel;
    return '${memoDistance(d)}${widget.futureSuffix}';
  }

  @override
  Widget build(BuildContext context) => Text(_label(DateTime.now()),
    maxLines: 1, overflow: TextOverflow.ellipsis, style: widget.style);
}
