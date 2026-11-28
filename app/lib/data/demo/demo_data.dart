import '../models/comms.dart';
import '../models/diary.dart';
import '../models/roster.dart';
import '../models/test.dart';
import '../models/user.dart';

/// Sample data for demo mode. The unit and its rhythm follow NCC RVCE; the
/// people and records are made up.
abstract final class DemoData {
  static const unitName = 'NCC RVCE · 2/2 Coy, 6 Kar Sig Regt';

  static const cadet = AppUser(
    id: 'demo-cadet',
    fullName: 'Aarav Menon',
    role: AppRole.cadet,
    rank: 'CDT',
    regimentalNo: 'KA24SDA000001',
    wing: Wing.army,
    division: Division.sd,
    trainingYear: 2,
    unitName: unitName,
    isSample: true,
  );

  static const seniorCadet = AppUser(
    id: 'demo-suo',
    fullName: 'Diya Rao',
    role: AppRole.seniorCadet,
    rank: 'SUO',
    regimentalNo: 'KA23SWA000002',
    wing: Wing.army,
    division: Division.sw,
    trainingYear: 3,
    unitName: unitName,
    isSample: true,
  );

  static const ano = AppUser(
    id: 'demo-ano',
    fullName: 'Kavitha Iyer',
    role: AppRole.ano,
    rank: 'Lt',
    unitName: unitName,
    isSample: true,
  );

  static AppUser forRole(AppRole role) => switch (role) {
        AppRole.cadet => cadet,
        AppRole.seniorCadet => seniorCadet,
        AppRole.ano => ano,
      };

  static List<RosterCadet> roster() => const [
        RosterCadet(user: cadet, periodsAttended: 61, periodsHeld: 90, campDone: true, mockAverage: 64),
        RosterCadet(
            user: seniorCadet,
            periodsAttended: 38,
            periodsHeld: 44,
            campDone: true,
            certificatesHeld: {'B'},
            mockAverage: 81),
        RosterCadet(
            user: AppUser(
                id: 'c3', fullName: 'Rohan Gowda', role: AppRole.cadet, rank: 'LCPL',
                wing: Wing.army, division: Division.sd, trainingYear: 2),
            periodsAttended: 80, periodsHeld: 90, campDone: true, mockAverage: 72),
        RosterCadet(
            user: AppUser(
                id: 'c4', fullName: 'Sneha Kulkarni', role: AppRole.cadet, rank: 'CDT',
                wing: Wing.army, division: Division.sw, trainingYear: 2),
            periodsAttended: 70, periodsHeld: 90, campDone: false, mockAverage: 58),
        RosterCadet(
            user: AppUser(
                id: 'c5', fullName: 'Imran Shaikh', role: AppRole.cadet, rank: 'CPL',
                wing: Wing.army, division: Division.sd, trainingYear: 2),
            periodsAttended: 88, periodsHeld: 90, campDone: true, mockAverage: 88),
        RosterCadet(
            user: AppUser(
                id: 'c6', fullName: 'Ananya Das', role: AppRole.cadet, rank: 'CDT',
                wing: Wing.army, division: Division.sw, trainingYear: 1),
            periodsAttended: 30, periodsHeld: 45, campDone: false),
      ];

  static List<Announcement> announcements(DateTime now) => [
        Announcement(
          id: 'a1',
          title: 'B Certificate practicals: uniform check on Saturday',
          body: 'All second-year cadets report in full uniform at 0730 for inspection before the practical exam.',
          author: 'Lt Kavitha Iyer',
          createdAt: now.subtract(const Duration(hours: 5)),
          pinned: true,
        ),
        Announcement(
          id: 'a2',
          title: 'Shaurya at 8th Mile: volunteers needed',
          body: 'We run map reading, Kholna-Jodna, obstacle training and the weapon display again this year. '
              'Second-years, give your names to the SUO by Friday.',
          author: 'SUO Diya Rao',
          createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        ),
        Announcement(
          id: 'a3',
          title: 'SSCD: blood donation camp with the Rotaract Club',
          body: 'Volunteers report at the BT Quadrangle at 0730 to set up registration and manage the crowd. '
              'Counts towards your SSCD hours.',
          author: 'Lt Kavitha Iyer',
          createdAt: now.subtract(const Duration(days: 3)),
        ),
      ];

