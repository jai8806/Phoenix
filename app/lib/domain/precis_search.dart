import 'dart:math' as math;

/// One passage from a précis, as stored in the knowledge base.
class PrecisPassage {
  const PrecisPassage({
    required this.id,
    required this.title,
    required this.heading,
    required this.content,
    this.page,
    this.pageEnd,
  });

  final int id;
  final String title;
  final String heading;
  final String content;
  final int? page;
  final int? pageEnd;

  String get pages => page == null ? '' : (pageEnd != null && pageEnd != page ? '$page–$pageEnd' : '$page');

  /// "Special Subject (Army) JD/JW (2025) · MR I · … · p. 166"
  String get citation => [title, heading, if (page != null) 'p. $pages'].join(' · ');

  Map<String, dynamic> toJson() =>
      {'id': id, 't': title, 'h': heading, 'c': content, 'p': page, 'pe': pageEnd};

  factory PrecisPassage.fromJson(Map<String, dynamic> j) => PrecisPassage(
        id: (j['id'] as num).toInt(),
        title: j['t'] as String,
        heading: j['h'] as String? ?? '',
        content: j['c'] as String,
        page: (j['p'] as num?)?.toInt(),
        pageEnd: (j['pe'] as num?)?.toInt(),
      );
}

/// A sentence picked from a passage to answer the question.
class Snippet {
  const Snippet(this.text, this.passage);
  final String text;
  final PrecisPassage passage;
}

class PrecisAnswer {
  const PrecisAnswer({required this.snippets, required this.passages});

  /// The most relevant sentences, best first.
  final List<Snippet> snippets;

  /// Passages they came from, best first (for "read more").
  final List<PrecisPassage> passages;

  bool get found => snippets.isNotEmpty;
}

/// Offline search over the précis: BM25 ranking of passages, then the best
/// sentences inside them. No AI and no network: it only ever returns the
/// book's own words, with the chapter and page.
class PrecisSearch {
  PrecisSearch(this.passages) {
    for (final p in passages) {
      final tokens = [...tokenize(p.heading), ...tokenize(p.heading), ...tokenize(p.content)];
      _docs.add(tokens);
      final tf = <String, int>{};
      for (final t in tokens) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      _tf.add(tf);
      for (final t in tf.keys) {
        _df[t] = (_df[t] ?? 0) + 1;
      }
      _totalLength += tokens.length;
    }
    _avgLength = passages.isEmpty ? 0 : _totalLength / passages.length;
  }

  final List<PrecisPassage> passages;
  final _docs = <List<String>>[];
  final _tf = <Map<String, int>>[];
  final _df = <String, int>{};
  int _totalLength = 0;
  double _avgLength = 0;

  static const _k1 = 1.4;
  static const _b = 0.75;

  /// Share of the question's weight a passage must cover to count as an answer.
  static const minCoverage = 0.6;

  double _idf(String t) {
    final n = passages.length;
    final f = _df[t] ?? 0;
    return math.log(1 + (n - f + 0.5) / (f + 0.5));
  }

  /// Weight given to question words the précis never uses (as rare as possible).
  double get _unknownIdf => _idf('');

