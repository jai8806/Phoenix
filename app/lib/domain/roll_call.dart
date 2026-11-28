import 'package:intl/intl.dart';

import '../data/models/comms.dart';
import '../data/models/user.dart';

/// Where a roll-call stands: who is coming, who has permission to be absent
/// (and why), who hasn't replied, and who actually came.
class RollCall {
  RollCall({required this.event, required this.coming, required this.absent, required this.noReply, required this.attended});

  final CalendarEvent event;
  final List<EventResponse> coming;
  final List<EventResponse> absent;
  final List<AppUser> noReply;

  /// Cadet ids marked present on the day.
  final Set<String> attended;

  int get total => coming.length + absent.length + noReply.length;
}

/// [members] is everyone expected (the ANO is left out).
RollCall rollCall(CalendarEvent event, List<AppUser> members, List<EventResponse> responses) {
  final expected = [for (final m in members) if (!m.role.isAno) m];
  final names = {for (final m in expected) m.id: m.displayName};
  final byCadet = {for (final r in responses) r.cadetId: r};
  String nameOf(EventResponse r) => r.cadetName.isNotEmpty ? r.cadetName : (names[r.cadetId] ?? 'Cadet');
  int byName(EventResponse a, EventResponse b) => nameOf(a).compareTo(nameOf(b));
  final named = [
    for (final r in responses)
      EventResponse(
        eventId: r.eventId,
        cadetId: r.cadetId,
        cadetName: nameOf(r),
        status: r.status,
        reason: r.reason,
        respondedAt: r.respondedAt,
        attended: r.attended,
      ),
  ];
  return RollCall(
    event: event,
    coming: [for (final r in named) if (r.status == Attendance.coming) r]..sort(byName),
    absent: [for (final r in named) if (r.status == Attendance.absent) r]..sort(byName),
    noReply: [for (final m in expected) if (!byCadet.containsKey(m.id)) m]..sort((a, b) => a.displayName.compareTo(b.displayName)),
    attended: {for (final r in responses) if (r.attended == true) r.cadetId},
  );
}

/// The summary for the ANO, ready to paste into WhatsApp.
String rollCallSummary(RollCall rc, {String? unitName}) {
  final e = rc.event;
  final b = StringBuffer()
    ..writeln('*${e.title}*')
    ..writeln(DateFormat('EEE d MMM yyyy, h:mm a').format(e.startsAt) + (e.location == null ? '' : ' · ${e.location}'));
  if (unitName != null) b.writeln(unitName);
  b
    ..writeln()
    ..writeln('Coming: ${rc.coming.length}  (refreshments: ${rc.coming.length})')
    ..writeln('Permission to be absent: ${rc.absent.length}')
    ..writeln('No reply: ${rc.noReply.length}');
  if (rc.attended.isNotEmpty) b.writeln('Present on the day: ${rc.attended.length}');
  if (rc.absent.isNotEmpty) {
    b
      ..writeln()
      ..writeln('*Absent with permission*');
    for (final (i, r) in rc.absent.indexed) {
      b.writeln('${i + 1}. ${r.cadetName} – ${r.reason ?? ''}');
    }
  }
  if (rc.noReply.isNotEmpty) {
    b
      ..writeln()
      ..writeln('*No reply*');
    for (final (i, m) in rc.noReply.indexed) {
      b.writeln('${i + 1}. ${m.displayName}');
    }
  }
  if (rc.coming.isNotEmpty) {
    b
      ..writeln()
      ..writeln('*Coming*');
    for (final (i, r) in rc.coming.indexed) {
      b.writeln('${i + 1}. ${r.cadetName}${rc.attended.isEmpty ? '' : (rc.attended.contains(r.cadetId) ? ' ✓' : ' ✗')}');
    }
  }
  b
    ..writeln()
    ..write('Compiled in Phoenix');
  return b.toString();
}