  static List<CalendarEvent> events(DateTime now) {
    final d = DateTime(now.year, now.month, now.day);
    // Parades are on Saturdays (and general holidays), 20 in a year.
    final saturday = d.add(Duration(days: (DateTime.saturday - d.weekday) % 7));
    return [
      CalendarEvent(
          id: 'e1', title: 'Saturday parade', kind: EventKind.parade,
          startsAt: saturday.add(const Duration(hours: 7, minutes: 30)), location: 'RVCE parade ground'),
      CalendarEvent(
          id: 'e2', title: 'Shaurya at 8th Mile', kind: EventKind.event,
          startsAt: d.add(const Duration(days: 8, hours: 9)),
          endsAt: d.add(const Duration(days: 9, hours: 17)), location: 'Old Library, RVCE'),
      CalendarEvent(
          id: 'e3', title: 'Saturday parade', kind: EventKind.parade,
          startsAt: saturday.add(const Duration(days: 14, hours: 7, minutes: 30)), location: 'RVCE parade ground'),
      CalendarEvent(
          id: 'e4', title: 'Combined Annual Training Camp', kind: EventKind.camp,
          startsAt: d.add(const Duration(days: 30)),
          endsAt: d.add(const Duration(days: 39)), location: 'Camp site (TBC)'),
      CalendarEvent(
          id: 'e5', title: 'B Certificate exam', kind: EventKind.exam,
          startsAt: d.add(const Duration(days: 81, hours: 9)), location: 'Exam centre (TBC)'),
    ];
  }

  /// Small starter set of general NCC questions. The full bank is generated
  /// from the official precis and approved by the ANO.
  static const questions = [
    Question(
      id: 'q1', subject: 'NCC General', prompt: 'What is the motto of the NCC?',
      options: ['Service Before Self', 'Unity and Discipline', 'Duty, Honour, Courage', 'Valour and Faith'],
      correctIndex: 1,
      explanation: 'The NCC motto is "Unity and Discipline" (Ekta aur Anushasan).'),
    Question(
      id: 'q2', subject: 'NCC General', prompt: 'In which year was the NCC raised?',
      options: ['1947', '1948', '1950', '1962'], correctIndex: 1,
      explanation: 'The NCC was raised in 1948 under the NCC Act.'),
    Question(
      id: 'q3', subject: 'NCC General', prompt: 'NCC Day is celebrated on the…',
      options: ['Second Sunday of November', 'Fourth Sunday of November', '15 January', '26 January'],
      correctIndex: 1),
    Question(
      id: 'q4', subject: 'NCC General', prompt: 'Where is the Headquarters of the Directorate General NCC?',
      options: ['Pune', 'Dehradun', 'New Delhi', 'Kolkata'], correctIndex: 2),
    Question(
      id: 'q5', subject: 'NCC General', prompt: 'The three colours of the NCC flag stand for…',
      options: ['The three services', 'Three founding states', 'Three ranks', 'Land, sea and sky only'],
      correctIndex: 0,
      explanation: 'Red, dark blue and light blue represent the Army, Navy and Air Force.'),
    Question(
      id: 'q6', subject: 'Drill', prompt: 'The word of command "Savdhan" means…',
      options: ['Stand at ease', 'Attention', 'Quick march', 'Salute'], correctIndex: 1),
    Question(
      id: 'q7', subject: 'Drill', prompt: 'The word of command "Vishram" means…',
      options: ['Attention', 'Halt', 'Stand at ease', 'About turn'], correctIndex: 2),
    Question(
      id: 'q8', subject: 'Map Reading', prompt: 'A six-figure grid reference locates a point to within…',
      options: ['1 metre', '10 metres', '100 metres', '1 kilometre'], correctIndex: 2,
      explanation: 'Six figures give 100 m precision; eight figures give 10 m.'),
    Question(
      id: 'q9', subject: 'Map Reading', prompt: 'Which compass is used for map reading in NCC training?',
      options: ['Prismatic compass', 'Gyro compass', 'Sun compass', 'Magnetic needle only'], correctIndex: 0),
    Question(
      id: 'q10', subject: 'Disaster Management', prompt: 'Who chairs the National Disaster Management Authority (NDMA)?',
      options: ['Home Minister', 'Prime Minister', 'President', 'Defence Minister'], correctIndex: 1),
    Question(
      id: 'q11', subject: 'Health & Hygiene', prompt: 'For adult CPR, the ratio of chest compressions to rescue breaths is…',
      options: ['15:2', '30:2', '5:1', '10:1'], correctIndex: 1),
    Question(
      id: 'q12', subject: 'Health & Hygiene', prompt: 'Malaria is spread by the bite of the female…',
      options: ['Aedes mosquito', 'Culex mosquito', 'Anopheles mosquito', 'Sandfly'], correctIndex: 2),
    Question(
      id: 'q13', subject: 'Leadership', prompt: 'In a SWOT analysis, the "O" stands for…',
      options: ['Objectives', 'Opportunities', 'Obstacles', 'Operations'], correctIndex: 1),
    Question(
      id: 'q14', subject: 'Environment Awareness', prompt: 'World Environment Day is observed on…',
      options: ['22 April', '5 June', '16 September', '2 October'], correctIndex: 1),
    Question(
      id: 'q15', subject: 'National Integration & Awareness', prompt: 'India\'s highest wartime gallantry award is the…',
      options: ['Ashoka Chakra', 'Maha Vir Chakra', 'Param Vir Chakra', 'Kirti Chakra'], correctIndex: 2),
  ];

