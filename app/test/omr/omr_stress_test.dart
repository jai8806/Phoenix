// Many random photos: STRESS=40 flutter test test/omr/omr_stress_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/domain/omr/exam_pattern.dart';
import 'package:phoenix/domain/omr/omr_layout.dart';
import 'package:phoenix/domain/omr/omr_scanner.dart';

import 'synthetic_sheet.dart';

void main() {
  final n = int.tryParse(Platform.environment['STRESS'] ?? '') ?? 0;
  test('random photos', () {
    final layout = OmrLayout.forPattern(bCertPattern);
    var misread = 0, unread = 0, flagged = 0, total = 0;
    for (var i = 0; i < n; i++) {
      final rng = math.Random((int.tryParse(Platform.environment['SEED'] ?? '') ?? 1000) + i);
      final o = PhotoOptions(
        turns: rng.nextInt(4),
        tilt: rng.nextDouble() * 0.07,
        shadow: rng.nextDouble() * 0.6,
        noise: 3 + rng.nextInt(18),
        blur: rng.nextInt(3),
        jpegQuality: 40 + rng.nextInt(50),
        penDarkness: 30 + rng.nextInt(80),
      );
      final marks = <int, List<int>>{
        for (var q = 1; q <= 175; q++)
          if (rng.nextDouble() > 0.08) q: [rng.nextInt(4)],
      };
      final scan = scanOmrImage(photograph(drawSheet(layout, marks, code: i + 1, set: 'A1', o: o, rng: rng), o: o, rng: rng), layout);
      final desc = 'turns ${o.turns} tilt ${o.tilt.toStringAsFixed(3)} shadow ${o.shadow.toStringAsFixed(2)} noise ${o.noise} '
          'blur ${o.blur} jpeg ${o.jpegQuality} ink ${o.penDarkness}';
      if (!scan.ok || scan.sheetCode != i + 1) {
        unread++;
        // ignore: avoid_print
        print('UNREAD #$i $desc · ${scan.problem} code ${scan.sheetCode}');
        continue;
      }
      var bad = 0;
      for (var q = 1; q <= 175; q++) {
        total++;
        if (scan.answers[q] != marks[q]?.single) bad++;
      }
      misread += bad;
      // ignore: avoid_print
      if (bad > 0) print('MISREAD #$i $bad · $desc');
      flagged += scan.flagged.length;
    }
    // ignore: avoid_print
    print('sheets $n · unreadable $unread · answers $total · misread $misread · flagged $flagged');
    expect(misread, 0);
    expect(unread, 0);
  }, skip: n == 0, timeout: const Timeout(Duration(minutes: 20)));
}
