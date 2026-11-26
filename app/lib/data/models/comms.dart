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
  });

  final String id;
  final String title;
  final EventKind kind;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? location;
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
