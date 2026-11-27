enum ExamPaper {
  common('Common subjects'),
  special('Special subjects (Army)');

  const ExamPaper(this.label);
  final String label;
}

/// Share of a subject's questions that came from one précis chapter.
class ChapterShare {
  const ChapterShare({required this.code, required this.title, required this.share});

  final String code;
  final String title;

  /// 0..1 of the subject's matched questions.
  final double share;
}

class SubjectInsight {
  const SubjectInsight({
    required this.paper,
    required this.name,
    required this.marks,
    required this.groupCodes,
    required this.bankQuestions,
    required this.topChapters,
    this.bankSections = const [],
    this.note = '',
  });

  final ExamPaper paper;
  final String name;

  /// Marks in the analysed paper.
  final int marks;

  /// Précis lesson-code prefixes for this subject, e.g. ["MR"].
  final List<String> groupCodes;

  /// How many bank and paper questions exist for practice.
  final int bankQuestions;
  final List<ChapterShare> topChapters;

  /// Section names used for this subject in question banks (for practice filters).
  final List<String> bankSections;
  final String note;

  int get questions => marks ~/ 2;
}

class ExamInsights {
  const ExamInsights({
    required this.exam,
    required this.source,
    required this.totalMarks,
    required this.questionCount,
    required this.durationMinutes,
    required this.passRule,
    required this.questionsAnalysed,
    required this.subjects,
  });

  final String exam;
  final String source;
  final int totalMarks;
  final int questionCount;
  final int durationMinutes;
  final String passRule;
  final int questionsAnalysed;
  final List<SubjectInsight> subjects;

  int marksFor(ExamPaper p) => subjects.where((s) => s.paper == p).fold(0, (a, s) => a + s.marks);

  /// Subjects carrying marks, heaviest first.
  List<SubjectInsight> ranked([ExamPaper? paper]) =>
      subjects.where((s) => s.marks > 0 && (paper == null || s.paper == paper)).toList()
        ..sort((a, b) => b.marks.compareTo(a.marks));

  /// Share of the whole paper, 0..1.
  double weight(SubjectInsight s) => s.marks / totalMarks;
}
