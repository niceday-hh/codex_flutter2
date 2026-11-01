import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';

/// The floating tab bar.
///
/// A flush Material bar draws a hard edge across the bottom of a page whose
/// whole idea is soft surfaces, and it leaves the primary action stranded in a
/// corner. This is one capsule hovering 10dp above the system inset with the
/// create button sitting *in* it: four destinations split 2 + 2 around the
/// disc, so the middle of the bar is the middle of the app.
///
/// The shape is borrowed; the numbers are ours — 64dp tall, 28dp radius, 16dp
/// side inset, 56dp disc lifted 8dp above the capsule's top edge.
class MemoTabBar extends StatelessWidget {
  /// Index of the visible page. Exposed by name (not `selectedIndex`) because
  /// this is not a [NavigationBar]; the tests read it directly.
  final int index;
  final ValueChanged<int> onSelect;

  /// The disc in the middle. Null when batch mode owns the bottom of the
  /// screen, in which case the bar is not built at all.
  final VoidCallback? onCreate;

  const MemoTabBar({super.key, required this.index, required this.onSelect, this.onCreate});

  static const List<(IconData, IconData, String)> items = <(IconData, IconData, String)>[
    (Icons.description_outlined, Icons.description_rounded, '备忘录'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, '日历'),
    (Icons.mic_none_rounded, Icons.mic_rounded, '语音'),
    (Icons.settings_outlined, Icons.settings_rounded, '设置'),
  ];

  /// The gap the disc sits in. 76 rather than 56 leaves 10dp of air on each
  /// side, which is what stops the disc from looking wedged between labels.
  static const double discGap = 76;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SizedBox(height: 64, child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(MemoRadius.xxl),
            boxShadow: MemoShadow.float,
            // On a near-black page a shadow is invisible, so the capsule is
            // separated by a 6% white hairline instead — same trick as the
            // cards, same reason.
            border: dark ? Border.all(color: Colors.white.withValues(alpha: .08))
              : Border.all(color: c.line, width: .6),
          ),
          child: Row(children: [
            _item(context, 0), _item(context, 1),
            const SizedBox(width: discGap),
            _item(context, 2), _item(context, 3),
          ]),
        )),
        if (onCreate != null) Positioned(left: 0, right: 0, top: -10,
          child: Center(child: _CreateDisc(onTap: onCreate!))),
      ])),
    );
  }

  Widget _item(BuildContext context, int i) {
    final on = index == i;
    final c = context.colors;
    final item = items[i];
    return Expanded(child: Semantics(
      // The label is read by the screen reader, so the Text inside must not
      // be announced a second time; and at 1.6× system type a 3-character
      // label is wider than the 53dp slot a 320dp screen gives it.
      button: true, selected: on, label: item.$3, excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(i),
        child: SizedBox(height: 64, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // 1.06, not 1.2: the icon is 21dp, so the whole move is 1.3dp per
          // edge — enough to feel like the tab grew, not enough to nudge the
          // label underneath it.
          AnimatedScale(scale: on ? 1.06 : 1, duration: MemoMotion.base,
            curve: Curves.easeOutCubic,
            child: Icon(on ? item.$2 : item.$1, size: 21,
              color: on ? c.brand600 : c.muted)),
          const SizedBox(height: 3),
          // copyWith on the inherited style, not a fresh TextStyle: a bare
          // TextStyle drops the theme's font family and fallback chain, and
          // every CJK label turns into tofu on a device whose default face has
          // no Han glyphs.
          AnimatedDefaultTextStyle(duration: MemoMotion.fast, curve: MemoMotion.curve,
            style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12, height: 1.12,
              fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              color: on ? c.brand600 : c.muted),
            child: Text(item.$3, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ])),
      )));
  }
}

/// The middle disc: a gradient circle that dips under the finger.
///
/// A real [FloatingActionButton] would bring the Material elevation shadow,
/// the 48dp ripple and a square hit box; this is a 56dp circle that scales to
/// 0.94 and stops, which is the same feedback the rest of the app uses.
class _CreateDisc extends StatefulWidget {
  final VoidCallback onTap;
  const _CreateDisc({required this.onTap});

  @override State<_CreateDisc> createState() => _CreateDiscState();
}

class _CreateDiscState extends State<_CreateDisc> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(message: '新建提醒',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () { HapticFeedback.mediumImpact(); widget.onTap(); },
        child: AnimatedScale(scale: _down ? .94 : 1, duration: MemoMotion.press,
          curve: MemoMotion.curve,
          // A 3px ring in the bar's own colour, not a drop shadow. The disc is
          // half-sunk in the capsule, so any shadow long enough to read as
          // light also pooled underneath it as a purple crescent. The ring
          // cuts the disc out of the surface instead, which is the same trick
          // the card corners use: the shape, not the shadow, says "raised".
          child: Container(width: 56, height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [c.brand400, c.brand600]),
              border: Border.all(color: c.surface, width: 3)),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 26))),
      ));
  }
}
