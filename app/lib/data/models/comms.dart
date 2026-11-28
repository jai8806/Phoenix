class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    required this.createdAt,
    this.pinned = false,
  });

  final String id;
  final String title;
  final String body;
  final String author;
  final DateTime createdAt;
  final bool pinned;
}

enum EventKind {
  parade('Parade'),
  camp('Camp'),
  exam('Exam'),
  test('Test'),
  event('Event');

  const EventKind(this.label);
  final String label;
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.kind,
    required this.startsAt,
    this.endsAt,
    this.location,
    this.details,
    this.needsResponse = false,
    this.respondBy,
  });

  final String id;
  final String title;
  final EventKind kind;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? location;

  /// The message to cadets, e.g. "Report 0730 in full uniform".
  final String? details;

  /// Cadets must say whether they are coming.
  final bool needsResponse;

  /// Replies close then; null means when the event starts.
  final DateTime? respondBy;

  DateTime get repliesCloseAt => respondBy ?? startsAt;
  bool repliesOpen(DateTime now) => needsResponse && now.isBefore(repliesCloseAt);
}

enum Attendance { coming, absent }

/// A cadet's answer to a roll-call, and whether they actually came.
class EventResponse {
  const EventResponse({
    required this.eventId,
    required this.cadetId,
    required this.status,
    this.cadetName = '',
    this.reason,
    this.respondedAt,
    this.attended,
  });

  final String eventId;
  final String cadetId;
  final String cadetName;
  final Attendance status;
  final String? reason;
  final DateTime? respondedAt;

  /// Marked by an admin on the day; null until then.
  final bool? attended;

  EventResponse copyWith({Attendance? status, String? Function()? reason, bool? Function()? attended}) => EventResponse(
        eventId: eventId,
        cadetId: cadetId,
        cadetName: cadetName,
        status: status ?? this.status,
        reason: reason == null ? this.reason : reason(),
        respondedAt: respondedAt,
        attended: attended == null ? this.attended : attended(),
      );
}

class KnowledgeDocument {
  const KnowledgeDocument({
    required this.id,
    required this.title,
    required this.scope,
    required this.status,
  });

  final String id;
  final String title;

  /// e.g. "Army · Senior" or "Unit upload".
  final String scope;
  final DocumentStatus status;
}

enum DocumentStatus {
  awaitingUpload('Awaiting upload'),
  processing('Processing'),
  ready('Ready');

  const DocumentStatus(this.label);
  final String label;
}
