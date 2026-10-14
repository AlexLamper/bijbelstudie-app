import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../settings/data/reading_settings.dart';
import 'commentary_format.dart';

/// Paints one commentary entry.
///
/// Mirrors the styling `formatCommentaryText()` bakes into its HTML in
/// `components/study/CommentaryComponent.tsx`, together with the `prefClasses`
/// and `prefStyles` the website wraps that HTML in: the reader's font family,
/// size and line height reach every block here, exactly as they do on the
/// site. The website's own paragraph rules pin `line-height:1.8`, which is the
/// factor its default "Ruim" setting resolves to anyway; the app follows the
/// setting instead, so the preference does something for a change.
///
/// Parsing happens once per entry rather than once per build. The entries are
/// long - Matthew Henry on Genesis 1 verse 1 is eleven kilobytes - and this
/// sits in a ListView that rebuilds its children as they scroll.
class CommentaryBody extends StatefulWidget {
  const CommentaryBody({
    super.key,
    required this.text,
    required this.settings,
    this.selectable = true,
    this.onQuote,
  });

  final String text;
  final ReadingSettings settings;

  /// Whether the reader may drag a cursor through this text.
  ///
  /// False for a licensed commentary - see
  /// `features/commentary/domain/commentary_copy_policy.dart`. With no
  /// [SelectionArea] around them the blocks are plain `Text.rich`, which has no
  /// selection, no handles and so no copy item in any toolbar: the same stance
  /// the reader's own verses take for a restricted translation.
  final bool selectable;

  /// Called with the text the reader picked out, to hang a note off it.
  ///
  /// Both paths end here, which is the point: when [selectable] is true the
  /// selection toolbar grows an "Aantekening maken" item and hands over the
  /// selection; when it is false a long press on one block hands over that
  /// block. A licensed commentary therefore takes notes without becoming
  /// copyable. Null leaves the text inert.
  final ValueChanged<String>? onQuote;

  @override
  State<CommentaryBody> createState() => _CommentaryBodyState();
}

class _CommentaryBodyState extends State<CommentaryBody> {
  late List<CommentaryBlock> _blocks = parseCommentary(widget.text);

  /// What is selected right now, cached from [SelectionArea.onSelectionChanged]
  /// so the toolbar item can quote it. Not state the build depends on.
  String? _selection;