  static List<TestDefinition> tests(DateTime now) => [
        TestDefinition(
          id: 't1',
          title: 'Mock test #3 · Drill, WT, Map Reading',
          durationMinutes: 30,
          marking: const MarkingScheme(correct: 2, wrong: 0.5),
          questionIds: const ['q6', 'q7', 'q8', 'q9'],
          opensAt: now.subtract(const Duration(days: 1)),
        ),
        TestDefinition(
          id: 't2',
          title: 'NCC General quick check',
          durationMinutes: 10,
          marking: const MarkingScheme(),
          questionIds: const ['q1', 'q2', 'q3', 'q4', 'q5'],
          opensAt: now.add(const Duration(days: 3)),
        ),
      ];

  static List<KnowledgeDocument> documents() => [
        for (final wing in ['Army', 'Navy', 'Air Force', 'RVC'])
          for (final level in ['Junior', 'Senior'])
            KnowledgeDocument(
              id: '$wing-$level',
              title: '$wing precis ($level)',
              scope: 'Official syllabus · $wing · $level',
              status: DocumentStatus.awaitingUpload,
            ),
      ];

  static List<DiaryEntry> diary(DateTime now) {
    DateTime ago(int d) => now.subtract(Duration(days: d));
    ShootingMetrics s(int score, double group) => ShootingMetrics(
        rifle: '.22 rifle', position: ShootingPosition.prone, distanceMetres: 25,
        rounds: 5, score: score, groupMm: group);
    return [
      DiaryEntry(
          id: 'd1', type: SessionType.shooting, date: ago(1), durationMinutes: 60,
          shooting: s(44, 10), wentWell: 'Breathing pause felt natural.',
          toImprove: 'Last two rounds drifted right.', mood: 4, fatigue: 2, sleepHours: 7.5),
      DiaryEntry(
          id: 'd2', type: SessionType.drill, date: ago(2), durationMinutes: 45,
          instructorNotes: 'Arm swing to shoulder height.', mood: 3, fatigue: 3, sleepHours: 6),
      DiaryEntry(
          id: 'd3', type: SessionType.shooting, date: ago(3), durationMinutes: 60,
          shooting: s(40, 12), toImprove: 'Trigger squeeze rushed.', mood: 3, fatigue: 3, sleepHours: 5.5),
      DiaryEntry(id: 'd4', type: SessionType.pt, date: ago(4), durationMinutes: 40, mood: 4, fatigue: 4),
      DiaryEntry(id: 'd5', type: SessionType.shooting, date: ago(8), shooting: s(34, 16), sleepHours: 7),
      DiaryEntry(id: 'd6', type: SessionType.shooting, date: ago(12), shooting: s(31, 18), sleepHours: 6.5),
      DiaryEntry(id: 'd7', type: SessionType.shooting, date: ago(15), shooting: s(29, 20), sleepHours: 6),
    ];
  }
}
