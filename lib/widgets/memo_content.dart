import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Page-level title block: 30px display + one line of muted context.
class MemoPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  const MemoPageHeader({super.key, required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(MemoSpace.xxl, MemoSpace.xxl, MemoSpace.xxl, MemoSpace.xl),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: MemoText.display),
        const SizedBox(height: 6),
        Text(subtitle, style: MemoText.body.copyWith(color: MemoColor.muted)),
      ])),
      if (trailing != null) trailing!,
    ]),
  );
}

/// Section label with an optional count on the right.
class MemoSectionHeader extends StatelessWidget {
  final String title;
  final String trailing;
  const MemoSectionHeader(this.title, {this.trailing = '', super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(MemoSpace.xxl, MemoSpace.xxl + 4, MemoSpace.xxl, MemoSpace.md),
    child: Row(children: [
      Text(title, style: MemoText.headline),
      const Spacer(),
      if (trailing.isNotEmpty) Text(trailing, style: MemoText.caption),
    ]),
  );
}

/// Empty state with exactly one call to action. Never more than one.
class MemoEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const MemoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(MemoSpace.xxl, MemoSpace.xxl, MemoSpace.xxl, MemoSpace.xxxl),
    child: Column(children: [
      Container(
        width: 76, height: 76,
        decoration: const BoxDecoration(color: MemoColor.brand100, shape: BoxShape.circle),
        child: Icon(icon, size: 32, color: MemoColor.brand500),
      ),
      const SizedBox(height: MemoSpace.xl),
      Text(title, textAlign: TextAlign.center, style: MemoText.headline),
      const SizedBox(height: MemoSpace.sm),
      Text(subtitle, textAlign: TextAlign.center, style: MemoText.label.copyWith(color: MemoColor.muted)),
      if (actionLabel != null) ...[
        const SizedBox(height: MemoSpace.xl),
        FilledButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: Text(actionLabel!),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 22)),
        ),
      ],
    ]),
  );
}

/// Search input: white fill, hairline border, brand focus ring. The old design
/// used a #EEEDF3 fill on white — 1.09:1, invisible in daylight.
class MemoSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final bool showClear;
  final Key? fieldKey;

  const MemoSearchField({
    super.key,
    this.controller,
    this.hint = '搜索',
    this.onChanged,
    this.onClear,
    this.showClear = false,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    style: MemoText.body,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: MemoText.body.copyWith(color: MemoColor.muted),
      filled: true,
      fillColor: MemoColor.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 13),
      prefixIcon: const Icon(Icons.search_rounded, color: MemoColor.muted, size: 21),
      suffixIcon: showClear
        ? IconButton(
            tooltip: '清空搜索',
            icon: const Icon(Icons.close_rounded, size: 19, color: MemoColor.muted),
            onPressed: onClear)
        : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MemoRadius.md),
        borderSide: const BorderSide(color: MemoColor.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MemoRadius.md),
        borderSide: const BorderSide(color: MemoColor.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MemoRadius.md),
        borderSide: const BorderSide(color: MemoColor.brand600, width: 1.6),
      ),
    ),
  );
}

/// Label / value row used by the confirmation dialog and the reminder detail.
class MemoMetaRow extends StatelessWidget {
  final String label;
  final Widget value;
  const MemoMetaRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 2, child: Text(label, style: MemoText.body.copyWith(color: MemoColor.muted))),
      const SizedBox(width: MemoSpace.md),
      Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: value)),
    ]),
  );
}

/// Small print. One style, so nobody re-invents 11px grey text.
class MemoHint extends StatelessWidget {
  final String text;
  final TextAlign align;
  final EdgeInsetsGeometry padding;
  const MemoHint(this.text, {super.key, this.align = TextAlign.start, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(text, textAlign: align, style: MemoText.caption.copyWith(height: 1.6)),
  );
}
