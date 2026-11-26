import '../models/user.dart';
import 'army_junior.dart';
import 'army_senior.dart';
import 'common_senior.dart';

class SyllabusSubject {
  const SyllabusSubject({
    required this.code,
    required this.title,
    this.theoryPeriods = 0,
    this.practicalPeriods = 0,
    this.page,
  });

  final String code;
  final String title;
  final int theoryPeriods;
  final int practicalPeriods;

  /// Page in the précis where the chapter starts.
  final int? page;

  int get totalPeriods => theoryPeriods + practicalPeriods;
}

class SubjectGroup {
  const SubjectGroup({required this.code, required this.name, required this.subjects});

  final String code;
  final String name;
  final List<SyllabusSubject> subjects;

  int get totalPeriods => subjects.fold(0, (sum, s) => sum + s.totalPeriods);
}

class Syllabus {
  const Syllabus({required this.source, required this.official, required this.groups});

  /// Where the list comes from, shown to cadets.
  final String source;

  /// True when taken from the official précis; false for placeholder lists.
  final bool official;
  final List<SubjectGroup> groups;

  int get subjectCount => groups.fold(0, (sum, g) => sum + g.subjects.length);
  int get totalPeriods => groups.fold(0, (sum, g) => sum + g.totalPeriods);

  /// Period counts are printed only in some précis editions.
  bool get hasPeriods => totalPeriods > 0;
}

enum SyllabusLevel {
  junior('Junior (JD/JW)'),
  senior('Senior (SD/SW)');

  const SyllabusLevel(this.label);
  final String label;

  static SyllabusLevel of(Division? d) => d == null || d.isSenior ? senior : junior;
}

/// Wing-specific (special subject) syllabus. Official lists are generated from
/// the précis master index; the rest are placeholders until their précis is ingested.
Syllabus specialSyllabus(Wing wing, SyllabusLevel level) {
  if (wing == Wing.army) return level == SyllabusLevel.junior ? armyJunior : armySenior;
  return Syllabus(
    source: 'Provisional list · official précis not yet added',
    official: false,
    groups: [
      SubjectGroup(
        code: wing.name.toUpperCase(),
        name: '${wing.label} subjects',
        subjects: [for (final t in _provisionalWing[wing] ?? const <String>[]) SyllabusSubject(code: '', title: t)],
      ),
    ],
  );
}

/// Common subjects shared by all wings. The SD/SW list is official; the JD/JW
/// common-subject précis has not been ingested yet.
Syllabus commonSyllabus(SyllabusLevel level) =>
    level == SyllabusLevel.senior ? commonSenior : _provisionalCommon;

const _provisionalCommon = Syllabus(
  source: 'Provisional list · official précis not yet added',
  official: false,
  groups: [
    SubjectGroup(code: 'COMMON', name: 'Common subjects', subjects: [
      SyllabusSubject(code: '', title: 'NCC General'),
      SyllabusSubject(code: '', title: 'National Integration & Awareness'),
      SyllabusSubject(code: '', title: 'Drill'),
      SyllabusSubject(code: '', title: 'Weapon Training'),
      SyllabusSubject(code: '', title: 'Personality Development'),
      SyllabusSubject(code: '', title: 'Leadership'),
      SyllabusSubject(code: '', title: 'Disaster Management'),
      SyllabusSubject(code: '', title: 'Social Awareness & Community Development'),
      SyllabusSubject(code: '', title: 'Health & Hygiene'),
      SyllabusSubject(code: '', title: 'Environment Awareness'),
      SyllabusSubject(code: '', title: 'Adventure'),
    ]),
  ],
);

const _provisionalWing = <Wing, List<String>>{
  Wing.army: ['Armed Forces', 'Map Reading', 'Field Craft & Battle Craft', 'Military Communication', 'Weapons & Equipment'],
  Wing.navy: ['Naval Orientation', 'Naval Communication', 'Navigation', 'Seamanship', 'Fire Fighting & Damage Control'],
  Wing.air: ['General Service Knowledge', 'Principles of Flight', 'Airmanship', 'Aircraft Recognition', 'Aero Modelling'],
  Wing.rvc: ['Animal Management', 'Equitation', 'Veterinary First Aid'],
};
