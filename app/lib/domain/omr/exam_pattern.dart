import 'dart:math';

import '../../data/models/test.dart';

/// One subject block of a paper, e.g. "Map Reading, 12 questions".
class PatternSection {
  const PatternSection(this.subject, this.count, {this.labels = const [], this.codes = const []});

  final String subject;
  final int count;

  /// Question-bank section names that belong here ("Map Reading (MR)").
  final List<String> labels;

  /// Précis chapter code prefixes that belong here ("MR" for "MR III").
  final List<String> codes;

  bool matches(Question q) {
    if (labels.contains(q.subject) || q.subject == subject) return true;
    final prefix = chapterPrefix(q.subject);
    return prefix != null && codes.contains(prefix);
  }
}

/// "MR III" -> "MR", "FC/BC-2" -> "FC/BC", "C-1" -> "C"; null for names.
String? chapterPrefix(String label) {
  final m = RegExp(r'^([A-Z][A-Z/]{0,5})[\s-]+(?:[IVXL]+|\d{1,2})$').firstMatch(label.trim());
  return m?.group(1);
}

class PatternPaper {
  const PatternPaper(this.title, this.sections);
  final String title; // "PAPER - II : WEAPON TRAINING"
  final List<PatternSection> sections;
  int get count => sections.fold(0, (a, s) => a + s.count);
}

/// The shape of a real certificate paper.
class ExamPattern {
  const ExamPattern({
    required this.id,
    required this.name,
    required this.heading,
    required this.papers,
    this.durationMinutes = 180,
    this.marking = const MarkingScheme(correct: 2, wrong: 0.5),
    this.passPercent = 33,
  });

  final String id; // 'bcert' | 'ccert'
  final String name;

  /// Printed on the sheet, e.g. "'B' CERTIFICATE EXAMINATION".
  final String heading;
  final List<PatternPaper> papers;
  final int durationMinutes;
  final MarkingScheme marking;

  /// Pass mark in each paper, as a percentage of that paper's marks.
  final double passPercent;

  int get questionCount => papers.fold(0, (a, p) => a + p.count);
  double get totalMarks => questionCount * marking.correct;

  /// Sheet number (1-based) where each paper starts.
  List<int> get paperStarts {
    final out = <int>[];
    var n = 1;
    for (final p in papers) {
      out.add(n);
      n += p.count;
    }
    return out;
  }

  /// Which paper and section a sheet number belongs to.
  (PatternPaper, PatternSection) slot(int number) {
    var n = 1;
    for (final p in papers) {
      for (final s in p.sections) {
        if (number < n + s.count) return (p, s);
        n += s.count;
      }
    }
    throw RangeError.range(number, 1, questionCount);
  }

  static ExamPattern byId(String id) => id == 'ccert' ? cCertPattern : bCertPattern;
}



/// B Certificate, Karnataka & Goa Directorate, as in the 2026 papers (Sets 1 and 2).
const bCertPattern = ExamPattern(
  id: 'bcert',
  name: 'B Certificate',
  heading: "'B' CERTIFICATE MOCK EXAMINATION",
  papers: [
    PatternPaper('PAPER - II : WEAPON TRAINING', [
      PatternSection('Weapon Training', 15, labels: ['Weapon Training'], codes: ['WT']),
    ]),
    PatternPaper('PAPER - III : MISCELLANEOUS', [
      PatternSection('NCC General', 3, labels: ['NCC General'], codes: ['N', 'NCC']),
      PatternSection('National Integration & Awareness', 10, labels: ['National Integration', 'NCC Integration and Awareness'], codes: ['NI']),
      PatternSection('Personality Development', 30, labels: ['Personality Development'], codes: ['PDLS']),
      PatternSection('Leadership', 9, labels: ['Leadership'], codes: ['L', 'ME']),
      PatternSection('Disaster Management', 9, labels: ['Disaster Management'], codes: ['DM']),
      PatternSection('Social Service & Community Development', 16,
          labels: ['Social Service & Community Development (SSCD)', 'PMJAY'], codes: ['SA', 'SSCD']),
      PatternSection('Health & Hygiene', 13, labels: ['Health and Hygiene'], codes: ['H', 'PMW']),
      PatternSection('Adventure', 8, labels: ['Adventure'], codes: ['ADV']),
      PatternSection('Obstacle Training', 3, labels: ['Obstacle Training'], codes: ['OT']),
      PatternSection('Border & Coastal Areas', 4, labels: ['Border And Coastal Areas'], codes: ['BCA']),
    ]),
    PatternPaper('PAPER - IV : SPECIALISED SUBJECTS', [
      PatternSection('Armed Forces', 10, labels: ['Armed Forces'], codes: ['AF']),
      PatternSection('Map Reading', 12, labels: ['Map Reading (MR)', 'Map Reading'], codes: ['MR']),
      PatternSection('Field Craft & Battle Craft', 12,
          labels: ['Field Craft And Battle Craft (Fc & Bc)', 'Field Craft & Battle Craft (Fc & Bc)', 'Field Craft & Battle Craft'],
          codes: ['FCBC', 'FC/BC']),
      PatternSection('Infantry Weapons & Equipment', 8,
          labels: ['Introduction To Infantry Weapons And Equipment', 'Infantry Weapons & Equipment'], codes: ['INF', 'MWE']),
      PatternSection('Military History', 10, labels: ['Military History (MH)', 'Military History'], codes: ['MH']),
      PatternSection('Communication', 3, labels: ['Communication'], codes: ['C', 'MC']),
    ]),
  ],
);

