import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/domain/quick_facts.dart';
import 'package:phoenix/features/shared/rich_answer.dart';

void main() {
  test('quick facts match the questions they are for', () {
    expect(quickFactFor('who is dg ncc')?.id, 'dg_ncc');
    expect(quickFactFor('Who is the head of NCC?')?.id, 'dg_ncc');
    expect(quickFactFor('highest rank of ncc cadet')?.id, 'cadet_ranks');
    expect(quickFactFor('what are the ranks in ncc')?.id, 'cadet_ranks');
    expect(quickFactFor('what is a JUO')?.id, 'cadet_ranks');
    expect(quickFactFor('when is ncc day celebrated')?.id, 'ncc_day');
    expect(quickFactFor('when was ncc raised')?.id, 'ncc_raised');
    expect(quickFactFor('motto of ncc')?.id, 'ncc_motto');
  });

  test('and stay out of questions about something else', () {
    expect(quickFactFor('what is the dg ncc commendation card'), isNull);
    expect(quickFactFor('badges of rank of army officers'), isNull);
    expect(quickFactFor('rank of ano'), isNull);
    expect(quickFactFor('what is army day'), isNull);
    expect(quickFactFor('camp routine of ncc day'), isNull);
    expect(quickFactFor('what are the types of north'), isNull);
  });

  test('answers in light markdown become bullets, bold and citations', () {
    final blocks = parseAnswer('**NCC** is a youth organisation [1].\n## Ranks\n- **CSUO**: senior-most\n  * nested\n1. First\n(a) Item\n\n');
    expect(blocks.map((b) => b.marker), [null, null, '•', '•', '1.', '(a)']);
    expect(blocks[1].heading, isTrue);
    expect(blocks[1].text, 'Ranks');
    expect(blocks[3].text, 'nested');
  });
}
