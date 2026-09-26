import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/bronnen_models.dart';

/// Opens the app's Bible reader at a resolved reference.
typedef OpenBronRef = void Function(BronRef ref);

/// One section of a work, as the reader shows it: the section label and
/// title, then every block in order.
///
/// [fontSize] is the reader's own text-size preference, so a catechism reads
/// at the size the Bible does.
class BronSectionView extends StatelessWidget {
  const BronSectionView({
    super.key,
    required this.section,
    required this.onOpenRef,
    this.fontSize = 17,
    this.expandAll = false,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 48),
  });

  final BronSection section;
  final OpenBronRef onOpenRef;
  final double fontSize;
  final bool expandAll;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    return ListView(
      padding: padding,
      children: [
        Text(section.label, style: AppTheme.displaySmall),
        if (section.title != null) ...[
          const SizedBox(height: 2),
          Text(
            section.title!,
            style: AppTheme.readerBody.copyWith(
              fontStyle: FontStyle.italic,
              fontSize: fontSize,
              height: 1.4,
              color: AppTheme.inkMuted,
            ),
          ),
        ],
        const SizedBox(height: 20),
        for (final block in section.blocks)
          switch (block) {
            BronHeading() => _Heading(block),
            BronQa() => _QaBlock(
              block: block,
              fontSize: fontSize,
              expandAll: expandAll,
              onOpenRef: onOpenRef,
            ),
            BronParagraph() => _ParagraphBlock(
              block: block,
              fontSize: fontSize,
              expandAll: expandAll,
              onOpenRef: onOpenRef,
            ),
          },
      ],
    );
  }
}

/// "\n\n" in the source is a paragraph break inside one answer.
List<String> _paragraphs(String text) => text
    .split(RegExp(r'\n\s*\n'))
    .map((p) => p.trim())
    .where((p) => p.isNotEmpty)
    .toList(growable: false);

Widget _textWithBreaks(String text, TextStyle style) {
  final parts = _paragraphs(text);
  if (parts.length <= 1) return Text(text.trim(), style: style);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < parts.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
          child: Text(parts[i], style: style),
        ),
    ],
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.block);

  final BronHeading block;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(block.text.toUpperCase(), style: AppTheme.groupLabel),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.number);

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.tealTint,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Text(
        '$number',
        style: AppTheme.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: AppTheme.tealStrong,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _QaBlock extends StatelessWidget {
  const _QaBlock({
    required this.block,
    required this.fontSize,
    required this.expandAll,
    required this.onOpenRef,
  });

  final BronQa block;
  final double fontSize;
  final bool expandAll;
  final OpenBronRef onOpenRef;

  @override
  Widget build(BuildContext context) {
    final question = AppTheme.bodyStrong.copyWith(
      fontSize: fontSize - 1,
      height: 1.45,
    );
    final answer = AppTheme.readerBody.copyWith(fontSize: fontSize, height: 1.7);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (block.number != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: _NumberBadge(block.number!),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: _textWithBreaks(block.question, question)),
            ],
          ),
          const SizedBox(height: 10),
          _textWithBreaks(block.answer, answer),
          if (block.refs.isNotEmpty) ...[
            const SizedBox(height: 12),
            BronRefList(refs: block.refs, expandAll: expandAll, onOpenRef: onOpenRef),
          ],
        ],
      ),
    );
  }
}

class _ParagraphBlock extends StatelessWidget {
  const _ParagraphBlock({
    required this.block,
    required this.fontSize,
    required this.expandAll,
    required this.onOpenRef,
  });

  final BronParagraph block;
  final double fontSize;
  final bool expandAll;
  final OpenBronRef onOpenRef;

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.readerBody.copyWith(fontSize: fontSize, height: 1.7);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (block.number != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _NumberBadge(block.number!),
                ),
                const SizedBox(width: 10),
                Expanded(child: _textWithBreaks(block.text, style)),
              ],
            )
          else
            _textWithBreaks(block.text, style),
          if (block.refs.isNotEmpty) ...[
            const SizedBox(height: 12),
            BronRefList(refs: block.refs, expandAll: expandAll, onOpenRef: onOpenRef),
          ],
        ],
      ),
    );
  }
}

/// The Scripture references under one block: small outlined chips.
///
/// A chip that carries Statenvertaling text opens it inline, beneath the row;
/// one without text goes straight to the reader; an unresolved reference is
/// plain text. "Schriftteksten voluit" ([expandAll]) opens every chip that
/// has text; a tap still closes a single one.
class BronRefList extends StatefulWidget {
  const BronRefList({
    super.key,
    required this.refs,
    required this.onOpenRef,
    this.expandAll = false,
  });

  final List<BronRef> refs;
  final OpenBronRef onOpenRef;
  final bool expandAll;

  @override
  State<BronRefList> createState() => _BronRefListState();
}

class _BronRefListState extends State<BronRefList> {
  /// Indexes whose state differs from [BronRefList.expandAll].
  final Set<int> _toggled = {};

  @override
  void didUpdateWidget(covariant BronRefList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expandAll != widget.expandAll) _toggled.clear();
  }

  bool _isOpen(int i) =>
      widget.refs[i].hasText && (widget.expandAll != _toggled.contains(i));

  void _tap(int i) {
    final r = widget.refs[i];
    if (r.hasText) {
      setState(() => _toggled.contains(i) ? _toggled.remove(i) : _toggled.add(i));
    } else if (r.isResolved) {
      widget.onOpenRef(r);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.dependOn(context);
    final open = [
      for (var i = 0; i < widget.refs.length; i++)
        if (_isOpen(i)) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < widget.refs.length; i++)
              widget.refs[i].isResolved
                  ? _RefChip(
                      label: widget.refs[i].label,
                      active: _isOpen(i),
                      onTap: () => _tap(i),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      child: Text(widget.refs[i].label, style: AppTheme.caption),
                    ),
          ],
        ),
        for (final i in open)
          _RefText(ref: widget.refs[i], onOpen: () => widget.onOpenRef(widget.refs[i])),
      ],
    );
  }
}

class _RefChip extends StatelessWidget {
  const _RefChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? AppTheme.tealTint : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        side: BorderSide(color: active ? AppTheme.teal : scheme.outline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: AppTheme.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: active ? AppTheme.tealStrong : AppTheme.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

/// The Statenvertaling verses of one reference, with superscript verse
/// numbers and a link into the reader.
class _RefText extends StatelessWidget {
  const _RefText({required this.ref, required this.onOpen});

  final BronRef ref;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final body = AppTheme.readerBody.copyWith(fontSize: 15, height: 1.65);
    final number = AppTheme.verseNumber.copyWith(fontSize: 10, color: AppTheme.teal);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 4),
      decoration: BoxDecoration(
        color: AppTheme.paperSunken,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border(left: BorderSide(color: AppTheme.teal, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ref.label, style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                for (final v in ref.text) ...[
                  WidgetSpan(
                    alignment: PlaceholderAlignment.top,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Text('${v.n}', style: number),
                    ),
                  ),
                  TextSpan(text: '${v.text.trim()} '),
                ],
              ],
            ),
            style: body,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 4),
                minimumSize: const Size(0, 36),
                foregroundColor: AppTheme.teal,
                textStyle: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
              ),
              child: Text('${ref.chapterLabel} lezen'),
            ),
          ),
        ],
      ),
    );
  }
}
