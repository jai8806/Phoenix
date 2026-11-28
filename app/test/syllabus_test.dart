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

  test('Army and common SD/SW lists come from the précis', () {
    final army = specialSyllabus(Wing.army, SyllabusLevel.senior);
    expect(army.official, isTrue);
    expect(army.subjectCount, 40);
    expect(army.groups.map((g) => g.code), ['AF', 'MR', 'FC/BC', 'INF', 'MH', 'C']);
    expect(army.hasPeriods, isFalse); // this edition prints no period counts
    final common = commonSyllabus(SyllabusLevel.senior);
    expect(common.official, isTrue);
    expect(common.subjectCount, 103);
    expect(common.groups.length, 11);
  });

  test('wings and levels without an ingested précis fall back to a provisional list', () {
    expect(specialSyllabus(Wing.navy, SyllabusLevel.junior).official, isFalse);
    expect(specialSyllabus(Wing.air, SyllabusLevel.senior).official, isFalse);
    expect(commonSyllabus(SyllabusLevel.junior).official, isFalse);
  });

  test('division maps to syllabus level', () {
    expect(SyllabusLevel.of(Division.jd), SyllabusLevel.junior);
    expect(SyllabusLevel.of(Division.jw), SyllabusLevel.junior);
    expect(SyllabusLevel.of(Division.sd), SyllabusLevel.senior);
    expect(SyllabusLevel.of(null), SyllabusLevel.senior);
  });
}
