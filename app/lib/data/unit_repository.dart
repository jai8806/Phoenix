import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/comms.dart';
import 'models/diary.dart';
import 'models/figure.dart';
import 'models/test.dart';
import 'models/user.dart';
import 'models/ustaad.dart';
import '../domain/omr/progress.dart';
import '../domain/precis_search.dart';

/// Everything a signed-in member reads or writes for their unit.
abstract interface class UnitRepository {
  Future<List<Announcement>> announcements();
  Future<void> postAnnouncement({required String title, required String body, bool pinned = false});

  Future<List<CalendarEvent>> events();
  Future<void> addEvent(CalendarEvent event);

  Future<List<DiaryEntry>> diary();
  Future<void> addDiaryEntry(DiaryEntry entry);

  /// Approved questions the cadet can practise with (unit bank and shared approved ones).
  Future<List<Question>> approvedQuestions();
  Future<List<ReviewItem>> reviewQueue();
  Future<void> approveQuestion(String id, int answer);

  Future<List<KnowledgeDocument>> documents();

  /// The AI's plain explanation. [chunkIds] are the précis passages the app
  /// already found and [facts] any checked quick fact, so both answers agree.
  ///
  /// [mode] 'answer' writes Ustaad's main answer; 'simple' explains it more simply.
  Future<UstaadReply> askUstaad(String question,
      {List<int> chunkIds = const [], List<String> facts = const [], String mode = 'simple'});

  /// Every précis passage this member may read, for offline search.
  Future<List<PrecisPassage>> precisPassages();

  /// Figures (maps, signs, badges, diagrams) with their chapter and page.
  Future<List<PrecisFigure>> figures();

  /// Short-lived links to figure files, keyed by storage path.
  Future<Map<String, String>> figureUrls(List<String> paths);

  // Hosted tests ------------------------------------------------------------

  /// The unit's tests, newest first, with the member's own score on each.
  Future<List<TestDefinition>> tests();
  Future<List<Question>> testQuestions(String testId);
  Future<void> createTest(NewTest test);
  Future<void> deleteTest(String testId);

  /// Marked on the server; returns the score. A cadet can submit once.
  /// For an OMR mock, pass the uploaded sheet photo and how it was read.
  Future<double> submitAttempt(String testId, Map<String, int> answers,
      {int focusLost = 0, String? sheetPath, String? setLabel, int scanFlags = 0, int corrected = 0});

  /// ANO / senior cadet: starts an OMR mock now; it closes after the paper and the upload window.
  Future<TestDefinition> startTest(TestDefinition test);

  /// Uploads the cadet's sheet photo; returns its storage path.
  Future<String> uploadSheet(String testId, Uint8List jpeg);

  /// Short-lived link to a sheet photo.
  Future<String?> sheetUrl(String path);

  /// Submitted attempts with every answer and its question: the member's own,
  /// or the whole unit's for admins.
  Future<List<AttemptHistory>> attemptHistory({bool wholeUnit = false});

  /// The member's own answers to a test they took.
  Future<Map<String, int?>> myAnswers(String testId);

  /// Every attempt at a test (admins).
  Future<List<AttemptRecord>> testAttempts(String testId);

  /// Every score in the unit (admins), for averages.
  Future<List<ScoreRow>> unitScores();

  // Roster ------------------------------------------------------------------

  Future<List<AppUser>> members();

  /// ANO only: change a member's role or rank.
  Future<void> updateMember(String id, {required AppRole role, String? rank});
}

