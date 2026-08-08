import 'package:flutter/material.dart';

import '../data/cu_product_catalog.dart';

const Color _newProductGreen = Color(0xFF149857);

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
    final matches = CuProductCatalog.matchesForText(title);
    final highlights = _highlightsFor(title, matches);
    final titleWidget = RichText(
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      text: TextSpan(
        style: style,
        children: _spansFor(title, highlights, style),
      ),
    );

    if (highlights.isEmpty || !showLabels) return titleWidget;

    return Column(
      crossAxisAlignment: textAlign == TextAlign.right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        titleWidget,
        Padding(
          padding: EdgeInsets.only(top: labelTopPadding),
          child: _TinyProductLabels(
            matches: highlights.map((item) => item.match),
            compact: true,
          ),
        ),
      ],
    );
  }
}

class CuProductBadgeStrip extends StatelessWidget {
  const CuProductBadgeStrip({
    super.key,
    required this.text,
    this.compact = false,
    this.onDark = false,
    this.topPadding = 0,
  });

  final String text;
  final bool compact;
  final bool onDark;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final matches = CuProductCatalog.matchesForText(text);
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
            (label) => Text(
              label.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onDark ? Colors.white.withAlpha(230) : label.color,
                fontSize: compact ? 9 : 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.25,
              ),
            ),
          )
          .toList(),
    );
  }
}

List<InlineSpan> _spansFor(
  String title,
  List<_ProductHighlight> highlights,
  TextStyle style,
) {
  if (highlights.isEmpty) return <InlineSpan>[TextSpan(text: title)];

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final highlight in highlights) {
    if (highlight.start > cursor) {
      spans.add(TextSpan(text: title.substring(cursor, highlight.start)));
    }
    final highlightedText = title.substring(highlight.start, highlight.end);
    final isPb = highlight.match.labels.contains(CuProductLabel.pbProduct);
    final isNew = highlight.match.labels.contains(CuProductLabel.newProduct);
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _ProductMarkedText(
          text: highlightedText,
          style: style,
          isPb: isPb,
          isNew: isNew,
        ),
      ),
    );
    cursor = highlight.end;
  }
  if (cursor < title.length) {
    spans.add(TextSpan(text: title.substring(cursor)));
  }
  return spans;
}

List<_ProductHighlight> _highlightsFor(
  String title,
  List<CuProductMatch> matches,
) {
  final normalized = _NormalizedText.from(title);
  final highlights = <_ProductHighlight>[];

  for (final match in matches) {
    if (!_hasDisplayLabel(match)) continue;
    final candidates =
        <String>{
            ...match.aliases,
            _cleanProductName(match.productName),
            match.productName,
          }.where((item) => item.trim().isNotEmpty).toList()
          ..sort((a, b) => b.length.compareTo(a.length));

    for (final candidate in candidates) {
      final target = _normalize(candidate);
      if (target.isEmpty) continue;
      final index = normalized.value.indexOf(target);
      if (index < 0) continue;
      final start = normalized.sourceIndexes[index];
      final end = normalized.sourceIndexes[index + target.length - 1] + 1;
      if (_overlaps(highlights, start, end)) continue;
      highlights.add(_ProductHighlight(match: match, start: start, end: end));
      break;
    }
  }

  highlights.sort((a, b) => a.start.compareTo(b.start));
  return highlights;
}

bool _overlaps(List<_ProductHighlight> highlights, int start, int end) {
  return highlights.any((item) => start < item.end && end > item.start);
}

bool _hasDisplayLabel(CuProductMatch match) {
  return match.labels.contains(CuProductLabel.pbProduct) ||
      match.labels.contains(CuProductLabel.newProduct);
}

List<_ProductLabel> _labelItems(Iterable<CuProductMatch> matches) {
  final labels = <String, _ProductLabel>{};
  for (final match in matches) {
    if (match.labels.contains(CuProductLabel.pbProduct)) {
      labels['${match.store}|PB'] = _ProductLabel(
        text: '${match.store} PB',
        color: match.color,
      );
    }
    if (match.labels.contains(CuProductLabel.newProduct)) {
      labels['${match.store}|new'] = _ProductLabel(
        text: '${match.store} 신상',
        color: _newProductGreen,
      );
    }
  }
  return labels.values.toList();
}

String _cleanProductName(String value) {
  return value
      .replaceAll(RegExp(r'\d+(g|ml|p|입|개)$', caseSensitive: false), '')
      .trim();
}

String _normalize(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^0-9a-z가-힣]'), '').trim();
}

class _NormalizedText {
  const _NormalizedText({required this.value, required this.sourceIndexes});

  factory _NormalizedText.from(String source) {
    final buffer = StringBuffer();
    final indexes = <int>[];
    for (var i = 0; i < source.length; i += 1) {
      final char = source[i].toLowerCase();
      if (RegExp(r'[0-9a-z가-힣]').hasMatch(char)) {
        buffer.write(char);
        indexes.add(i);
      }
    }
    return _NormalizedText(value: buffer.toString(), sourceIndexes: indexes);
  }

  final String value;
  final List<int> sourceIndexes;
}

class _ProductHighlight {
  const _ProductHighlight({
    required this.match,
    required this.start,
    required this.end,
  });

  final CuProductMatch match;
  final int start;
  final int end;
}

class _ProductLabel {
  const _ProductLabel({required this.text, required this.color});

  final String text;
  final Color color;
}

class _ProductMarkedText extends StatelessWidget {
  const _ProductMarkedText({
    required this.text,
    required this.style,
    required this.isPb,
    required this.isNew,
  });

  final String text;
  final TextStyle style;
  final bool isPb;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ProductMarkPainter(isPb: isPb, isNew: isNew),
      child: Padding(
        padding: EdgeInsets.only(bottom: isNew ? 4 : 0),
        child: Text(text, style: style),
      ),
    );
  }
}

class _ProductMarkPainter extends CustomPainter {
  const _ProductMarkPainter({required this.isPb, required this.isNew});

  final bool isPb;
  final bool isNew;

  @override
  void paint(Canvas canvas, Size size) {
    if (isPb) {
      final marker = Paint()
        ..color = const Color(0xFF9B59B6).withAlpha(78)
        ..strokeWidth = size.height * 0.56
        ..strokeCap = StrokeCap.round;
      final y = size.height * 0.57;
      canvas.drawLine(Offset(1, y), Offset(size.width - 1, y + 0.5), marker);
    }

    if (isNew) {
      final wave = Paint()
        ..color = const Color(0xFF9EDB35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(0, size.height - 1.5);
      var x = 0.0;
      var rising = true;
      while (x < size.width) {
        final next = (x + 6).clamp(0, size.width).toDouble();
        path.quadraticBezierTo(
          x + 3,
          size.height - (rising ? 4 : 0.5),
          next,
          size.height - 1.5,
        );
        rising = !rising;
        x = next;
      }
      canvas.drawPath(path, wave);
    }
  }

  @override
  bool shouldRepaint(covariant _ProductMarkPainter oldDelegate) {
    return oldDelegate.isPb != isPb || oldDelegate.isNew != isNew;
  }
}
