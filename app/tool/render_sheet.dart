// Writes sample OMR sheets for a visual check:  dart run tool/render_sheet.dart out_dir
import 'dart:io';

import 'package:phoenix/domain/omr/exam_pattern.dart';
import 'package:phoenix/features/omr/omr_sheet_pdf.dart';

Future<void> main(List<String> args) async {
  final out = args.isEmpty ? '.' : args.first;
  for (final p in [bCertPattern, cCertPattern]) {
    final bytes = await buildOmrSheetPdf(pattern: p, sheetCode: 0xA2F3, testTitle: 'Mock 1 · ${p.name}');
    File('$out/omr_${p.id}.pdf').writeAsBytesSync(bytes);
  }
}
