// Cross-checks the printed sheet against the scanner.
//   dart run tool/omr_check.dart layout            -> bubble positions as JSON
//   dart run tool/omr_check.dart scan photo.jpg    -> what the scanner reads, as JSON
import 'dart:convert';
import 'dart:io';

import 'package:phoenix/domain/omr/exam_pattern.dart';
import 'package:phoenix/domain/omr/omr_layout.dart';
import 'package:phoenix/domain/omr/omr_scanner.dart';

void main(List<String> args) {
  final layout = OmrLayout.forPattern(ExamPattern.byId(args.length > 2 ? args[2] : 'bcert'));
  if (args.first == 'layout') {
    stdout.write(jsonEncode({
      'bubbles': {for (final e in layout.bubbles.entries) '${e.key}': [for (final b in e.value) [b.x, b.y]]},
      'set': {for (final e in layout.setBubbles.entries) e.key: [e.value.x, e.value.y]},
    }));
  } else {
    final sw = Stopwatch()..start();
    final scan = scanOmrImage(File(args[1]).readAsBytesSync(), layout);
    stdout.write(jsonEncode({
      'problem': scan.problem,
      'code': scan.sheetCode,
      'set': scan.setLabel,
      'answers': {for (final e in scan.answers.entries) '${e.key}': e.value},
      'flagged': scan.flagged.toList(),
      'ms': sw.elapsedMilliseconds,
    }));
  }
}
