import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';

/// A pill segmented control: a recessed track, one raised white thumb.
///
/// Used where a page has two or three *views of the same list* (all / done /
/// archived) and a tab bar would be too heavy. The thumb is a real surface —
/// white, one contact shadow — so the selection reads as a physical switch
/// rather than a tinted rectangle.
class MemoSegmentBar extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  const MemoSegmentBar({super.key, required this.labels, required this.index,
    required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 38, padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(MemoRadius.pill),
        border: Border.all(color: c.line, width: .6)),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(child: Semantics(button: true, selected: i == index, label: labels[i],
            child: GestureDetector(behavior: HitTestBehavior.opaque,
              onTap: () {
                if (i == index) return;
                HapticFeedback.selectionClick();
                onChanged(i);
              },
              child: AnimatedContainer(duration: MemoMotion.fast, curve: MemoMotion.curve,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == index ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(MemoRadius.pill),
                  boxShadow: i == index ? MemoShadow.disc : null),
                child: Text(labels[i], maxLines: 1, style: TextStyle(fontSize: 13, height: 1.2,
                  fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                  color: i == index ? c.ink : c.muted)))))),
      ]),
    );
  }
}
