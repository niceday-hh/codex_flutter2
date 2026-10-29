import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Bottom-sheet chrome: grab handle, title, optional "located entry" hint, body.
///
/// Replaces the old frosted panel here. The sheet used a full-width
/// `BackdropFilter` behind a 92%-height surface, which forced an offscreen
/// compose of the entire screen on the first frame of every open. A solid
/// surface is indistinguishable at this opacity and costs one rounded clip.
class MemoSheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final String? hint;
  final VoidCallback? onClose;

  const MemoSheetShell({super.key, required this.title, required this.child, this.hint, this.onClose});

  @override
  Widget build(BuildContext context) => Container(
    decoration:  BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(MemoRadius.xxl)),
      boxShadow: MemoShadow.sheet,
    ),
    clipBehavior: Clip.antiAlias,
    child: SafeArea(
      top: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: context.colors.lineStrong, borderRadius: BorderRadius.circular(MemoRadius.pill)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 14, 12),
          child: Row(children: [
            Expanded(child: Text(title, style: context.text.title)),
            if (onClose != null)
              IconButton(
                tooltip: '关闭设置分类',
                onPressed: onClose,
                style: IconButton.styleFrom(backgroundColor: context.colors.brand100, foregroundColor: context.colors.muted),
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
          ]),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
            child: Row(children: [
               Icon(Icons.search_rounded, size: 15, color: context.colors.brand500),
              const SizedBox(width: 6),
              Expanded(child: Text(hint!, style: context.text.caption.copyWith(color: context.colors.brand700))),
            ]),
          ),
        Expanded(child: child),
      ]),
    ),
  );
}
