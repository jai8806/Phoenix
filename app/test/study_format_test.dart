import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/domain/precis_search.dart';
import 'package:phoenix/domain/study_format.dart';

void main() {
  test('lists, labels and paragraph numbers are formatted for reading', () {
    final out = formatForStudy('12. The youth of today are the leaders of tomorrow and the NCC trains them in many useful ways. '
        'There are three types of north:- (a) True North. It points to the geographic pole. '
        '(b) Magnetic North. Shown by the compass needle. • Grid North follows the grid lines.');
    final lines = out.split('\n');
    expect(lines.first, startsWith('The youth of today'));
    expect(lines, contains('**There are three types of north:**'));
    expect(out, contains('(a) **True North.** It points to the geographic pole.'));
    expect(out, contains('(b) **Magnetic North.** Shown by the compass needle.'));
    expect(out, contains('- Grid North follows the grid lines.'));
  });

  test('ordinary sentences are not mistaken for labels', () {
    expect(formatForStudy('The cadets reported at the venue at 0730 hrs and were briefed.'), isNot(contains('**')));
  });

  test('key points come from the summary when there is one', () {
    const chapter = [
      PrecisPassage(id: 1, title: 'B', heading: 'MR III · North · Introduction', content: 'Maps show the ground. They are drawn to scale for soldiers.'),
      PrecisPassage(id: 2, title: 'B', heading: 'MR III · North · Summary',
          content: '(a) There are three types of north used in map reading. (b) Magnetic north changes slowly every year.'),
    ];
    expect(keyPoints(chapter), ['There are three types of north used in map reading.', 'Magnetic north changes slowly every year.']);
    const defined = [
      PrecisPassage(id: 3, title: 'B', heading: 'MR III · North · Part II',
          content: 'These are:- (a) True North. It is the direction of the geographic North Pole. '
              '(b) Grid North. It is the north shown by the grid lines. (c) Magnetic North. It refers to where the compass needle points.'),
    ];
    expect(keyPoints(defined), [
      '**True North**: the direction of the geographic North Pole.',
      '**Grid North**: the north shown by the grid lines.',
      '**Magnetic North**: where the compass needle points.',
    ]);
    expect(readMinutes(chapter), 1);
  });
}
