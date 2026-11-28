import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/data/models/comms.dart';
import 'package:phoenix/data/models/user.dart';
import 'package:phoenix/domain/roll_call.dart';

void main() {
  final event = CalendarEvent(id: 'e', title: 'Saturday parade', kind: EventKind.parade,
      startsAt: DateTime(2026, 12, 5, 7, 30), location: 'Parade ground', needsResponse: true);
  const members = [
    AppUser(id: 'ano', fullName: 'Ajay K M', role: AppRole.ano, rank: 'Lt'),
    AppUser(id: 'a', fullName: 'Asha', role: AppRole.cadet, rank: 'CDT'),
    AppUser(id: 'b', fullName: 'Bharat', role: AppRole.seniorCadet, rank: 'SUO'),
    AppUser(id: 'c', fullName: 'Chetan', role: AppRole.cadet, rank: 'CDT'),
  ];
  final responses = [
    const EventResponse(eventId: 'e', cadetId: 'a', status: Attendance.absent, reason: 'University exam'),
    const EventResponse(eventId: 'e', cadetId: 'b', status: Attendance.coming, attended: true),
  ];

  test('splits the unit into coming, absent with reasons and no reply (the ANO is not counted)', () {
    final rc = rollCall(event, members, responses);
    expect(rc.coming.map((r) => r.cadetName), ['SUO Bharat']);
    expect(rc.absent.single.reason, 'University exam');
    expect(rc.noReply.map((m) => m.id), ['c']);
    expect(rc.total, 3);
    expect(rc.attended, {'b'});
  });

  test('the WhatsApp summary has the counts, the reasons and who has not replied', () {
    final text = rollCallSummary(rollCall(event, members, responses));
    expect(text, startsWith('*Saturday parade*\nSat 5 Dec 2026, 7:30 AM · Parade ground'));
    expect(text, contains('Coming: 1  (refreshments: 1)'));
    expect(text, contains('1. CDT Asha – University exam'));
    expect(text, contains('*No reply*\n1. CDT Chetan'));
    expect(text, contains('Present on the day: 1'));
    expect(text, contains('1. SUO Bharat ✓'));
  });

  test('replies close at the reply-by time, or when the event starts', () {
    expect(event.repliesOpen(DateTime(2026, 12, 5, 7)), isTrue);
    expect(event.repliesOpen(DateTime(2026, 12, 5, 8)), isFalse);
    final early = CalendarEvent(id: 'x', title: 'Camp', kind: EventKind.camp, startsAt: DateTime(2026, 12, 20),
        needsResponse: true, respondBy: DateTime(2026, 12, 10));
    expect(early.repliesOpen(DateTime(2026, 12, 11)), isFalse);
  });
}