  @override
  void didUpdateWidget(covariant CommentaryBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _blocks = parseCommentary(widget.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_blocks.isEmpty) return const SizedBox.shrink();

    final base = TextStyle(
      fontFamily: widget.settings.fontFamily.fontName,
      fontSize: widget.settings.fontSize.points * 0.92,
      height: widget.settings.lineHeight.factor,
      color: AppTheme.inkSoft,
    );
    final em = base.fontSize!;

    final children = <Widget>[];
    for (var i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];

      // The footnotes sit under a rule, as they do in `formatDachselText`.
      final opensFootnotes =
          block.kind == CommentaryBlockKind.footnote &&
          (i == 0 || _blocks[i - 1].kind != CommentaryBlockKind.footnote);
      if (opensFootnotes) {
        children.add(
          Padding(
            padding: EdgeInsets.only(top: em * 1.5, bottom: em),
            child: const RuleLine(),
          ),
        );
      }

      final rendered = _block(block, base, suppressTop: children.isEmpty);
      // Only where a selection cannot do the job: inside a SelectionArea a
      // long press starts a selection, and a gesture stealing that would take
      // the reader's copy away rather than add anything.
      children.add(
        widget.selectable || widget.onQuote == null
            ? rendered
            : Semantics(
                onLongPressHint: 'Aantekening maken',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _quote(block),
                  child: rendered,
                ),
              ),
      );
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );

    // A licensed commentary stops here: no SelectionArea, so no handles and no
    // toolbar to carry a copy item. The long press on each block above is the
    // way in for a note.
    if (!widget.selectable) return column;

    // Selectable, as the flat `SelectableText` this replaced was. One area per
    // entry, so a drag cannot run off into the next verse's commentary.
    return SelectionArea(
      onSelectionChanged: (content) => _selection = content?.plainText,
      contextMenuBuilder: widget.onQuote == null
          ? null
          : _contextMenu,
      child: column,
    );
  }

  /// The platform's own selection toolbar with one item added, so copy, share
  /// and lookup keep working exactly as they did on a public-domain commentary.
  Widget _contextMenu(BuildContext context, SelectableRegionState state) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        ...state.contextMenuButtonItems,
        ContextMenuButtonItem(
          label: 'Aantekening maken',
          onPressed: () {
            final selection = _selection;
            state.hideToolbar();
            if (selection != null && selection.trim().isNotEmpty) {
              widget.onQuote?.call(selection);
            }
          },
        ),
      ],
    );
  }

  /// Long press on one block of a non-selectable commentary: quote that block.
  void _quote(CommentaryBlock block) {
    final text = block.spans.map((span) => span.text).join().trim();
    if (text.isEmpty) return;
    HapticFeedback.selectionClick();
    widget.onQuote?.call(text);
  }

  Widget _block(
    CommentaryBlock block,
    TextStyle base, {
    required bool suppressTop,
  }) {
    final em = base.fontSize!;
    double top(double factor) => suppressTop ? 0 : em * factor;

    switch (block.kind) {
      // `border-left:3px solid #0D9488;padding-left:0.75em` and bold, the
      // treatment `formatPlainText` gives a Roman-numeral heading.
      case CommentaryBlockKind.section:
        return Padding(
          padding: EdgeInsets.only(top: top(1.6), bottom: em * 0.15),
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: AppTheme.teal, width: 3)),
            ),
            padding: EdgeInsets.only(left: em * 0.75),
            child: _rich(
              block,
              base.copyWith(
                fontSize: em * 0.95,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ),
        );

      case CommentaryBlockKind.heading:
        return Padding(
          padding: EdgeInsets.only(top: top(1.6), bottom: em * 0.4),
          child: _rich(
            block,
            base.copyWith(
              fontSize: em * 1.05,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        );

      case CommentaryBlockKind.subheading:
        return Padding(
          padding: EdgeInsets.only(top: top(1.25), bottom: em * 0.3),
          child: _rich(
            block,
            base.copyWith(
              fontSize: em * 0.95,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        );

      case CommentaryBlockKind.listItem:
        return Padding(
          padding: EdgeInsets.only(top: top(0.85)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: em * 2,
                child: Padding(
                  padding: EdgeInsets.only(right: em * 0.5),
                  child: Text(
                    block.marker ?? '',
                    textAlign: TextAlign.right,
                    style: base.copyWith(color: AppTheme.muted),
                  ),
                ),
              ),
              Expanded(child: _rich(block, base)),
            ],
          ),
        );

      case CommentaryBlockKind.quote:
        // A rule and an indent, no wash and no italic: the quote is set in the
        // serif the bible text uses, which is what marks it as quoted matter
        // in a column of Inter. A tinted box made it read as a callout.
        return Padding(
          padding: EdgeInsets.only(top: top(0.75), bottom: em * 0.75),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: AppTheme.teal, width: 2),
              ),
            ),
            padding: const EdgeInsets.only(left: 14),
            child: _rich(
              block,
              base.copyWith(
                fontFamily: AppTheme.serifFontName,
                fontSize: em * 0.97,
                height: 1.7,
                color: AppTheme.ink,
              ),
            ),
          ),
        );

      case CommentaryBlockKind.footnote:
        final muted = base.copyWith(
          fontSize: em * 0.88,
          color: base.color?.withValues(alpha: 0.85),
        );
        return Padding(
          padding: EdgeInsets.only(top: top(0.6)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: em * 1.5,
                child: block.marker == null
                    ? null
                    : Text(
                        block.marker!,
                        style: muted.copyWith(
                          fontSize: em * 0.7,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.teal,
                        ),
                      ),
              ),
              Expanded(child: _rich(block, muted)),
            ],
          ),
        );

      case CommentaryBlockKind.paragraph:
        // The `padding-left` ladder `formatPlainText` gives the outline: `1.`
        // and `A.` one step in, `a.` two, `(1)` three.
        const steps = [0.0, 1.5, 2.75, 3.75];
        final indent = block.indent.clamp(0, steps.length - 1);
        return Padding(
          padding: EdgeInsets.only(
            top: top(switch (indent) {
              0 => 0.85,
              1 => 0.8,
              _ => 0.5,
            }),
            left: em * steps[indent],
          ),
          child: _rich(block, base),
        );
    }
  }

  /// The block's style goes on the root span, so the reader's typography is
  /// one thing the whole block inherits and each run only says how it differs.
  Widget _rich(CommentaryBlock block, TextStyle style) {
    return Text.rich(
      TextSpan(
        style: style,
        children: [for (final span in block.spans) _span(span, style)],
      ),
    );
  }

  InlineSpan _span(CommentarySpan span, TextStyle style) {
    final emphasis = span.bold || span.italic || span.accent
        ? TextStyle(
            fontWeight: span.bold ? FontWeight.w700 : null,
            fontStyle: span.italic ? FontStyle.italic : null,
            color: span.accent ? AppTheme.teal : null,
          )
        : null;
    if (!span.superscript) return TextSpan(text: span.text, style: emphasis);

    // Flutter has no baseline shift on a TextSpan, so a raised marker has to
    // be a placeholder aligned to the top of the line box.
    return WidgetSpan(
      alignment: PlaceholderAlignment.top,
      child: Text(
        span.text,
        style: style.merge(emphasis).copyWith(
          fontSize: (style.fontSize ?? 16) * 0.7,
          height: 1.2,
        ),
      ),
    );
  }
}