/// Thrown with a message that is safe to show.
class UnitDataFailure implements Exception {
  const UnitDataFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class SupabaseUnitRepository implements UnitRepository {
  SupabaseUnitRepository(this._client, this._user);

  final SupabaseClient _client;
  final AppUser _user;

  String get _unitId => _user.unitId!;

  Future<T> _guard<T>(Future<T> Function() run, String doing) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      throw UnitDataFailure(e.message.contains('row-level security')
          ? "You don't have permission to $doing."
          : "Couldn't $doing. Check your connection and try again.");
    } on UnitDataFailure {
      rethrow;
    } catch (_) {
      throw UnitDataFailure("Couldn't $doing. Check your connection and try again.");
    }
  }

  @override
  Future<List<Announcement>> announcements() => _guard(() async {
        final rows = await _client
            .from('announcements')
            .select('id, title, body, pinned, created_at, author:profiles(full_name, rank)')
            .order('created_at', ascending: false)
            .limit(100);
        return [for (final r in rows) announcementFromRow(r)];
      }, 'load announcements');

  @override
  Future<void> postAnnouncement({required String title, required String body, bool pinned = false}) =>
      _guard(() async {
        await _client.from('announcements').insert({
          'unit_id': _unitId,
          'author_id': _user.id,
          'title': title,
          'body': body,
          'pinned': pinned,
        });
      }, 'post the announcement');

  @override
  Future<List<CalendarEvent>> events() => _guard(() async {
        final rows = await _client.from('calendar_events').select().order('starts_at').limit(500);
        return [for (final r in rows) eventFromRow(r)];
      }, 'load the calendar');

  @override
  Future<void> addEvent(CalendarEvent e) => _guard(() async {
        await _client.from('calendar_events').insert({
          'unit_id': _unitId,
          'title': e.title,
          'kind': e.kind.name,
          'starts_at': e.startsAt.toUtc().toIso8601String(),
          'ends_at': e.endsAt?.toUtc().toIso8601String(),
          'location': e.location,
          'created_by': _user.id,
        });
      }, 'add the event');

  @override
  Future<List<DiaryEntry>> diary() => _guard(() async {
        final rows = await _client
            .from('diary_entries')
            .select()
            .eq('cadet_id', _user.id)
            .order('happened_on', ascending: false)
            .order('created_at', ascending: false)
            .limit(500);
        return [for (final r in rows) diaryFromRow(r)];
      }, 'load your diary');

  @override
  Future<void> addDiaryEntry(DiaryEntry e) => _guard(() async {
        await _client.from('diary_entries').insert({...diaryToRow(e), 'cadet_id': _user.id});
      }, 'save the session');

  @override
  Future<List<Question>> approvedQuestions() => _guard(() async {
        final rows = await _client
            .from('questions')
            .select('id, subject, prompt, options, correct_index, explanation')
            .eq('status', 'approved')
            .limit(2000);
        return [for (final r in rows) questionFromRow(r)];
      }, 'load practice questions');

  @override
  Future<List<ReviewItem>> reviewQueue() => _guard(() async {
        final rows = await _client.rpc('review_queue', params: {'max_rows': 100}) as List;
        return [for (final r in rows) reviewItemFromRow(r as Map<String, dynamic>)];
      }, 'load questions to review');

  @override
  Future<void> approveQuestion(String id, int answer) => _guard(() async {
        await _client.rpc('adopt_question', params: {'qid': id, 'answer': answer});
      }, 'approve the question');

  @override
  Future<List<KnowledgeDocument>> documents() => _guard(() async {
        final rows = await _client
            .from('documents')
            .select('id, title, wing, division_level, unit_id, storage_path')
            .order('title');
        return [
          for (final r in rows)
            KnowledgeDocument(
              id: r['id'] as String,
              title: r['title'] as String,
              scope: [
                r['unit_id'] == null ? 'Official syllabus' : 'Unit upload',
                if (r['wing'] != null) (r['wing'] as String)[0].toUpperCase() + (r['wing'] as String).substring(1),
                if (r['division_level'] != null) r['division_level'] == 'junior' ? 'JD/JW' : 'SD/SW',
                (r['storage_path'] as String).split('/').last,
              ].join(' · '),
              status: DocumentStatus.ready,
            ),
        ];
      }, 'load the knowledge base');

  @override
  Future<List<PrecisPassage>> precisPassages() => _guard(() async {
        const pageSize = 1000;
        final out = <PrecisPassage>[];
        for (var from = 0;; from += pageSize) {
          final rows = await _client
              .from('document_chunks')
              .select('id, page, page_end, heading, content, documents(title)')
              .order('id')
              .range(from, from + pageSize - 1);
          for (final r in rows) {
            out.add(PrecisPassage(
              id: (r['id'] as num).toInt(),
              title: (r['documents'] as Map<String, dynamic>?)?['title'] as String? ?? 'Précis',
              heading: r['heading'] as String? ?? '',
              content: r['content'] as String,
              page: (r['page'] as num?)?.toInt(),
              pageEnd: (r['page_end'] as num?)?.toInt(),
            ));
          }
          if (rows.length < pageSize) break;
        }
        return out;
      }, 'download the study material');

  @override
  Future<List<PrecisFigure>> figures() => _guard(() async {
        final out = <PrecisFigure>[];
        const pageSize = 1000;
        for (var from = 0;; from += pageSize) {
          final rows = await _client
              .from('figures')
              .select('id, document_title, chapter_code, page, storage_path, width, height')
              .order('chapter_code')
              .order('page')
              .range(from, from + pageSize - 1);
          for (final r in rows) {
            out.add(PrecisFigure(
              id: r['id'] as String,
              title: r['document_title'] as String,
              chapterCode: r['chapter_code'] as String,
              page: (r['page'] as num?)?.toInt(),
              path: r['storage_path'] as String,
              width: (r['width'] as num?)?.toInt(),
              height: (r['height'] as num?)?.toInt(),
            ));
          }
          if (rows.length < pageSize) break;
        }
        return out;
      }, 'load the figures');

  @override
  Future<Map<String, String>> figureUrls(List<String> paths) => _guard(() async {
        if (paths.isEmpty) return const {};
        final results = await _client.storage.from('precis-figures').createSignedUrlsResult(paths, 60 * 60 * 12);
        // Files not uploaded yet come back as failures and simply show a placeholder.
        return {for (final r in results.whereType<SignedUrlSuccess>()) r.path: r.signedUrl};
      }, 'load the figures');

  @override
  Future<List<TestDefinition>> tests() => _guard(() async {
        final rows = await _client
            .from('tests')
            .select('id, title, description, duration_minutes, marks_correct, marks_wrong, opens_at, closes_at, '
                'mode, pattern, sheet_code, started_at, upload_minutes, set_seed, '
                'test_questions(question_id, position), test_attempts(count)')
            .order('created_at', ascending: false)
            .limit(200);
        final mine = await _client.from('test_attempts').select('test_id, score').eq('cadet_id', _user.id);
        final scores = {for (final r in mine) r['test_id'] as String: (r['score'] as num?)?.toDouble() ?? 0};
        return [for (final r in rows) testFromRow(r, myScore: scores[r['id']])];
      }, 'load tests');

  @override
  Future<List<Question>> testQuestions(String testId) => _guard(() async {
        final rows = await _client
            .from('test_questions')
            .select('position, questions(id, subject, prompt, options, correct_index, explanation)')
            .eq('test_id', testId)
            .order('position');
        return [
          for (final r in rows)
            if (r['questions'] != null) questionFromRow(r['questions'] as Map<String, dynamic>),
        ];
      }, 'load the test');

  @override
  Future<void> createTest(NewTest t) => _guard(() async {
        final row = await _client
            .from('tests')
            .insert({
              'unit_id': _unitId,
              'title': t.title,
              'description': t.description,
              'duration_minutes': t.durationMinutes,
              'marks_correct': t.marking.correct,
              'marks_wrong': t.marking.wrong,
              'opens_at': t.opensAt?.toUtc().toIso8601String(),
              'closes_at': t.closesAt?.toUtc().toIso8601String(),
              'created_by': _user.id,
              'mode': t.mode.name,
              'pattern': t.pattern,
              'sheet_code': t.sheetCode,
              'upload_minutes': t.uploadMinutes,
              'set_seed': t.setSeed,
            })
            .select('id')
            .single();
        final id = row['id'] as String;
        try {
          await _client.from('test_questions').insert([
            for (var i = 0; i < t.questionIds.length; i++)
              {'test_id': id, 'question_id': t.questionIds[i], 'position': t.numbers?[i] ?? i + 1},
          ]);
        } catch (_) {
          await _client.from('tests').delete().eq('id', id);
          rethrow;
        }
      }, 'create the test');

  @override
  Future<void> deleteTest(String testId) => _guard(() async {
        await _client.from('tests').delete().eq('id', testId);
      }, 'delete the test');

  @override
  Future<double> submitAttempt(String testId, Map<String, int> answers,
      {int focusLost = 0, String? sheetPath, String? setLabel, int scanFlags = 0, int corrected = 0}) async {
    try {
      final score = await _client.rpc('submit_attempt', params: {
        'tid': testId,
        'answers': answers,
        'focus_lost': focusLost,
        'sheet_path': ?sheetPath,
        'set_label': ?setLabel,
        'scan_flags': scanFlags,
        'corrected': corrected,
      });
      return (score as num).toDouble();
    } on PostgrestException catch (e) {
      // The function's own messages are written for cadets.
      const known = ['already taken', 'has closed', 'not opened', 'not found', 'not started', 'not yours'];
      throw UnitDataFailure(known.any(e.message.contains)
          ? '${e.message}.'
          : "Couldn't submit your answers. Check your connection and try again; your answers are kept.");
    } catch (_) {
      throw const UnitDataFailure(
          "Couldn't submit your answers. Check your connection and try again; your answers are kept.");
    }
  }

  @override
  Future<TestDefinition> startTest(TestDefinition test) => _guard(() async {
        final now = DateTime.now().toUtc();
        final closes = now.add(Duration(minutes: test.durationMinutes + test.uploadMinutes));
        final rows = await _client
            .from('tests')
            .update({
              'started_at': now.toIso8601String(),
              'opens_at': now.toIso8601String(),
              'closes_at': closes.toIso8601String(),
            })
            .eq('id', test.id)
            .select('id');
        if (rows.isEmpty) throw const UnitDataFailure('Only your ANO or a senior cadet can start the exam.');
        return test.copyWith(startedAt: now.toLocal(), opensAt: now.toLocal(), closesAt: closes.toLocal());
      }, 'start the exam');

  @override
  Future<String> uploadSheet(String testId, Uint8List jpeg) => _guard(() async {
        final path = '$_unitId/$testId/${_user.id}.jpg';
        await _client.storage
            .from('omr-sheets')
            .uploadBinary(path, jpeg, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
        return path;
      }, 'upload your sheet photo');

  @override
  Future<String?> sheetUrl(String path) => _guard(() async {
        return _client.storage.from('omr-sheets').createSignedUrl(path, 60 * 30);
      }, 'open the sheet photo');

  @override
  Future<List<AttemptHistory>> attemptHistory({bool wholeUnit = false}) => _guard(() async {
        var query = _client.from('test_attempts').select(
            'test_id, cadet_id, score, submitted_at, profiles(full_name, rank), '
            'tests(title, marks_correct, marks_wrong, pattern), '
            'attempt_answers(chosen_index, questions(id, subject, prompt, options, correct_index, explanation))');
        if (!wholeUnit) query = query.eq('cadet_id', _user.id);
        final rows = await query.order('submitted_at').limit(wholeUnit ? 1500 : 300);
        return [for (final r in rows) historyFromRow(r)];
      }, 'load progress');

  @override
  Future<Map<String, int?>> myAnswers(String testId) => _guard(() async {
        final rows = await _client
            .from('test_attempts')
            .select('attempt_answers(question_id, chosen_index)')
            .eq('test_id', testId)
            .eq('cadet_id', _user.id);
        if (rows.isEmpty) return const {};
        return answersFromRows(rows.first['attempt_answers'] as List? ?? const []);
      }, 'load your answers');

  @override
  Future<List<AttemptRecord>> testAttempts(String testId) => _guard(() async {
        final rows = await _client
            .from('test_attempts')
            .select('cadet_id, score, submitted_at, focus_lost_count, sheet_path, set_label, scan_flags, corrected, '
                'profiles(full_name, rank), attempt_answers(question_id, chosen_index)')
            .eq('test_id', testId);
        return [for (final r in rows) attemptFromRow(r)];
      }, 'load the results');

  @override
  Future<List<ScoreRow>> unitScores() => _guard(() async {
        final rows = await _client.from('test_attempts').select('test_id, cadet_id, score').limit(5000);
        return [
          for (final r in rows)
            ScoreRow(
              testId: r['test_id'] as String,
              cadetId: r['cadet_id'] as String,
              score: (r['score'] as num?)?.toDouble() ?? 0,
            ),
        ];
      }, 'load scores');

  @override
  Future<List<AppUser>> members() => _guard(() async {
        final rows = await _client
            .from('profiles')
            .select('id, full_name, role, rank, regimental_no, wing, division, training_year, unit_id')
            .eq('unit_id', _unitId)
            .order('full_name');
        return [for (final r in rows) appUserFromRow(r)];
      }, 'load the roster');

  @override
  Future<void> updateMember(String id, {required AppRole role, String? rank}) => _guard(() async {
        final rows = await _client
            .from('profiles')
            .update({'role': roleToDb(role), 'rank': rank})
            .eq('id', id)
            .select('id');
        // Row-level security turns a forbidden update into "no rows changed".
        if (rows.isEmpty) throw const UnitDataFailure('Only the ANO can change roles and ranks.');
      }, 'update the cadet');

  @override
  Future<UstaadReply> askUstaad(String question,
      {List<int> chunkIds = const [], List<String> facts = const [], String mode = 'simple'}) async {
    try {
      final res = await _client.functions.invoke('ustaad', body: {
        'question': question,
        'mode': mode,
        if (chunkIds.isNotEmpty) 'chunk_ids': chunkIds.take(8).toList(),
        if (facts.isNotEmpty) 'facts': facts.take(2).toList(),
      });
      return UstaadReply.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on FunctionException catch (e) {
      throw UnitDataFailure(ustaadErrorMessage(e.status, e.details));
    } catch (_) {
      throw const UnitDataFailure("Couldn't reach Ustaad. Check your connection and try again.");
    }
  }
}

// ---------------------------------------------------------------------------
// Row mapping (pure, unit-tested)
// ---------------------------------------------------------------------------

DateTime _time(Object? v) => DateTime.parse(v as String).toLocal();

Announcement announcementFromRow(Map<String, dynamic> r) {
  final author = r['author'] as Map<String, dynamic>?;
  final name = author == null
      ? 'Unit'
      : [if (author['rank'] != null) author['rank'], author['full_name']].join(' ');
  return Announcement(
    id: r['id'] as String,
    title: r['title'] as String,
    body: r['body'] as String,
    author: name,
    createdAt: _time(r['created_at']),
    pinned: r['pinned'] as bool? ?? false,
  );
}

CalendarEvent eventFromRow(Map<String, dynamic> r) => CalendarEvent(
      id: r['id'] as String,
      title: r['title'] as String,
      kind: EventKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => EventKind.event),
      startsAt: _time(r['starts_at']),
      endsAt: r['ends_at'] == null ? null : _time(r['ends_at']),
      location: r['location'] as String?,
    );

