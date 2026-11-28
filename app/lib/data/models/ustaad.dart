class UstaadSource {
  const UstaadSource({required this.n, required this.title, this.heading, this.pages});

  final int n;
  final String title;
  final String? heading;
  final String? pages;

  String get label => [title, ?heading, if (pages != null) 'p. $pages'].join(' · ');
}

class UstaadReply {
  const UstaadReply({required this.answer, required this.sources, required this.covered, this.general = false});

  /// Answered from general knowledge because the précis didn't cover it.
  final bool general;

  final String answer;
  final List<UstaadSource> sources;

  /// False when the study material didn't cover the question.
  final bool covered;

  factory UstaadReply.fromJson(Map<String, dynamic> j) => UstaadReply(
        answer: j['answer'] as String? ?? '',
        covered: j['covered'] as bool? ?? false,
        general: j['general'] as bool? ?? false,
        sources: [
          for (final s in (j['sources'] as List? ?? const []))
            UstaadSource(
              n: (s['n'] as num).toInt(),
              title: s['title'] as String? ?? '',
              heading: s['heading'] as String?,
              pages: s['pages'] as String?,
            ),
        ],
      );
}
