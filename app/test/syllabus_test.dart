import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/data/models/user.dart';
import 'package:phoenix/data/syllabus/syllabus.dart';

void main() {
  test('Army junior list matches the précis master index totals', () {
    final s = specialSyllabus(Wing.army, SyllabusLevel.junior);
    expect(s.official, isTrue);
    expect(s.subjectCount, 25);
    expect(s.groups.map((g) => g.code), ['AF', 'FCBC', 'MC', 'MR', 'MWE']);
    // The index totals 31 theory + 16 practical periods.
    final theory = s.groups.expand((g) => g.subjects).fold(0, (a, x) => a + x.theoryPeriods);
    final practical = s.groups.expand((g) => g.subjects).fold(0, (a, x) => a + x.practicalPeriods);
    expect((theory, practical), (31, 16));
    expect(s.groups.firstWhere((g) => g.code == 'MR').totalPeriods, 27);
  });

  test('wings and levels without an ingested précis fall back to a provisional list', () {
    expect(specialSyllabus(Wing.army, SyllabusLevel.senior).official, isFalse);
    expect(specialSyllabus(Wing.navy, SyllabusLevel.junior).official, isFalse);
    expect(commonSyllabus.official, isFalse);
  });

  test('division maps to syllabus level', () {
    expect(SyllabusLevel.of(Division.jd), SyllabusLevel.junior);
    expect(SyllabusLevel.of(Division.jw), SyllabusLevel.junior);
    expect(SyllabusLevel.of(Division.sd), SyllabusLevel.senior);
    expect(SyllabusLevel.of(null), SyllabusLevel.senior);
  });
}
