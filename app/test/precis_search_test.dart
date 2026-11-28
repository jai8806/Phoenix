import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/domain/precis_search.dart';

// Made-up passages in précis style (no précis text in this public repo).
const passages = [
  PrecisPassage(
    id: 1, title: 'Demo Map Book', heading: 'MR I · Grid References', page: 166,
    content: 'A grid reference describes a point on a map. A six figure grid reference locates a point '
        'to within 100 metres. An eight figure grid reference locates a point to within 10 metres. '
        'Always read eastings before northings.',
  ),
  PrecisPassage(
    id: 2, title: 'Demo Map Book', heading: 'MR III · Types of North', page: 185, pageEnd: 186,
    content: 'There are three types of north. (a) True north points to the geographic pole. '
        '(b) Magnetic north is shown by the compass needle. (c) Grid north follows the grid lines of the map.',
  ),
  PrecisPassage(
    id: 3, title: 'Demo Awards Book', heading: 'AF III · Gallantry Awards', page: 28,
    content: 'The Param Vir Chakra is the highest wartime gallantry award. It is awarded for the most '
        'conspicuous bravery in the presence of the enemy.',
  ),
  PrecisPassage(
    id: 4, title: 'Demo Drill Book', heading: 'FD-2 · Words of Command', page: 120,
    content: 'On the word of command attention, the cadet brings the left heel in line with the right heel.',
  ),
];

final search = PrecisSearch(passages);

void main() {
  test('finds the right passage and the exact sentence, with citation', () {
    final a = search.answer('What does an eight figure grid reference give?');
    expect(a.found, isTrue);
    expect(a.passages.first.id, 1);
    expect(a.snippets.first.text, 'An eight figure grid reference locates a point to within 10 metres.');
    expect(a.snippets.first.passage.citation, 'Demo Map Book · MR I · Grid References · p. 166');
  });

  test('NCC shorthand is understood', () {
    expect(search.answer('what is PVC').passages.first.id, 3);
    expect(search.answer('explain 8 figure GR').snippets.first.text, contains('eight figure'));
  });

  test('one typo is forgiven', () {
    expect(search.answer('magnetic nroth compas').passages.first.id, 2);
  });

  test('lettered points become separate sentences', () {
    final a = search.answer('what is magnetic north');
    expect(a.snippets.first.text, '(b) Magnetic north is shown by the compass needle.');
    expect(a.snippets.first.passage.pages, '185–186');
  });

  test('questions the material does not cover find nothing', () {
    expect(search.answer('who won the cricket world cup').found, isFalse);
    expect(search.answer('').found, isFalse);
    expect(search.answer('what is the').found, isFalse); // only stop words
  });

  test('passages survive the offline pack round-trip', () {
    final back = PrecisPassage.fromJson(passages[1].toJson());
    expect(back.citation, passages[1].citation);
    expect(back.content, passages[1].content);
  });

  test('stemming matches singular and plural', () {
    expect(stem('awards'), 'award');
    expect(stem('bodies'), 'body');
    expect(stem('compass'), 'compass');
  });
}
