import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';

/// Shows an answer written in a little markdown: "- " / "* " / "• " bullets,
/// "1." and "(a)" items, **bold**, *italic* and citation numbers like [2].
/// Headings and nested bullets are flattened, so nothing shows as raw markup.
class RichAnswer extends StatelessWidget {
  const RichAnswer(this.text, {super.key, this.style, this.selectable = true});

  final String text;
  final TextStyle? style;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium!;
    final c = Theme.of(context).colorScheme;
    final blocks = parseAnswer(text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, b) in blocks.indexed)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : (b.marker == null ? Space.sm : Space.xs)),
          child: b.marker == null
              ? _text(context, b.text, base.copyWith(fontWeight: b.heading ? FontWeight.w600 : null), c)
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: b.marker == '•' ? 18 : 28,
                    child: Text(b.marker!, style: base.copyWith(color: c.primary, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: _text(context, b.text, base, c)),
                ]),
        ),
    ]);
  }

  Widget _text(BuildContext context, String s, TextStyle style, ColorScheme c) {
    final span = TextSpan(style: style, children: inlineSpans(s, style, c.primary));
    return selectable ? SelectableText.rich(span) : Text.rich(span);
  }
}

/// One line of an answer: plain text, or a list item with its marker.
class AnswerBlock {
  const AnswerBlock(this.text, {this.marker, this.heading = false});
  final String text;
  final String? marker; // '•', '1.', '(a)'
  final bool heading;
}

final _bullet = RegExp(r'^\s*[-*•➢▪●]\s+');
final _numbered = RegExp(r'^\s*(\d{1,2})[.)]\s+');
final _lettered = RegExp(r'^\s*\(([a-z]{1,3}|[ivx]{1,4})\)\s*');
final _heading = RegExp(r'^\s*#{1,6}\s+');

List<AnswerBlock> parseAnswer(String text) {
  final out = <AnswerBlock>[];
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    if (_heading.hasMatch(line)) {
      out.add(AnswerBlock(line.replaceFirst(_heading, '').trim(), heading: true));
    } else if (_bullet.hasMatch(line)) {
      out.add(AnswerBlock(line.replaceFirst(_bullet, '').trim(), marker: '•'));
    } else if (_numbered.hasMatch(line)) {
      final m = _numbered.firstMatch(line)!;
      out.add(AnswerBlock(line.substring(m.end).trim(), marker: '${m.group(1)}.'));
    } else if (_lettered.hasMatch(line)) {
      final m = _lettered.firstMatch(line)!;
      final rest = line.substring(m.end).trim();
      if (rest.isEmpty) continue;
      out.add(AnswerBlock(rest, marker: '(${m.group(1)})'));
    } else {
      // "Title:" on its own line reads as a small heading.
      final t = line.trim();
      out.add(AnswerBlock(t.replaceAll(RegExp(r'^\*\*(.+)\*\*:?$'), r'$1'), heading: RegExp(r'^\*\*.+\*\*:?$').hasMatch(t)));
    }
  }
  return out;
}

final _inline = RegExp(r'\*\*(.+?)\*\*|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])|((?:\[\d{1,2}\])+)');

/// **bold**, *italic* and [n] citations (shown small and raised).
List<InlineSpan> inlineSpans(String s, TextStyle style, Color accent) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in _inline.allMatches(s)) {
    if (m.start > at) spans.add(TextSpan(text: s.substring(at, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(text: m.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
    } else {
      final nums = RegExp(r'\d+').allMatches(m.group(3)!).map((x) => x.group(0)).join(',');
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.top,
        child: Padding(
          padding: const EdgeInsets.only(left: 1),
          child: Text(nums, style: style.copyWith(fontSize: (style.fontSize ?? 14) * 0.7, color: accent, fontWeight: FontWeight.w600)),
        ),
      ));
    }
    at = m.end;
  }
  if (at < s.length) spans.add(TextSpan(text: s.substring(at)));
  return spans;
}