const _sessionDb = {
  SessionType.drill: 'drill',
  SessionType.shooting: 'shooting',
  SessionType.pt: 'pt',
  SessionType.mapReading: 'map_reading',
  SessionType.obstacle: 'obstacle',
  SessionType.cultural: 'cultural',
  SessionType.sscd: 'sscd',
  SessionType.ceremonial: 'ceremonial',
  SessionType.other: 'other',
};

Map<String, dynamic> diaryToRow(DiaryEntry e) {
  final s = e.shooting;
  final d = e.date;
  return {
    'session_type': _sessionDb[e.type],
    'happened_on': '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    'duration_minutes': e.durationMinutes,
    'went_well': e.wentWell,
    'to_improve': e.toImprove,
    'instructor_notes': e.instructorNotes,
    'mood': e.mood,
    'fatigue': e.fatigue,
    'sleep_hours': e.sleepHours,
    'visibility': e.sharedWithUnit ? 'shared_with_unit' : 'private',
    'metrics': s == null
        ? <String, dynamic>{}
        : {
            'rifle': s.rifle,
            'position': s.position.name,
            'distance_m': s.distanceMetres,
            'rounds': s.rounds,
            if (s.score != null) 'score': s.score,
            if (s.groupMm != null) 'group_mm': s.groupMm,
          },
  };
}