/// C Certificate, by the subject weights of the 2024-25 paper.
const cCertPattern = ExamPattern(
  id: 'ccert',
  name: 'C Certificate',
  heading: "'C' CERTIFICATE MOCK EXAMINATION",
  papers: [
    PatternPaper('PAPER - I : COMMON SUBJECTS', [
      PatternSection('Weapon Training', 5, labels: ['Weapon Training'], codes: ['WT']),
      PatternSection('Personality Development', 35, labels: ['Personality Development'], codes: ['PDLS']),
      PatternSection('Social Service & Community Development', 18,
          labels: ['Social Service & Community Development (SSCD)', 'PMJAY'], codes: ['SA', 'SSCD']),
      PatternSection('Health & Hygiene', 14, labels: ['Health and Hygiene'], codes: ['H', 'PMW']),
      PatternSection('Disaster Management', 11, labels: ['Disaster Management'], codes: ['DM']),
      PatternSection('Leadership', 10, labels: ['Leadership'], codes: ['L', 'ME']),
      PatternSection('Environment Awareness', 10, labels: ['Environmental Awareness And Conservation'], codes: ['E', 'EA']),
      PatternSection('Obstacle Training', 7, labels: ['Obstacle Training'], codes: ['OT']),
      PatternSection('National Integration & Awareness', 5, labels: ['National Integration', 'NCC Integration and Awareness'], codes: ['NI']),
      PatternSection('Border & Coastal Areas', 5, labels: ['Border And Coastal Areas'], codes: ['BCA']),
    ]),
    PatternPaper('PAPER - II : SPECIALISED SUBJECTS', [
      PatternSection('Field Craft & Battle Craft', 16,
          labels: ['Field Craft And Battle Craft (Fc & Bc)', 'Field Craft & Battle Craft (Fc & Bc)', 'Field Craft & Battle Craft'],
          codes: ['FCBC', 'FC/BC']),
      PatternSection('Map Reading', 15, labels: ['Map Reading (MR)', 'Map Reading'], codes: ['MR']),
      PatternSection('Military History', 10, labels: ['Military History (MH)', 'Military History'], codes: ['MH']),
      PatternSection('Infantry Weapons & Equipment', 6,
          labels: ['Introduction To Infantry Weapons And Equipment', 'Infantry Weapons & Equipment'], codes: ['INF', 'MWE']),
      PatternSection('Armed Forces', 5, labels: ['Armed Forces'], codes: ['AF']),
      PatternSection('Communication', 3, labels: ['Communication'], codes: ['C', 'MC']),
    ]),
  ],
);

/// Questions for a mock in [pattern]: sheet number -> question id, with
/// numbers left empty where the bank is short. [shortfall] says by how much.
class PatternPick {
  const PatternPick(this.byNumber, this.shortfall);
  final Map<int, String> byNumber;
  final Map<String, int> shortfall; // subject -> missing questions
  bool get complete => shortfall.isEmpty;
}

PatternPick pickForPattern(ExamPattern pattern, List<Question> bank, {Random? rng}) {
  rng ??= Random();
  final used = <String>{};
  final byNumber = <int, String>{};
  final shortfall = <String, int>{};
  var n = 1;
  for (final paper in pattern.papers) {
    for (final s in paper.sections) {
      final pool = bank.where((q) => !used.contains(q.id) && s.matches(q)).toList()..shuffle(rng);
      for (var i = 0; i < s.count; i++) {
        if (i < pool.length) {
          byNumber[n + i] = pool[i].id;
          used.add(pool[i].id);
        }
      }
      if (pool.length < s.count) shortfall[s.subject] = s.count - pool.length;
      n += s.count;
    }
  }
  return PatternPick(byNumber, shortfall);
}

/// Set A2 asks the same questions in a different order within each paper,
/// so neighbours on different sets can't copy. Deterministic per [seed].
Map<int, int> setA2Order(ExamPattern pattern, int seed) {
  final rng = Random(seed);
  final out = <int, int>{};
  for (final (i, paper) in pattern.papers.indexed) {
    final start = pattern.paperStarts[i];
    final numbers = [for (var k = 0; k < paper.count; k++) start + k];
    final shuffled = [...numbers]..shuffle(rng);
    for (var k = 0; k < numbers.length; k++) {
      out[numbers[k]] = shuffled[k]; // A1 number -> A2 number
    }
  }
  return out;
}

/// Each paper's marks and pass/fail, from per-question results.
class PaperResult {
  const PaperResult(this.paper, this.score, this.max, this.passPercent);
  final PatternPaper paper;
  final double score;
  final double max;
  final double passPercent;
  double get percent => max == 0 ? 0 : score / max * 100;
  bool get passed => percent >= passPercent;
}

/// [answers] maps sheet number -> chosen option; [key] maps sheet number -> question.
List<PaperResult> paperResults(ExamPattern pattern, Map<int, Question> key, Map<int, int?> answers) {
  final out = <PaperResult>[];
  for (final (i, paper) in pattern.papers.indexed) {
    final start = pattern.paperStarts[i];
    var score = 0.0, max = 0.0;
    for (var n = start; n < start + paper.count; n++) {
      final q = key[n];
      if (q == null) continue;
      max += pattern.marking.correct;
      final a = answers[n];
      if (a == null) continue;
      score += a == q.correctIndex ? pattern.marking.correct : -pattern.marking.wrong;
    }
    out.add(PaperResult(paper, score, max, pattern.passPercent));
  }
  return out;
}
