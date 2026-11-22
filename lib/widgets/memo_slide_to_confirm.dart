import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';

/// Swipe-to-confirm. Replaces the old [Slider] on the reminder detail page.
///
/// Motion: zero-latency finger tracking during drag, a subtle tactile tick when
/// crossing the 88% commit threshold, and a single-shot elastic snap-back when
/// released early. Nothing runs on an idle ticker.
class MemoSlideToConfirm extends StatefulWidget {
  final String label;
  final IconData icon;
  final Future<void> Function() onConfirm;
  final bool enabled;

  const MemoSlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirm,
    this.icon = Icons.check_rounded,
    this.enabled = true,
  });

  @override
  State<MemoSlideToConfirm> createState() => _MemoSlideToConfirmState();
}

class _MemoSlideToConfirmState extends State<MemoSlideToConfirm> {
  static const _height = 56.0;
  static const _inset = 4.0;
  static const _thumb = _height - _inset * 2;
  static const _threshold = 0.88;

  double _progress = 0;
  bool _dragging = false, _busy = false, _thresholdReached = false;

  Future<void> _confirm() async {
    if (_busy || !widget.enabled) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _progress = 1;
      _thresholdReached = false;
    });
    try {
      await widget.onConfirm();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = 0;
          _dragging = false;
          _thresholdReached = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.enabled && !_busy;
    final duration = _dragging ? Duration.zero : MemoMotion.base;
    final curve = _dragging ? Curves.linear : Curves.easeOutBack;

    return LayoutBuilder(builder: (context, box) {
      final maxDrag = (box.maxWidth - _height).clamp(1.0, double.infinity);
      final left = _inset + maxDrag * _progress;
      final armed = _dragging && _progress >= _threshold;

      return Semantics(
        button: true,
        label: widget.label,
        hint: '向右滑动',
        onTap: enabled ? _confirm : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: enabled
              ? (_) => setState(() {
                    _dragging = true;
                    _thresholdReached = false;
                  })
              : null,
          onHorizontalDragUpdate: enabled
              ? (d) {
                  final next = (_progress + d.delta.dx / maxDrag).clamp(0.0, 1.0);
                  final nowReached = next >= _threshold;
                  if (nowReached && !_thresholdReached) {
                    HapticFeedback.selectionClick();
                  }
                  setState(() {
                    _progress = next;
                    _thresholdReached = nowReached;
                  });
                }
              : null,
          onHorizontalDragEnd: enabled
              ? (_) {
                  setState(() => _dragging = false);
                  if (_progress >= _threshold) {
                    _confirm();
                  } else {
                    setState(() {
                      _progress = 0;
                      _thresholdReached = false;
                    });
                  }
                }
              : null,
          onHorizontalDragCancel: enabled
              ? () => setState(() {
                    _dragging = false;
                    _progress = 0;
                    _thresholdReached = false;
                  })
              : null,
          child: Container(
            height: _height,
            decoration: BoxDecoration(
              color: enabled ? c.brand100 : c.canvas,
              borderRadius: BorderRadius.circular(MemoRadius.pill),
              border: Border.all(
                color: armed
                    ? c.brand500.withValues(alpha: 0.45)
                    : c.line.withValues(alpha: enabled ? 0.55 : 0.25),
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              AnimatedContainer(
                duration: duration,
                curve: curve,
                width: (left + _thumb + _inset).clamp(_height, box.maxWidth),
                height: _height,
                decoration: BoxDecoration(
                  color: enabled
                      ? (armed ? c.brand600 : c.brand500)
                      : c.lineStrong,
                  borderRadius: BorderRadius.circular(MemoRadius.pill),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: (1 - _progress * 1.8).clamp(0.0, 1.0),
                  child: Text(
                    widget.label,
                    style: context.text.subtitle.copyWith(
                      color: enabled ? c.brand700 : c.muted,
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: duration,
                curve: curve,
                left: left.clamp(_inset, _inset + maxDrag),
                top: _inset,
                child: AnimatedScale(
                  scale: _dragging ? 1.04 : 1.0,
                  duration: MemoMotion.press,
                  curve: MemoMotion.curve,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: MemoShadow.card,
                    ),
                    child: _busy
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.brand500,
                            ),
                          )
                        : Icon(
                            widget.icon,
                            size: 24,
                            color: enabled
                                ? (armed ? c.brand600 : c.brand500)
                                : c.muted,
                          ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}
