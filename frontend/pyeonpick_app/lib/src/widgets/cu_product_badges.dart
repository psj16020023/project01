import 'package:flutter/material.dart';

import '../data/cu_product_catalog.dart';

class ConvenienceProductTitle extends StatelessWidget {
  const ConvenienceProductTitle({
    super.key,
    required this.title,
    this.contextText,
    required this.style,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign = TextAlign.start,
    this.labelTopPadding = 4,
    this.showLabels = true,
  });

  final String title;
  final String? contextText;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final double labelTopPadding;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final matches = <CuProductMatch>[
      ...CuProductCatalog.matchesForText(title),
      ...CuProductCatalog.contextMatchesForTitle(title, contextText),
    ];
    final hasLabels = matches.any(
      (match) =>
          match.labels.contains(CuProductLabel.pbProduct) ||
          match.labels.contains(CuProductLabel.newProduct),
    );
    final titleWidget = Text(
      title,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style,
    );

    if (!hasLabels || !showLabels) return titleWidget;

    return Column(
      crossAxisAlignment: textAlign == TextAlign.right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        titleWidget,
        Padding(
          padding: EdgeInsets.only(top: labelTopPadding),
          child: _TinyProductLabels(matches: matches, compact: true),
        ),
      ],
    );
  }
}

class CuProductBadgeStrip extends StatelessWidget {
  const CuProductBadgeStrip({
    super.key,
    required this.text,
    this.contextText,
    this.compact = false,
    this.onDark = false,
    this.topPadding = 0,
  });

  final String text;
  final String? contextText;
  final bool compact;
  final bool onDark;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final matches = <CuProductMatch>[
      ...CuProductCatalog.matchesForText(text),
      ...CuProductCatalog.contextMatchesForTitle(text, contextText),
    ];
    if (matches.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: _TinyProductLabels(
        matches: matches,
        compact: compact,
        onDark: onDark,
      ),
    );
  }
}

class _TinyProductLabels extends StatelessWidget {
  const _TinyProductLabels({
    required this.matches,
    this.compact = false,
    this.onDark = false,
  });

  final Iterable<CuProductMatch> matches;
  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final labels = _labelItems(matches).take(compact ? 3 : 5).toList();
    if (labels.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: compact ? 5 : 7,
      runSpacing: compact ? 2 : 3,
      children: labels
          .map(
            (label) => Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 8,
                vertical: compact ? 3 : 4,
              ),
              decoration: BoxDecoration(
                color: onDark ? label.color : label.color.withAlpha(20),
                borderRadius: BorderRadius.circular(999),
                border: onDark
                    ? null
                    : Border.all(color: label.color.withAlpha(90)),
              ),
              child: Text(
                label.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onDark ? Colors.white : label.color,
                  fontSize: compact ? 9 : 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.25,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

List<_ProductLabel> _labelItems(Iterable<CuProductMatch> matches) {
  final labels = <String, _ProductLabel>{};
  for (final match in matches) {
    if (match.labels.contains(CuProductLabel.pbProduct)) {
      labels['${match.store}|PB'] = _ProductLabel(
        text: '${match.store} · PB 상품',
        color: match.color,
      );
    }
    if (match.labels.contains(CuProductLabel.newProduct)) {
      labels['${match.store}|new'] = _ProductLabel(
        text: '${match.store} · 신상',
        color: match.color,
      );
    }
  }
  return labels.values.toList();
}

class _ProductLabel {
  const _ProductLabel({required this.text, required this.color});

  final String text;
  final Color color;
}
