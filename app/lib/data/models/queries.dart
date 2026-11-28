import 'dart:math';

/// What an anonymous query is about.
enum QueryCategory {
  personal('Personal problem'),
  ragging('Ragging / bullying'),
  health('Health'),
  studies('Studies / exams'),
  camp('Camp'),
  unit('Unit matters'),
  other('Something else');

  const QueryCategory(this.label);
  final String label;
}

enum QueryStatus {
  open('Waiting for a reply'),
  answered('Answered'),
  escalated('Raised with the ANO'),
  closed('Closed');

  const QueryStatus(this.label);
  final String label;
}

class QueryMessage {
  const QueryMessage({required this.id, required this.fromSenior, required this.body, required this.createdAt, this.seniorLabel});

  final String id;
  final bool fromSenior;

  /// e.g. "CSUO": who replied, never the asker.
  final String? seniorLabel;
  final String body;
  final DateTime createdAt;
}

/// A question asked without a name. [token] is the asker's private ticket
/// code (only on their own phone); seniors never see it.
class AnonQuery {
  const AnonQuery({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.toAllSeniors = false,
    this.token,
  });

  final String id;
  final String subject;
  final QueryCategory category;
  final QueryStatus status;

  /// The asker let JUO, CSM and CQMS see it as well as the CSUO / SUO.
  final bool toAllSeniors;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<QueryMessage> messages;
  final String? token;

  /// Seniors: the asker wrote last, so it needs a reply.
  bool get awaitingSenior => messages.isNotEmpty && !messages.last.fromSenior && status != QueryStatus.closed;

  /// Asker: a senior wrote last.
  bool get hasReply => messages.isNotEmpty && messages.last.fromSenior;
}

const _ticketAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O, 1/I

/// A fresh private ticket code: 24 random characters.
String newTicketCode([Random? rng]) {
  rng ??= Random.secure();
  return List.generate(24, (_) => _ticketAlphabet[rng!.nextInt(_ticketAlphabet.length)]).join();
}

/// "ABCD-EFGH-…" for reading out or writing down.
String formatTicket(String code) => [for (var i = 0; i < code.length; i += 4) code.substring(i, min(i + 4, code.length))].join('-');

/// What someone typed back into a ticket code (spaces, dashes, lower case).
String? parseTicket(String typed) {
  final c = typed.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return c.length >= 20 ? c : null;
}

QueryMessage queryMessageFromRow(Map<String, dynamic> m) => QueryMessage(
      id: m['id'] as String,
      fromSenior: m['from_senior'] == true,
      seniorLabel: m['senior_label'] as String?,
      body: m['body'] as String,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    );

AnonQuery anonQueryFromRow(Map<String, dynamic> r) {
  final msgs = [
    for (final m in (r['messages'] ?? r['query_messages']) as List? ?? const []) queryMessageFromRow(m as Map<String, dynamic>),
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return AnonQuery(
    id: r['id'] as String,
    token: r['token'] as String?,
    subject: r['subject'] as String,
    category: QueryCategory.values.firstWhere((c) => c.name == r['category'], orElse: () => QueryCategory.other),
    status: QueryStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => QueryStatus.open),
    toAllSeniors: r['audience'] == 'seniors',
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(r['updated_at'] as String).toLocal(),
    messages: msgs,
  );
}
