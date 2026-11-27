import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/comms.dart';
import 'models/diary.dart';
import 'models/test.dart';
import 'models/user.dart';
import 'models/ustaad.dart';
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

  Future<UstaadReply> askUstaad(String question);

  /// Every précis passage this member may read, for offline search.
  Future<List<PrecisPassage>> precisPassages();
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
  Future<UstaadReply> askUstaad(String question) async {
    try {
      final res = await _client.functions.invoke('ustaad', body: {'question': question});
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
