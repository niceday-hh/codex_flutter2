import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Page-level title block: 34px display + one line of muted context.
///
/// The gap under the title is deliberately small (8) and the block under it is
/// tight (12): an editorial header groups the title, the kicker and the first
/// piece of content into one mass, instead of leaving them floating apart.
class MemoPageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  const MemoPageHeader({super.key, required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(MemoSpace.xxl, 28, MemoSpace.xxl, 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: context.text.display),
        const SizedBox(height: 8),
        Text(subtitle, style: context.text.body.copyWith(color: context.colors.muted)),
      ])),
      if (trailing != null) Padding(padding: const EdgeInsets.only(bottom: 2), child: trailing!),
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
      Text(title, style: context.text.headline),
      const Spacer(),
      if (trailing.isNotEmpty) Text(trailing, style: context.text.caption),
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

  /// Optional illustration that replaces the tinted circle. Passing one here
  /// keeps every empty state on the same vertical rhythm.
  final Widget? art;

  const MemoEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.art,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(MemoSpace.xxl, MemoSpace.xxl, MemoSpace.xxl, MemoSpace.xxxl),
    child: Column(children: [
      art ?? Container(
        width: 76, height: 76,
        decoration:  BoxDecoration(color: context.colors.brand100, shape: BoxShape.circle),
        child: Icon(icon, size: 32, color: context.colors.brand500),
      ),
      const SizedBox(height: MemoSpace.xl),
      Text(title, textAlign: TextAlign.center, style: context.text.headline),
      const SizedBox(height: MemoSpace.sm),
      Text(subtitle, textAlign: TextAlign.center, style: context.text.label.copyWith(color: context.colors.muted)),
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
    style: context.text.body,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: context.text.body.copyWith(color: context.colors.muted),
      filled: true,
      fillColor: context.colors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 13),
      prefixIcon:  Icon(Icons.search_rounded, color: context.colors.muted, size: 21),
      suffixIcon: showClear
        ? IconButton(
            tooltip: '清空搜索',
            icon:  Icon(Icons.close_rounded, size: 19, color: context.colors.muted),
            onPressed: onClear)
        : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MemoRadius.md),
        borderSide:  BorderSide(color: context.colors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MemoRadius.md),
        borderSide:  BorderSide(color: context.colors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MemoRadius.md),
        borderSide:  BorderSide(color: context.colors.brand600, width: 1.6),
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
      Expanded(flex: 2, child: Text(label, style: context.text.body.copyWith(color: context.colors.muted))),
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
    child: Text(text, textAlign: align, style: context.text.caption.copyWith(height: 1.6)),
  );
}
