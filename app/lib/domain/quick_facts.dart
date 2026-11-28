import 'precis_search.dart';

/// A short, checked answer for questions the précis answers badly or not at
/// all: facts that change (who holds an appointment) and ones scattered
/// across chapters. Each names its source and when it was last checked.
class QuickFact {
  const QuickFact({
    required this.id,
    required this.triggers,
    required this.answer,
    required this.source,
    this.checked,
    this.exclude = const [],
  });

  final String id;

  /// The fact applies when every word of any one group is in the question
  /// (words are stemmed the way the précis search stems them).
  final List<List<String>> triggers;

  /// Questions containing any of these words are about something else.
  final List<String> exclude;

  /// Plain text; lines starting with "- " are shown as bullets, **bold** as bold.
  final String answer;
  final String source;

  /// When a fact that can change was last checked, e.g. "Nov 2026".
  final String? checked;

  bool matches(Set<String> words) =>
      !exclude.any((e) => words.contains(stem(e))) &&
      triggers.any((group) => group.every((w) => words.contains(stem(w))));
}

/// Update these when appointments change; they win over the précis.
const quickFacts = <QuickFact>[
  QuickFact(
    id: 'dg_ncc',
    triggers: [
      ['dg', 'ncc'],
      ['director', 'general', 'ncc'],
      ['head', 'ncc'],
      ['chief', 'ncc'],
      ['heads', 'ncc'],
      ['current', 'dg'],
    ],
    exclude: ['commendation', 'card', 'insignia', 'badge', 'additional', 'deputy', 'adg', 'ddg', 'directorate'],
    answer: '**Lt Gen Virendra Vats**, YSM, SM, VSM, is the **Director General of the NCC (DG NCC)**, the head of the Corps.\n'
        '- He took over on **1 October 2025** from Lt Gen Gurbirpal Singh.\n'
        '- The DG NCC heads **HQ DG NCC in New Delhi** and is an officer of the rank of **Lieutenant General** '
        '(or equivalent from the Navy or Air Force).\n'
        '- Under him: Additional DGs, then **17 Directorates** (each under an ADG/DDG), then Group HQs and units.',
    source: 'HQ DG NCC · organisation from NB & CP SD/SW (Oct 2025) · NCC I · p. 5',
    checked: 'Nov 2026',
  ),
  QuickFact(
    id: 'cadet_ranks',
    triggers: [
      ['rank', 'cadet'],
      ['ranks', 'ncc'],
      ['rank', 'ncc'],
      ['appointment', 'cadet'],
      ['appointments', 'ncc'],
      ['highest', 'cadet'],
      ['senior', 'most', 'cadet'],
      ['csuo'],
      ['juo'],
      ['suo'],
      ['under', 'officer'],
    ],
    exclude: ['ano', 'army', 'navy', 'air', 'badge', 'jco', 'nco', 'dg', 'director', 'instructor', 'uoi', 'commissioned', 'lieutenant', 'captain', 'major'],
    answer: 'Cadet ranks (appointments) in a Senior Division / Senior Wing company, **highest first**:\n'
        '- **CSUO**, Company Senior Under Officer (often called **SUO**): the senior-most cadet, the link between cadets and the ANO.\n'
        '- **JUO**, Junior Under Officer: assists and understudies the CSUO.\n'
        '- **CSM**, Company Sergeant Major: controls the company and keeps the parade state.\n'
        '- **CQMS**, Company Quarter Master Sergeant: helps the ANO issue and receive stores.\n'
        '- **Sergeant**: controls a platoon.\n'
        '- **Corporal**: controls a section.\n'
        '- **Lance Corporal**: assists the corporal.\n'
        'So the **highest rank a cadet can hold is CSUO / SUO**.',
    source: 'Common Subject SD/SW · N-5 · Cadet Appointments · p. 33–34',
  ),
  QuickFact(
    id: 'ncc_day',
    triggers: [
      ['ncc', 'day'],
    ],
    exclude: ['army', 'navy', 'republic', 'independence', 'routine', 'camp'],
    answer: '**NCC Day** is celebrated on the **fourth Sunday of November** every year.\n'
        '- In 2026 it fell on **22 November**; in 2027 it falls on **28 November**.\n'
        '- It marks the raising of the NCC in 1948.',
    source: 'NCC calendar',
  ),
  QuickFact(
    id: 'ncc_raised',
    triggers: [
      ['ncc', 'raised'],
      ['ncc', 'formed'],
      ['ncc', 'established'],
      ['ncc', 'founded'],
      ['ncc', 'started'],
      ['ncc', 'existence'],
      ['ncc', 'act'],
      ['ncc', 'year'],
    ],
    exclude: ['day'],
    answer: 'The NCC formally came into existence on **15 July 1948** through the **NCC Act (Act XXXI of 1948)** of Parliament.\n'
        '- Girls Division: raised July 1949.\n'
        '- Air Wing: 1 April 1950.\n'
        '- Naval Wing: July 1952, so all three services were represented.',
    source: 'Common Subject SD/SW · N-1 · Introduction · p. 3',
  ),
  QuickFact(
    id: 'ncc_motto',
    triggers: [
      ['motto', 'ncc'],
      ['ncc', 'motto'],
    ],
    answer: 'The motto of the NCC is **"Unity and Discipline"** (*Ekta aur Anushasan*).',
    source: 'Common Subject SD/SW · N-1 · p. 3',
  ),
];

QuickFact? quickFactFor(String question) {
  final words = rawWords(question).map(stem).toSet();
  for (final f in quickFacts) {
    if (f.matches(words)) return f;
  }
  return null;
}

/// What Ustaad shows for a question: a checked quick fact when one applies,
/// and the précis' own words.
class UstaadAnswer {
  const UstaadAnswer({this.fact, required this.precis});
  final QuickFact? fact;
  final PrecisAnswer precis;

  bool get found => fact != null || precis.found;

  /// Everything shown, as plain text (for tests and the AI prompt).
  String get displayText => [
        if (fact != null) fact!.answer.replaceAll('**', '').replaceAll('*', ''),
        for (final s in precis.snippets) s.text,
      ].join('\n');

  String get source => fact?.source ?? (precis.snippets.isEmpty ? '' : precis.snippets.first.passage.citation);
}

UstaadAnswer askUstaad(String question, PrecisSearch search, {bool preferSenior = true}) {
  final fact = quickFactFor(question);
  final precis = search.answer(question, preferSenior: preferSenior, maxSnippets: fact == null ? 3 : 2);
  return UstaadAnswer(fact: fact, precis: precis);
}
