import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/domain/omr/exam_pattern.dart';
import 'package:phoenix/domain/omr/omr_layout.dart';
import 'package:phoenix/domain/omr/omr_scanner.dart';

import 'synthetic_sheet.dart';

Marks randomMarks(math.Random rng, int count, {double blank = 0.08}) => {
      for (var q = 1; q <= count; q++)
        if (rng.nextDouble() > blank) q: [rng.nextInt(4)],
    };

void main() {
  final layout = OmrLayout.forPattern(bCertPattern);

  test('sheet code round-trips and rejects a damaged code', () {
    for (final code in [0, 1, 0xA2F3, 0xFFFF]) {
      expect(OmrLayout.decodeCode(OmrLayout.encodeCode(code)), code);
    }
    final bits = OmrLayout.encodeCode(0xA2F3);
    bits[7] = !bits[7];
    expect(OmrLayout.decodeCode(bits), isNull);
  });

  test('layout has every question of the pattern, inside the page', () {
    expect(layout.bubbles.length, 175);
    for (final row in layout.bubbles.values) {
      for (final b in row) {
        expect(b.x, inInclusiveRange(15, 195));
        expect(b.y, inInclusiveRange(84, 277));
      }
    }
    expect(OmrLayout.forPattern(cCertPattern).bubbles.length, 175);
  });

  test('decision rules: clear, blank, double, faint and rubbed-out marks', () {
    expect(decideMarks([0.12, 0.7, 0.13, 0.11]).choice, 1);
    expect(decideMarks([0.12, 0.7, 0.13, 0.11]).flag, isNull);
    expect(decideMarks([0.12, 0.14, 0.13, 0.11]).state, MarkState.blank);
    expect(decideMarks([0.65, 0.7, 0.13, 0.11]).state, MarkState.multiple);
    expect(decideMarks([0.12, 0.31, 0.13, 0.11]).flag, 'faint');
    expect(decideMarks([0.12, 0.72, 0.33, 0.11]).flag, 'unclear');
  });

  final cases = <String, PhotoOptions>{
    'straight, good light': const PhotoOptions(tilt: 0.01, shadow: 0.05, noise: 4, blur: 0),
    'tilted with a shadow': const PhotoOptions(tilt: 0.05, shadow: 0.45),
    'upside down': const PhotoOptions(turns: 2),
    'sideways (landscape photo)': const PhotoOptions(turns: 1, tilt: 0.03),
    'dim, noisy, blurry, low quality JPEG': const PhotoOptions(shadow: 0.55, noise: 18, blur: 2, jpegQuality: 45),
    'blue pen, lighter ink': const PhotoOptions(penDarkness: 95),
  };
  for (final (i, e) in cases.entries.indexed) {
    test('reads every answer: ${e.key}', () {
      final rng = math.Random(100 + i);
      final marks = randomMarks(rng, 175);
      final sheet = drawSheet(layout, marks, code: 0xA2F3 + i, set: i.isEven ? 'A1' : 'A2', o: e.value, rng: rng);
      final scan = scanOmrImage(photograph(sheet, o: e.value, rng: rng), layout);
      expect(scan.problem, isNull);
      expect(scan.sheetCode, 0xA2F3 + i);
      expect(scan.setLabel, i.isEven ? 'A1' : 'A2');
      var wrong = 0;
      for (var q = 1; q <= 175; q++) {
        final want = marks[q]?.single;
        if (scan.answers[q] != want) wrong++;
      }
      expect(wrong, 0, reason: 'misread $wrong of 175');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('double marks and faint marks are flagged for the cadet to check', () {
    final rng = math.Random(7);
    final marks = randomMarks(rng, 175, blank: 0)
      ..[5] = [0, 2]
      ..[40] = [1];
    const o = PhotoOptions(faint: {40});
    final scan = scanOmrImage(photograph(drawSheet(layout, marks, code: 77, set: 'A1', o: o, rng: rng), o: o, rng: rng), layout);
    expect(scan.reads[5]!.state, MarkState.multiple);
    expect(scan.answers[5], -1);
    expect(scan.reads[40]!.flag, isNotNull);
    expect(scan.flagged.toSet(), {5, 40});
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a photo without the corner squares asks for a better photo', () {
    final sheet = drawSheet(layout, const {}, code: 1);
    // Crop away the bottom of the sheet.
    final scan = scanGray(Gray.fromImage(sheet.clone()..frames.first), layout);
    expect(scan.ok, isTrue); // the full flat sheet reads fine
    final cropped = scanGray(_crop(sheet), layout);
    expect(cropped.problem, contains('four black corner squares'));
  });
}

Gray _crop(dynamic sheet) {
  final g = Gray.fromImage(sheet);
  final h = g.height * 2 ~/ 3;
  return Gray(g.width, h, g.data.sublist(0, g.width * h));
}