DiaryEntry diaryFromRow(Map<String, dynamic> r) {
  final type = _sessionDb.entries.firstWhere((e) => e.value == r['session_type'],
      orElse: () => const MapEntry(SessionType.other, 'other')).key;
  final m = Map<String, dynamic>.from(r['metrics'] as Map? ?? const {});
  final shooting = type == SessionType.shooting && m.isNotEmpty
      ? ShootingMetrics(
          rifle: m['rifle'] as String? ?? 'Rifle',
          position: ShootingPosition.values.firstWhere((p) => p.name == m['position'],
              orElse: () => ShootingPosition.prone),
          distanceMetres: (m['distance_m'] as num?)?.toInt() ?? 0,
          rounds: (m['rounds'] as num?)?.toInt() ?? 0,
          score: (m['score'] as num?)?.toInt(),
          groupMm: (m['group_mm'] as num?)?.toDouble(),
        )
      : null;
  return DiaryEntry(
    id: r['id'] as String,
    type: type,
    date: DateTime.parse(r['happened_on'] as String),
    durationMinutes: (r['duration_minutes'] as num?)?.toInt(),
    wentWell: r['went_well'] as String?,
    toImprove: r['to_improve'] as String?,
    instructorNotes: r['instructor_notes'] as String?,
    mood: (r['mood'] as num?)?.toInt(),
    fatigue: (r['fatigue'] as num?)?.toInt(),
    sleepHours: (r['sleep_hours'] as num?)?.toDouble(),
    shooting: shooting,
    sharedWithUnit: r['visibility'] == 'shared_with_unit',
  );
}