  /// Query terms after synonyms and spelling correction, plus how many
  /// meaningful words matched nothing in the précis.
  /// Terms that came only from synonyms: they help a passage match but are
  /// not required for it to count as an answer.
  Set<String> expansionTerms(String question) {
    final q = ' ${question.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')} ';
    final own = rawWords(q).map(stem).toSet();
    return {
      for (final e in synonyms.entries)
        if (q.contains(' ${e.key} ')) ...tokenize(e.value).where((t) => !own.contains(t)),
    };
  }

  (List<String>, int) queryTerms(String question) {
    var q = ' ${question.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')} ';
    final extra = <String>[];
    for (final e in synonyms.entries) {
      if (q.contains(' ${e.key} ')) extra.add(e.value);
    }
    q = '$q ${extra.join(' ')}';
    final terms = <String>{};
    var unknown = 0;
    final expanded = tokenize(extra.join(' ')).toSet();
    for (final raw in rawWords(q)) {
      final t = stem(raw);
      if (_df.containsKey(t)) {
        terms.add(t);
      } else {
        // Try the stem and the word as typed: stemming "compas" gives "compa",
        // which is too far from "compass" to count as one typo.
        final fixed = _closestTerm(t) ?? _closestTerm(raw);
        if (fixed != null) {
          terms.add(fixed);
        } else if (!expanded.contains(t) && !synonyms.containsKey(t)) {
          unknown++;
        }
      }
    }
    return (terms.toList(), unknown);
  }

  /// Fixes one typo ("compas" -> "compass") against words that occur in the précis.
  String? _closestTerm(String t) {
    if (t.length < 5) return null;
    String? best;
    var bestDf = 0;
    for (final candidate in _df.keys) {
      if ((candidate.length - t.length).abs() > 1) continue;
      if (_withinOneEdit(t, candidate) && _df[candidate]! > bestDf) {
        best = candidate;
        bestDf = _df[candidate]!;
      }
    }
    return best;
  }

  /// Answers from the précis: the best passage's most relevant sentence with
  /// the context a reader needs (the sentence before a "This…", the items of
  /// a list it introduces), then up to two other places that say the same.
  ///
  /// [preferSenior] nudges SD/SW books ahead of JD/JW ones when both match.
  PrecisAnswer answer(String question, {int maxPassages = 8, int maxSnippets = 3, bool preferSenior = true}) {
    final (terms, unknown) = queryTerms(question);
    if (terms.isEmpty || passages.isEmpty) return const PrecisAnswer(snippets: [], passages: []);
    final expansions = expansionTerms(question);
    final required = [for (final t in terms) if (!expansions.contains(t)) t];
    final totalWeight = (required.isEmpty ? terms : required).fold(0.0, (a, t) => a + _idf(t)) + unknown * _unknownIdf;
    final intent = QuestionIntent.of(question);

    final scored = <(double, int)>[];
    for (var i = 0; i < passages.length; i++) {
      final tf = _tf[i];
      final len = _docs[i].length;
      var s = 0.0;
      var covered = 0.0;
      for (final t in terms) {
        final f = tf[t];
        if (f == null) continue;
        if (required.isEmpty || !expansions.contains(t)) covered += _idf(t);
        s += _idf(t) * f * (_k1 + 1) / (f + _k1 * (1 - _b + _b * len / _avgLength)) * (expansions.contains(t) ? 0.6 : 1);
      }
      if (s <= 0 || covered / totalWeight < minCoverage) continue;
      final p = passages[i];
      // Chapter titles that name the topic are the best evidence.
      final headingWords = tokenize(p.heading).toSet();
      final inHeading = terms.where(headingWords.contains).fold(0.0, (a, t) => a + _idf(t)) / totalWeight;
      s *= 1 + 0.6 * inHeading;
      if (preferSenior && p.title.contains('JD/JW')) s *= 0.9;
      if (p.title.contains('Oct 2025')) s *= 1.05;
      if (_isHinglish(p.content)) s *= 0.35;
      if (p.title.startsWith('MCQ Bank') || p.title.startsWith('B Cert Paper') || p.title.startsWith('General NCC')) s *= 0.5;
      scored.add((s, i));
    }
    if (scored.isEmpty) return const PrecisAnswer(snippets: [], passages: []);
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final top = scored.take(maxPassages).toList();
    final best = top.first.$1;

    final asksHighest = RegExp(r'\bhighest\b').hasMatch(question.toLowerCase());
    // Score every sentence of the top passages.
    final candidates = <_Candidate>[];
    for (final (score, i) in top) {
      final units = splitUnits(passages[i].content);
      for (var u = 0; u < units.length; u++) {
        final sentence = units[u];
        if (sentence.length < 25) continue;
        final words = tokenize(sentence).toSet();
        var hit = 0.0;
        for (final t in terms) {
          if (words.contains(t)) hit += _idf(t);
        }
        if (hit == 0) continue;
        var s = (hit / totalWeight).clamp(0.0, 1.2) + 0.35 * score / best + intent.bonus(sentence, terms);
        // "(c) Magnetic North." followed by "It is the direction …": a definition.
        if (u > 0 && units[u - 1].length < 45 && _leansOnPrevious.hasMatch(sentence)) {
          final label = tokenize(units[u - 1]).toSet();
          if (required.isNotEmpty && required.every(label.contains)) s += intent.kind == 'define' ? 0.5 : 0.25;
        }
        if (asksHighest && RegExp(r'\b(second|third|fourth)[- ]highest\b', caseSensitive: false).hasMatch(sentence)) s *= 0.5;
        s *= _quality(sentence);
        candidates.add(_Candidate(s, i, units, u, terms.toSet()));
      }
    }
    if (candidates.isEmpty) return const PrecisAnswer(snippets: [], passages: []);
    candidates.sort((a, b) => b.score.compareTo(a.score));

    final snippets = <Snippet>[];
    final seen = <String>{};
    final usedPassages = <int>[];
    final lead = candidates.first;
    for (final c in candidates) {
      if (snippets.length == maxSnippets) break;
      if (snippets.isNotEmpty && c.score < lead.score * 0.72) break;
      if (usedPassages.contains(c.passage)) continue;
      final text = c.window(listIntent: intent.wantsList);
      final key = _norm(text);
      // The JD/JW and SD/SW books share many paragraphs word for word.
      if (seen.any((k) => k.contains(key.substring(0, key.length.clamp(0, 80))) || key.contains(k.substring(0, k.length.clamp(0, 80))))) {
        continue;
      }
      seen.add(key);
      usedPassages.add(c.passage);
      snippets.add(Snippet(text, passages[c.passage]));
    }
    final order = [...usedPassages, for (final (_, i) in top) if (!usedPassages.contains(i)) i];
    return PrecisAnswer(snippets: snippets, passages: [for (final i in order.take(3)) passages[i]]);
  }
}

