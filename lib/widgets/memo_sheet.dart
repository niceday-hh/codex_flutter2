import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Bottom-sheet chrome: grab handle, title, optional "located entry" hint, body.
///
/// Uses a solid surface (no full-screen BackdropFilter offscreen compose) paired
/// with a subtle 1px hairline rim for crisp dark-mode elevation.
class MemoSheetShell extends StatelessWidget {
  final String title;
  final Widget child;
  final String? hint;
  final VoidCallback? onClose;

  const MemoSheetShell({
    super.key,
    required this.title,
    required this.child,
    this.hint,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rimColor = isDark
        ? Colors.white.withValues(alpha: 0.09)
        : c.line.withValues(alpha: 0.72);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(MemoRadius.xxl),
        ),
        border: Border(
          top: BorderSide(color: rimColor, width: 1),
          left: BorderSide(color: rimColor, width: 0.5),
          right: BorderSide(color: rimColor, width: 0.5),
        ),
        boxShadow: MemoShadow.sheet,
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.22)
                    : c.lineStrong,
                borderRadius: BorderRadius.circular(MemoRadius.pill),
              ),
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
                  style: IconButton.styleFrom(
                    backgroundColor: c.brand100,
                    foregroundColor: c.muted,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
            ]),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.brand100.withValues(alpha: isDark ? 0.35 : 0.65),
                  borderRadius: BorderRadius.circular(MemoRadius.sm),
                ),
                child: Row(children: [
                  Icon(Icons.search_rounded, size: 15, color: c.brand500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hint!,
                      style: context.text.caption.copyWith(color: c.brand700),
                    ),
                  ),
                ]),
              ),
            ),
          Expanded(child: child),
        ]),
      ),
    );
  }
}