Question questionFromRow(Map<String, dynamic> r) => Question(
      id: r['id'] as String,
      subject: _subjectLabel(r['subject'] as String?, r['explanation'] as String?),
      prompt: r['prompt'] as String,
      options: [for (final o in r['options'] as List) o as String],
      correctIndex: (r['correct_index'] as num).toInt(),
      explanation: null,
    );

ReviewItem reviewItemFromRow(Map<String, dynamic> r) => ReviewItem(
      id: r['id'] as String,
      prompt: r['prompt'] as String,
      options: [for (final o in r['options'] as List) o as String],
      source: [r['subject'], r['explanation']].whereType<String>().join(' · '),
      page: (r['source_page'] as num?)?.toInt(),
    );

TestDefinition testFromRow(Map<String, dynamic> r, {double? myScore}) {
  final tq = [for (final q in r['test_questions'] as List? ?? const []) q as Map<String, dynamic>]
    ..sort((a, b) => ((a['position'] as num?) ?? 0).compareTo((b['position'] as num?) ?? 0));
  final counts = r['test_attempts'] as List?;
  return TestDefinition(
    id: r['id'] as String,
    title: r['title'] as String,
    mode: r['mode'] == 'omr' ? TestMode.omr : TestMode.app,
    pattern: r['pattern'] as String?,
    sheetCode: (r['sheet_code'] as num?)?.toInt(),
    startedAt: r['started_at'] == null ? null : _time(r['started_at']),
    uploadMinutes: (r['upload_minutes'] as num?)?.toInt() ?? 20,
    setSeed: (r['set_seed'] as num?)?.toInt() ?? 0,
    numbers: [for (final q in tq) ((q['position'] as num?) ?? 0).toInt()],
    description: r['description'] as String?,
    durationMinutes: (r['duration_minutes'] as num).toInt(),
    marking: MarkingScheme(
      correct: (r['marks_correct'] as num?)?.toDouble() ?? 2,
      wrong: (r['marks_wrong'] as num?)?.toDouble() ?? 0,
    ),
    questionIds: [for (final q in tq) q['question_id'] as String],
    opensAt: r['opens_at'] == null ? null : _time(r['opens_at']),
    closesAt: r['closes_at'] == null ? null : _time(r['closes_at']),
    myScore: myScore,
    attemptCount: counts == null || counts.isEmpty ? 0 : ((counts.first as Map)['count'] as num?)?.toInt() ?? 0,
  );
}

