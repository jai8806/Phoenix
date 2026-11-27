import '../../domain/study_plan.dart';
import '../models/user.dart';
import '../syllabus/syllabus.dart';
import 'cert_insights.dart';
import 'insights.dart';

enum CertTrack {
  b('B Certificate'),
  c('C Certificate');

  const CertTrack(this.label);
  final String label;
}

/// Weightage for a track, from that certificate's own past paper.
ExamInsights insightsFor(CertTrack track) => track == CertTrack.b ? bCertInsights : cCertInsights;

/// Official SD/SW chapters for a subject, with how often each was asked.
List<StudyChapter> chaptersFor(SubjectInsight s) {
  final shares = {for (final c in s.topChapters) c.code: c.share};
  final books = [specialSyllabus(Wing.army, SyllabusLevel.senior), commonSyllabus(SyllabusLevel.senior)];
  return [
    for (final book in books)
      for (final g in book.groups)
        if (s.groupCodes.contains(g.code))
          for (final ch in g.subjects)
            StudyChapter(subject: s.name, code: ch.code, title: ch.title, share: shares[ch.code] ?? 0),
  ];
}

Map<String, List<StudyChapter>> chaptersBySubject(ExamInsights insights) =>
    {for (final s in insights.subjects) s.name: chaptersFor(s)};

SubjectInsight? subjectNamed(ExamInsights insights, String name) {
  for (final s in insights.subjects) {
    if (s.name == name) return s;
  }
  return null;
}