class _Candidate {
  _Candidate(this.score, this.passage, this.units, this.index, this.terms);
  final double score;
  final Set<String> terms;
  final int passage;
  final List<String> units;
  final int index;

  /// The sentence with the context it needs to stand on its own.
  String window({required bool listIntent}) {
    final out = <String>[];
    final s = units[index];
    final prev = index > 0 ? units[index - 1] : '';
    // "This…" needs the sentence before it; "• Ashoka Chakra." labels the line after it.
    final startsItem = _listItem.hasMatch(s);
    if (prev.isNotEmpty && (_leansOnPrevious.hasMatch(s) || (!startsItem && prev.length < 45 && _label.hasMatch(prev)))) {
      out.add(prev);
    }
    out.add(s);
    final introducesList = _listIntro.hasMatch(s) || (listIntent && RegExp(r':-?\s*$').hasMatch(s));
    if (introducesList) {
      final items = <String>[];
      for (var j = index + 1; j < units.length && items.length < 40; j++) {
        final next = units[j];
        if (!_listItem.hasMatch(next) && !(j == index + 1 && next.length < 120)) break;
        if (RegExp(r'^\(?[a-z]\)\s*Part [IVX]+\b').hasMatch(next)) continue; // lesson outline, not the list
        items.add(next);
      }
      // Long lists with sub-points: keep the main (a), (b), (c) items.
      final main = items.where((i) => !_subItem.hasMatch(i)).toList();
      var chars = 0;
      for (final item in (items.length > 9 && main.length >= 3 ? main : items)) {
        if (out.length >= 12 || chars > 800) break;
        out.add(item);
        chars += item.length;
      }
    } else if (index + 1 < units.length && !_listItem.hasMatch(s)) {
      // "The Param Vir Chakra is …" + "It is awarded for …"; a short lead
      // followed by a sentence on the same topic ("By 1963, the song …").
      final next = units[index + 1];
      final sameTopic = s.length < 140 && !_listItem.hasMatch(next) && tokenize(next).any(terms.contains);
      if (_leansOnPrevious.hasMatch(next) || sameTopic) out.add(next);
    }
    return out.join('\n');
  }
}