AttemptHistory historyFromRow(Map<String, dynamic> r) {
  final t = r['tests'] as Map<String, dynamic>? ?? const {};
  final p = r['profiles'] as Map<String, dynamic>?;
  return AttemptHistory(
    testId: r['test_id'] as String,
    testTitle: t['title'] as String? ?? 'Test',
    cadetId: r['cadet_id'] as String,
    cadetName: p == null ? 'Cadet' : [if (p['rank'] != null) p['rank'], p['full_name']].join(' '),
    score: (r['score'] as num?)?.toDouble() ?? 0,
    submittedAt: r['submitted_at'] == null ? null : _time(r['submitted_at']),
    pattern: t['pattern'] as String?,
    marking: MarkingScheme(
      correct: (t['marks_correct'] as num?)?.toDouble() ?? 2,
      wrong: (t['marks_wrong'] as num?)?.toDouble() ?? 0,
    ),
    answers: [
      for (final a in r['attempt_answers'] as List? ?? const [])
        if ((a as Map)['questions'] != null && (a['questions'] as Map)['correct_index'] != null)
          AnsweredQuestion(questionFromRow(Map<String, dynamic>.from(a['questions'] as Map)), (a['chosen_index'] as num?)?.toInt()),
    ],
  );
}

Map<String, int?> answersFromRows(List rows) => {
      for (final a in rows) (a as Map)['question_id'] as String: (a['chosen_index'] as num?)?.toInt(),
    };

