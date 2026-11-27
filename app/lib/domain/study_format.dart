import 'precis_search.dart';

/// Turns a précis passage into light markdown that reads well on a phone:
/// list items on their own lines, "Term. Meaning" with the term in bold,
/// paragraph numbers dropped, and long runs of sentences split into short
/// paragraphs.
String formatForStudy(String text) {
  final lines = <String>[];
  final para = <String>[];
  void flush() {
    if (para.isNotEmpty) lines.add(para.join(' '));
    para.clear();
  }

  // A marker left on its own ("12.", "(a)") belongs to the text after it.
  final units = <String>[];
  String? pending;
  for (final u in splitUnits(text)) {
    if (RegExp(r'^(\d{1,3}\.|\(?[a-z]{1,3}\)|\(?[ivx]{1,4}\))$').hasMatch(u)) {
      pending = u;
      continue;
    }
    final unit = pending == null ? u : '$pending $u';
    pending = null;
    // "(a) True North." + "It points to …" read as one item.
    if (units.isNotEmpty && !_isItem(unit) && _isShortLabel(units.last) &&
        (_isItem(units.last) || _boldLabel('${units.last} x') != '${units.last} x')) {
      units[units.length - 1] = '${units.last} $unit';
      continue;
    }
    units.add(unit);
  }

  for (var unit in units) {
    unit = unit.replaceAll(RegExp(r'\bLEARNING OBJECTIVES?\b'), '').trim();
    if (unit.isEmpty) continue;
    final itemBody = unit.replaceFirst(_itemStart, '');
    // Lesson outlines ("Part II: Section Battle Drill") and learning-objective
    // bullets ("Explain various types …") are not content.
    if (_isItem(unit) && RegExp(r'^Part\s+[IVX]+\b').hasMatch(itemBody)) continue;
    if (_isItem(unit) && RegExp(r'^(Explain|Describe|Understand|Identify|Learn|Know|Comprehend|Appreciate|Analyse|Analyze)\b').hasMatch(itemBody)) continue;
    // "12. The youth of today …": a paragraph number, not a list item.
    final paraNo = RegExp(r'^\d{1,3}\.\s+(?=[A-Z])').firstMatch(unit);
    if (paraNo != null && unit.length > 80) unit = unit.substring(paraNo.end);

    final item = RegExp(r'^(\(?[a-z]{1,3}\)|\(?[ivx]{1,4}\)|\d{1,2}[.)]|[•➢▪●])\s*').firstMatch(unit);
    if (item != null) {
      flush();
      var body = unit.substring(item.end);
      final marker = item.group(1)!;
      body = _boldLabel(body);
      lines.add(RegExp(r'^[•➢▪●]$').hasMatch(marker) ? '- $body' : '${marker.startsWith('(') || marker.endsWith(')') ? (marker.startsWith('(') ? marker : '($marker') : marker} $body');
      continue;
    }
    // "There are three types of north:-" introduces a list: its own bold line.
    if (RegExp(r'(:-|:)$').hasMatch(unit) && unit.length < 110 && _boldLabel(unit) == unit) {
      flush();
      lines.add('**${unit.replaceFirst(RegExp(r':-$'), ':')}**');
      continue;
    }
    final labelled = _boldLabel(unit);
    if (labelled != unit) {
      flush();
      lines.add(labelled);
      continue;
    }
    para.add(unit);
    if (para.length == 3) flush();
  }
  flush();
  return lines.join('\n');
}

final _itemStart = RegExp(r'^(\(?[a-z]{1,3}\)|\(?[ivx]{1,4}\)|\d{1,2}[.)]|[•➢▪●])\s*');
bool _isItem(String u) => _itemStart.hasMatch(u);
bool _isShortLabel(String u) {
  final body = u.replaceFirst(_itemStart, '');
  return body.length < 45 && RegExp(r'[.:]-?$').hasMatch(body) && body.split(' ').length <= 6;
}

/// "Magnetic North. It is …" -> "**Magnetic North.** It is …"
String _boldLabel(String s) {
  final m = RegExp(r"^([A-Z][A-Za-z0-9 ,&/'’()\-]{2,42}?)([.:]|:-)\s+(?=\S)").firstMatch(s);
  if (m == null) return s;
  final label = m.group(1)!;
  final words = label.split(' ');
  // A label is short and mostly capitalised; a normal sentence start is not.
  final caps = words.where((w) => w.isNotEmpty && w[0].toUpperCase() == w[0]).length;
  if (words.length > 6 || caps / words.length < 0.6) return s;
  return '**$label${m.group(2)}** ${s.substring(m.end)}';
}

/// Up to [max] key points for a chapter. The terms it defines come first
/// ("**True North**: the direction of the geographic North Pole"), because
/// those are what exams ask; its Summary fills any gap.
List<String> keyPoints(List<PrecisPassage> chapter, {int max = 6}) {
  final out = <String>[];
  final labels = <String>{};
  const generic = {'introduction', 'note', 'aim', 'scope', 'conclusion', 'summary', 'general', 'preview', 'example'};
  for (final p in chapter) {
    for (final line in formatForStudy(p.content).split('\n')) {
      final m = RegExp(r'^(?:\(?[a-z0-9ivx]{1,4}[.)]\s+|-\s+)?\*\*([^*]{3,45}?)[.:]?\*\*\s+(.+)$').firstMatch(line);
      if (m == null) continue;
      final label = m.group(1)!.trim();
      if (generic.contains(label.toLowerCase()) || label.toLowerCase().startsWith('part ') || !labels.add(label.toLowerCase())) {
        continue;
      }
      var meaning = m.group(2)!.trim().replaceFirst(RegExp(r'^(It|This) (is|refers to|means) ', caseSensitive: false), '');
      meaning = meaning.split(RegExp(r'(?<=[.!?])\s')).first;
      if (meaning.split(' ').length < 5 || RegExp(r'(:-|:)$|following parts|as under|as follows', caseSensitive: false).hasMatch(meaning)) continue;
      // Table headers ("ADVANTAGE DISADVANTAGE") are not terms.
      if (RegExp(r'\b[A-Z]{4,}\s+[A-Z]{4,}\b').hasMatch(label)) continue;
      if (meaning.length > 150) meaning = '${meaning.substring(0, meaning.lastIndexOf(' ', 145))}…';
      out.add('**$label**: ${meaning[0].toLowerCase() == meaning[0] ? meaning : meaning[0].toLowerCase() + meaning.substring(1)}');
      if (out.length == max) return out;
    }
  }
  if (out.length >= 3) return out;
  return [...out, ..._summaryPoints(chapter, max - out.length)];
}

List<String> _summaryPoints(List<PrecisPassage> chapter, int max) {
  if (max <= 0) return const [];
  String section(PrecisPassage p) => p.heading.split(' · ').last.toLowerCase();
  final summary = chapter.where((p) => section(p).contains('summary') || section(p).contains('conclusion')).toList();
  final source = summary.isNotEmpty ? summary : _firstOfEachSection(chapter);
  final out = <String>[];
  for (final p in source) {
    for (final u in splitUnits(p.content)) {
      var s = u.replaceFirst(RegExp(r'^(\(?[a-z]{1,3}\)|\(?[ivx]{1,4}\)|\d{1,3}[.)]|[•➢▪●])\s*'), '').trim();
      if (s.length < 40 || s.endsWith('?') || s.endsWith(':-') || s.endsWith(':')) continue;
      if (RegExp(r'^(In this|This chapter|The chapter|In the next|To (understand|comprehend|learn|know))', caseSensitive: false).hasMatch(s)) continue;
      if (s.length > 200) s = '${s.substring(0, s.lastIndexOf(' ', 195))}…';
      if (out.any((o) => o.substring(0, o.length.clamp(0, 50)) == s.substring(0, s.length.clamp(0, 50)))) continue;
      out.add(s);
      if (out.length == max) return out;
      if (summary.isEmpty) break;
    }
  }
  return out;
}

List<PrecisPassage> _firstOfEachSection(List<PrecisPassage> chapter) {
  final seen = <String>{};
  return [
    for (final p in chapter)
      if (seen.add(p.heading.split(' · ').last)) p,
  ];
}

/// Minutes to read, at 180 words a minute.
int readMinutes(List<PrecisPassage> chapter) {
  final words = chapter.fold(0, (a, p) => a + p.content.split(RegExp(r'\s+')).length);
  return (words / 180).ceil().clamp(1, 999);
}