final _leansOnPrevious = RegExp(r'^(It|This|These|They|Such|However|Hence|Therefore|Thus|He|She|Its|Their|Both|Here)\b');
final _listIntro = RegExp(
    r'(:-|:\s*$|\bas (under|follows)\b|\bthe following\b|\b(two|three|four|five|six|seven|eight|nine|ten) (main |basic |important )?(types|kinds|methods|parts|categories|principles|steps|stages|ways|elements|components|traits|qualities|aims|objectives)\b)',
    caseSensitive: false);
final _label = RegExp(r'^(\(?[a-z]{1,3}\)|\(?[ivx]{1,4}\)|\d{1,2}[.)]|[•➢▪●\-–])?\s*[A-Z][^.!?]{1,40}[.:]-?$');
final _subItem = RegExp(r'^\(?(i|ii|iii|iv|v|vi|vii|viii|ix|x)\)\s');
final _listItem = RegExp(r'^(\(?[a-z]{1,3}\)|\(?[ivx]{1,4}\)|\d{1,2}[.)]|[•➢▪●\-–])\s*');

/// What kind of answer a question wants.
class QuestionIntent {
  const QuestionIntent._(this.kind, this.wantsList);

  final String kind; // who | when | howMany | define | list | other
  final bool wantsList;

  static QuestionIntent of(String question) {
    final q = question.toLowerCase().trim();
    final list = RegExp(r'\b(types?|kinds?|methods?|parts?|steps?|principles?|traits?|qualities|stages|categories|aims|objectives|features|characteristics|sequence|list|what are|name the)\b')
        .hasMatch(q);
    if (RegExp(r'^(who|whom)\b|\bwho (is|was|heads|commands)\b|\bheaded by\b|\bhead of\b').hasMatch(q)) {
      return QuestionIntent._('who', list);
    }
    if (RegExp(r'^(when|which year|what year|in which year)\b|\b(date|year) (of|when)\b|\bwhen (is|was|did)\b').hasMatch(q)) {
      return QuestionIntent._('when', list);
    }
    if (RegExp(r'\bhow (many|much|far|long)\b|\bnumber of\b|\brange of\b|\bweight of\b|\blength of\b').hasMatch(q)) {
      return QuestionIntent._('howMany', list);
    }
    if (RegExp(r'^(what is|what are|what\x27s|define|meaning of|what do you mean)\b').hasMatch(q) && !list) {
      return QuestionIntent._('define', false);
    }
    return QuestionIntent._(list ? 'list' : 'other', list);
  }

  /// Extra score for sentences shaped like the answer.
  double bonus(String sentence, List<String> terms) {
    final s = sentence.toLowerCase();
    switch (kind) {
      case 'who':
        if (RegExp(r'\b(headed by|commanded by|is the|was the|heads|appointed)\b').hasMatch(s)) return 0.3;
        if (RegExp(r'\b(gen|lt|maj|col|brig|shri|smt|president|prime minister|minister)\b').hasMatch(s)) return 0.15;
      case 'when':
        if (RegExp(r'\b(1[89]\d\d|20\d\d)\b').hasMatch(s)) return 0.35;
        if (RegExp(r'\b(january|february|march|april|may|june|july|august|september|october|november|december|sunday|monday)\b').hasMatch(s)) return 0.3;
      case 'howMany':
        if (RegExp(r'\b\d+\b|\b(two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|seventeen)\b').hasMatch(s)) return 0.3;
      case 'define':
        final first = terms.isEmpty ? '' : terms.first;
        if (RegExp(r'\b(is|are) (a|an|the|defined|known|called|used)\b|\bmeans\b|\brefers to\b|\bis defined\b').hasMatch(s) &&
            tokenize(s.split(RegExp(r'\b(is|are|means|refers)\b')).first).contains(first)) {
          return 0.4;
        }
        if (RegExp(r'\b(is|are) (a|an|the)\b|\bmeans\b|\brefers to\b|\bis called\b|\bknown as\b').hasMatch(s)) return 0.15;
      case 'list':
        if (_listIntro.hasMatch(sentence)) return 0.35;
    }
    if (wantsList && _listIntro.hasMatch(sentence)) return 0.3;
    return 0;
  }
}

