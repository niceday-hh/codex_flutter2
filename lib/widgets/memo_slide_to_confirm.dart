import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';

/// Swipe-to-confirm. Replaces the old [Slider] on the reminder detail page.
///
/// Why: a slider is a *value* control — it reads as "pick a number", it needs a
/// 48dp grab target, and it shows a value bubble. Acknowledge is a one-way
/// action, so the affordance should be a single unidirectional drag. This also
/// removes a Material state layer that re-laid out on every drag frame.
///
/// Motion: only while the finger is down (duration zero) plus a 140ms snap-back
/// when released short of the threshold. Nothing runs on a ticker.
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

  double _progress = 0;
  bool _dragging = false, _busy = false;

  Future<void> _confirm() async {
    if (_busy || !widget.enabled) return;
    HapticFeedback.mediumImpact();
    setState(() { _busy = true; _progress = 1; });
    try {
      await widget.onConfirm();
    } finally {
      if (mounted) setState(() { _busy = false; _progress = 0; _dragging = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_busy;
    final duration = _dragging ? Duration.zero : MemoMotion.fast;
    return LayoutBuilder(builder: (context, box) {
      final maxDrag = (box.maxWidth - _height).clamp(1.0, double.infinity);
      final left = _inset + maxDrag * _progress;
      return Semantics(
        button: true,
        label: widget.label,
        hint: '向右滑动',
        onTap: enabled ? _confirm : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: enabled ? (_) => setState(() => _dragging = true) : null,
          onHorizontalDragUpdate: enabled ? (d) {
            setState(() => _progress = (_progress + d.delta.dx / maxDrag).clamp(0.0, 1.0));
          } : null,
          onHorizontalDragEnd: enabled ? (_) {
            setState(() => _dragging = false);
            if (_progress >= .88) { _confirm(); } else { setState(() => _progress = 0); }
          } : null,
          onHorizontalDragCancel: enabled ? () => setState(() { _dragging = false; _progress = 0; }) : null,
          child: Container(
            height: _height,
            decoration: BoxDecoration(
              color: enabled ? context.colors.brand100 : context.colors.canvas,
              borderRadius: BorderRadius.circular(MemoRadius.pill),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              AnimatedContainer(
                duration: duration,
                curve: MemoMotion.curve,
                width: left + _thumb + _inset,
                height: _height,
                decoration: BoxDecoration(
                  color: enabled ? context.colors.brand500 : context.colors.lineStrong,
                  borderRadius: BorderRadius.circular(MemoRadius.pill),
                ),
              ),
              Center(child: Opacity(
                opacity: (1 - _progress * 1.8).clamp(0.0, 1.0),
                child: Text(widget.label, style: context.text.subtitle.copyWith(
                  color: enabled ? context.colors.brand700 : context.colors.muted)),
              )),
              AnimatedPositioned(
                duration: duration,
                curve: MemoMotion.curve,
                left: left, top: _inset,
                child: Container(
                  width: _thumb, height: _thumb,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: MemoShadow.card,
                  ),
                  child: _busy
                    ?  Padding(padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.brand500))
                    : Icon(widget.icon, size: 24, color: enabled ? context.colors.brand500 : context.colors.muted),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}
