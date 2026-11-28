
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../domain/omr/exam_pattern.dart';
import '../../domain/omr/omr_layout.dart';
import '../../domain/omr/omr_scanner.dart';

/// What came back from scanning a sheet photo, ready to show and submit.
class ScanOutcome {
  const ScanOutcome({
    required this.answers,
    required this.flags,
    this.setLabel,
    this.sheetCode,
    this.problem,
    this.upload,
  });

  /// Sheet number -> option (0-3), -1 for a double mark, null for blank.
  final Map<int, int?> answers;

  /// Sheet number -> 'faint' | 'unclear' | 'multiple'.
  final Map<int, String> flags;
  final String? setLabel;
  final int? sheetCode;
  final String? problem;

  /// The photo, smaller, to keep as evidence.
  final Uint8List? upload;
}

/// Scans in a background isolate so the phone stays responsive.
Future<ScanOutcome> scanSheet(Uint8List photo, String patternId) => compute(_scan, (photo, patternId));

ScanOutcome _scan((Uint8List, String) args) {
  final (photo, patternId) = args;
  final layout = OmrLayout.forPattern(ExamPattern.byId(patternId));
  final scan = scanOmrImage(photo, layout);
  if (!scan.ok) return ScanOutcome(answers: const {}, flags: const {}, problem: scan.problem);
  // Keep a 1600 px JPEG of the sheet for the ANO to check against.
  Uint8List? upload;
  final decoded = img.decodeImage(photo);
  if (decoded != null) {
    var im = img.bakeOrientation(decoded);
    final long = im.width > im.height ? im.width : im.height;
    if (long > 1600) im = img.copyResize(im, width: (im.width * 1600 / long).round());
    upload = img.encodeJpg(im, quality: 80);
  }
  return ScanOutcome(
    answers: scan.answers,
    flags: {for (final e in scan.reads.entries) if (e.value.flag != null) e.key: e.value.flag!},
    setLabel: scan.setLabel,
    sheetCode: scan.sheetCode,
    upload: upload,
  );
}