/// How much a sentence reads like an answer rather than a heading, a quiz
/// question, a slide fragment or a list of options.
double _quality(String s) {
  var q = 1.0;
  if (s.length < 60) q *= 0.6;
  if (s.length > 500) q *= 0.8;
  if (s.trimRight().endsWith('?')) q *= 0.45;
  if (RegExp(r"\(a\).{1,60}\(b\).{1,60}\(c\)", caseSensitive: false).hasMatch(s)) q *= 0.4; // MCQ options
  if (RegExp(r"^(Let\x27s|Remember|Q\d|Questions?\b|Practice\b)", caseSensitive: false).hasMatch(s)) q *= 0.5;
  if (RegExp(r"^\(?[a-z]\)?\s*Part [IVX]+\b").hasMatch(s)) q *= 0.5; // "(a) Part I - …" lesson outlines
  final words = s.split(RegExp(r'\s+'));
  final capitalised = words.where((w) => w.isNotEmpty && w[0].toUpperCase() == w[0] && RegExp(r'[A-Za-z]').hasMatch(w[0])).length;
  if (words.length > 4 && capitalised / words.length > 0.7) q *= 0.6; // Title Case headings run together
  if (_isHinglish(s)) q *= 0.3;
  return q;
}

const _hinglish = {'ki', 'ka', 'ke', 'hai', 'aur', 'se', 'ko', 'mein', 'nahi', 'karna', 'kiya', 'hota', 'jata', 'tatha', 'hain', 'karen', 'jaye'};

