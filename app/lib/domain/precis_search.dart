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

  PrecisAnswer answer(String question, {int maxPassages = 3, int maxSnippets = 3}) {
    final (terms, unknown) = queryTerms(question);
    if (terms.isEmpty || passages.isEmpty) return const PrecisAnswer(snippets: [], passages: []);
    final totalWeight = terms.fold(0.0, (a, t) => a + _idf(t)) + unknown * _unknownIdf;

    final scored = <(double, int)>[];
    for (var i = 0; i < passages.length; i++) {
      final tf = _tf[i];
      final len = _docs[i].length;
      var s = 0.0;
      var covered = 0.0;
      for (final t in terms) {
        final f = tf[t];
        if (f == null) continue;
        covered += _idf(t);
        s += _idf(t) * f * (_k1 + 1) / (f + _k1 * (1 - _b + _b * len / _avgLength));
      }
      if (s > 0 && covered / totalWeight >= minCoverage) scored.add((s, i));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final top = scored.take(maxPassages).toList();
    if (top.isEmpty) return const PrecisAnswer(snippets: [], passages: []);

    // Rank sentences inside the top passages by how many distinct (weighted)
    // query terms they contain, nudged by their passage's score.
    final candidates = <(double, Snippet)>[];
    final best = top.first.$1;
    for (final (score, i) in top) {
      for (final sentence in splitSentences(passages[i].content)) {
        final words = tokenize(sentence).toSet();
        var s = 0.0;
        for (final t in terms) {
          if (words.contains(t)) s += _idf(t);
        }
        if (s == 0) continue;
        // Short heading-like lines ("Methods of Judging Distance.") say little.
        final informative = sentence.length < 60 ? 0.55 : (sentence.length > 400 ? 0.8 : 1.0);
        candidates.add(((s + 0.5 * score / best) * informative, Snippet(sentence, passages[i])));
      }
    }
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    final seen = <String>{};
    final snippets = <Snippet>[];
    for (final (_, sn) in candidates) {
      if (seen.add(sn.text)) snippets.add(sn);
      if (snippets.length == maxSnippets) break;
    }
    return PrecisAnswer(snippets: snippets, passages: [for (final (_, i) in top) passages[i]]);
  }
}

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