AttemptRecord attemptFromRow(Map<String, dynamic> r) {
  final p = r['profiles'] as Map<String, dynamic>?;
  return AttemptRecord(
    cadetId: r['cadet_id'] as String,
    cadetName: p == null ? 'Cadet' : [if (p['rank'] != null) p['rank'], p['full_name']].join(' '),
    score: (r['score'] as num?)?.toDouble() ?? 0,
    submittedAt: r['submitted_at'] == null ? null : _time(r['submitted_at']),
    focusLost: (r['focus_lost_count'] as num?)?.toInt() ?? 0,
    sheetPath: r['sheet_path'] as String?,
    setLabel: r['set_label'] as String?,
    scanFlags: (r['scan_flags'] as num?)?.toInt() ?? 0,
    corrected: (r['corrected'] as num?)?.toInt() ?? 0,
    answers: answersFromRows(r['attempt_answers'] as List? ?? const []),
  );
}

/// Précis questions store their chapter in `explanation` ("AF I · Q3"); show the chapter as the subject.
String _subjectLabel(String? subject, String? explanation) {
  final chapter = explanation?.split(' · Q').first;
  return chapter != null && chapter != explanation ? chapter : (subject ?? 'General');
}

/// What to tell the cadet when the Ustaad function call fails.
String ustaadErrorMessage(int status, Object? details) {
  if (details is Map && details['error'] is String) return details['error'] as String;
  if (status == 404) return "Ustaad isn't switched on for your unit yet. Ask your ANO to set it up.";
  if (status == 401) return 'Your session has expired. Sign out and sign in again.';
  return "Ustaad couldn't answer just now. Try again in a moment.";
}