bool _isHinglish(String text) {
  final words = RegExp(r'[a-z]+').allMatches(text.toLowerCase()).map((m) => m.group(0)!).toList();
  if (words.length < 8) return false;
  return words.where(_hinglish.contains).length / words.length > 0.08;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

// ---------------------------------------------------------------------------
// Text helpers
// ---------------------------------------------------------------------------

const _stop = {
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'can', 'do', 'does', 'did', 'for', 'from', 'has', 'have',
  'how', 'i', 'in', 'is', 'it', 'its', 'me', 'my', 'of', 'on', 'or', 'tell', 'that', 'the', 'their', 'there',
  'this', 'to', 'was', 'what', 'when', 'where', 'which', 'who', 'whom', 'why', 'will', 'with', 'you', 'your',
  'about', 'explain', 'describe', 'define', 'meant', 'mean', 'means', 'give', 'list', 'name', 'some', 'any',
  'please', 'kya', 'hai', 'ka', 'ki', 'ke',
};

/// NCC shorthand and common phrasings mapped to the précis' own words.
const synonyms = <String, String>{
  'gr': 'grid reference',
  '8 figure': 'eight figure grid reference',
  '6 figure': 'six figure grid reference',
  'pvc': 'param vir chakra',
  'mvc': 'maha vir chakra',
  'vrc': 'vir chakra',
  'ndma': 'national disaster management authority',
  'ndrf': 'national disaster response force',
  'capf': 'central armed police forces',
  'bsf': 'border security force',
  'crpf': 'central reserve police force',
  'itbp': 'indo tibetan border police',
  'cds': 'chief of defence staff',
  'coas': 'chief of army staff',
  'insas': 'insas rifle',
  'lmg': 'light machine gun',
  'rt': 'radio telephony',
  'gps': 'global positioning system',
  'atc': 'annual training camp',
  'rdc': 'republic day camp',
  'tsc': 'thal sainik camp',
  'ano': 'associate ncc officer',
  'suo': 'senior under officer',
  'north types': 'types of north',
  'dg': 'director general',
  'ddg': 'deputy director general',
  'hq': 'headquarters',
  'wt': 'weapon training',
  'fcbc': 'field craft battle craft',
  'cpr': 'cardio pulmonary resuscitation cpr',
  'ranks': 'appointments',
  'rank': 'appointment',
  'csuo': 'company senior under officer',
  'juo': 'junior under officer',
  'cqms': 'company quarter master sergeant',
  'csm': 'company sergeant major',
  'grit': 'fire control order',
  'nic': 'national integration camp',
  'ebsb': 'ek bharat shreshtha bharat',
  'ssb': 'services selection board',
  'goh': 'guard of honour',
  'raised': 'came into existence formally',
  'gallantry': 'valour',
  'formed': 'came into existence formally',
  'started': 'came into existence formally',
  'map setting': 'setting of map',
};

final _word = RegExp(r'[a-z0-9]+');

String stem(String w) {
  if (w.length > 5 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.length > 5 && w.endsWith('ing')) return w.substring(0, w.length - 3);
  if (w.length > 4 && w.endsWith('es') && !w.endsWith('ses')) return w.substring(0, w.length - 2);
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
  return w;
}

/// Lower-cased words without stop words, before stemming.
List<String> rawWords(String text) => [
      for (final m in _word.allMatches(text.toLowerCase()))
        if (!_stop.contains(m.group(0)) && m.group(0)!.length > 1) m.group(0)!,
    ];

List<String> tokenize(String text) => [
      for (final m in _word.allMatches(text.toLowerCase()))
        if (!_stop.contains(m.group(0)) && m.group(0)!.length > 1) stem(m.group(0)!),
    ];

/// Lecture-slide furniture in the 2025 books that is not content.
final _boilerplate = RegExp(
    r'\b(PREVIEW|INTERESTING FACTS?|DID YOU KNOW\?|AIM|SCOPE)\b(?=\s)|The lecture will be conducted in the following parts?\s*[:.-]*',
    caseSensitive: true);

/// Sentences and list items, short ones included (for showing context).
List<String> splitUnits(String text) => text
    // Wingdings bullets from the PDFs come through as private-use characters.
    .replaceAll(RegExp(r'[\uE000-\uF8FF]'), ' • ')
    .replaceAll(_boilerplate, ' ')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .split(RegExp(r'(?<=[.!?])\s+(?=[A-Z(0-9•➢])|\s(?=\([a-z]{1,3}\)\s)|\s(?=\([ivx]{1,4}\)\s)|\s(?=\d{1,2}\.\s)|\s(?=[•➢▪●]\s?)|(?<=:-)\s+'))
    .map((s) => s.trim())
    .where((s) => s.length >= 3)
    .toList();

/// Splits on sentence ends and on numbered or lettered points like "(b)".
List<String> splitSentences(String text) => text
    .split(RegExp(r'(?<=[.!?])\s+(?=[A-Z(0-9])|\s(?=\([a-z]{1,2}\)\s)|\s(?=\d{1,2}\.\s)'))
    .map((s) => s.trim())
    .where((s) => s.length >= 25)
    .toList();

bool _withinOneEdit(String a, String b) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    // Two neighbouring letters swapped ("nroth" / "north") counts as one typo.
    if (a.length == b.length && i + 1 < a.length && a[i] == b[j + 1] && a[i + 1] == b[j]) {
      i += 2;
      j += 2;
      continue;
    }
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}
