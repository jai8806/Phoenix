import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/omr/exam_pattern.dart';
import '../../domain/omr/omr_layout.dart';

/// A printable OMR answer sheet laid out like the DGNCC sheet, with corner
/// markers, a sheet code and set bubbles for Phoenix's scanner.
Future<Uint8List> buildOmrSheetPdf({
  required ExamPattern pattern,
  required int sheetCode,
  String directorate = 'NCC DTE KAR & GOA',
  String trainingYear = '2026-2027',
  String? testTitle,
}) async {
  final layout = OmrLayout.forPattern(pattern);
  final doc = pw.Document(title: 'OMR sheet ${formatSheetCode(sheetCode)}', author: 'Phoenix');
  final regular = PdfFont.helvetica(doc.document);
  final bold = PdfFont.helveticaBold(doc.document);
  const mm = PdfPageFormat.mm;
  final format = PdfPageFormat.a4;
  final h = format.height;

  doc.addPage(pw.Page(
    pageFormat: format,
    margin: pw.EdgeInsets.zero,
    build: (_) => pw.CustomPaint(
      size: PdfPoint(format.width, h),
      painter: (PdfGraphics g, PdfPoint size) {
        double x(double v) => v * mm;
        double y(double v) => h - v * mm;
        void text(String s, double xMm, double yMm, double pt, {PdfFont? font, String align = 'left', PdfColor color = PdfColors.black}) {
          final f = font ?? regular;
          final w = f.stringMetrics(s).width * pt;
          final dx = align == 'center' ? w / 2 : (align == 'right' ? w : 0);
          g
            ..setFillColor(color)
            ..drawString(f, pt, s, x(xMm) - dx, y(yMm) - pt * 0.35);
        }
        void rect(double l, double t, double r, double b, {double width = 0.6, bool fill = false}) {
          g
            ..setStrokeColor(PdfColors.black)
            ..setLineWidth(width)
            ..drawRect(x(l), y(b), x(r) - x(l), (b - t) * mm);
          fill ? g.fillPath() : g.strokePath();
        }
        void line(double x1, double y1, double x2, double y2, {double width = 0.5}) {
          g
            ..setStrokeColor(PdfColors.black)
            ..setLineWidth(width)
            ..drawLine(x(x1), y(y1), x(x2), y(y2))
            ..strokePath();
        }
        void circle(double cx, double cy, double r, {bool fill = false, double width = 0.45}) {
          g
            ..setStrokeColor(PdfColors.black)
            ..setFillColor(PdfColors.black)
            ..setLineWidth(width)
            ..drawEllipse(x(cx), y(cy), r * mm, r * mm);
          fill ? g.fillPath() : g.strokePath();
        }

        // Corner markers for the scanner.
        for (final f in OmrLayout.fiducials) {
          const s = OmrLayout.fiducialSize;
          rect(f.x - s / 2, f.y - s / 2, f.x + s / 2, f.y + s / 2, fill: true);
        }
        rect(15, 15, 195, 282, width: 0.8);

        // Header, as on the DGNCC sheet.
        text(directorate, 105, 19.5, 11, font: bold, align: 'center');
        text('${pattern.heading} : TRG YEAR $trainingYear', 105, 25, 10, font: bold, align: 'center');
        final marks = pattern.totalMarks.toStringAsFixed(0);
        text('TOTAL MARKS - $marks', 17, 30.5, 8, font: bold);
        text('PLACE :', 17, 34.5, 8, font: bold);
        text('TIME : ${pattern.durationMinutes ~/ 60} HOURS', 193, 30.5, 8, font: bold, align: 'right');
        text('DATE :', 160, 34.5, 8, font: bold);
        text('(Signature of Presiding Officer)', 105, 37.5, 7, font: bold, align: 'center');
        for (var d = 15.0; d < 195; d += 4) {
          line(d, 39.5, d + (d.round() % 8 == 3 ? 1 : 2.4), 39.5, width: 0.9);
        }

        // Regimental number (written by hand).
        rect(17, 42, 92, 70);
        text('REGIMENTAL NUMBER', 54.5, 44.5, 7, font: bold, align: 'center');
        for (var i = 0; i < 16; i++) {
          rect(19 + i * 4.5, 47, 23.2 + i * 4.5, 52, width: 0.4);
        }
        text('Write your regimental number in the boxes,', 54.5, 57, 6, align: 'center');
        text('one character per box.', 54.5, 60.5, 6, align: 'center');
        text(testTitle ?? 'Phoenix mock test', 54.5, 66, 6.5, font: bold, align: 'center');

        // Set.
        rect(95, 42, 117, 62);
        text('SET', 106, 44.5, 7, font: bold, align: 'center');
        for (final e in layout.setBubbles.entries) {
          text(e.key, e.value.x - 4, e.value.y, 7.5, font: bold, align: 'right');
          circle(e.value.x, e.value.y, OmrLayout.bubbleRadius + 0.3);
        }

        // Names.
        rect(120, 42, 195, 62);
        const fields = ['NAME OF UNIT :', 'NAME OF CADET :', 'NAME OF FATHER :', 'NAME OF INSTITUTE :'];
        for (final (i, f) in fields.indexed) {
          final fy = 46.5 + i * 4.6;
          text(f, 122, fy, 6.5, font: bold);
          for (var d = 147.0; d < 193; d += 1.2) {
            line(d, fy + 1, d + 0.4, fy + 1, width: 0.3);
          }
        }

        // Correct and wrong methods.
        rect(95, 64, 140, 73);
        text('CORRECT', 106, 66, 5.5, font: bold, align: 'center');
        text('WRONG METHODS', 128, 66, 5.5, font: bold, align: 'center');
        line(117.5, 64, 117.5, 73, width: 0.4);
        circle(101.5, 70, 1.4);
        circle(105.5, 70, 1.4, fill: true);
        circle(109.5, 70, 1.4);
        for (final (i, kind) in ['x', 'dot', 'tick', 'half'].indexed) {
          final cx = 121.0 + i * 4.8;
          circle(cx, 70, 1.4);
          switch (kind) {
            case 'x':
              line(cx - 1, 69, cx + 1, 71, width: 0.4);
              line(cx - 1, 71, cx + 1, 69, width: 0.4);
            case 'dot':
              circle(cx, 70, 0.45, fill: true);
            case 'tick':
              line(cx - 0.9, 70, cx - 0.2, 70.8, width: 0.4);
              line(cx - 0.2, 70.8, cx + 1, 69.1, width: 0.4);
            case 'half':
              line(cx - 1.2, 70.4, cx + 1.2, 70.4, width: 0.9);
          }
        }
        rect(142, 64, 195, 73);
        line(168.5, 64, 168.5, 73, width: 0.4);
        text('CADET SIGNATURE :', 155, 71.5, 5.5, font: bold, align: 'center');
        text("INVIGILATOR'S SIGN :", 181.75, 71.5, 5.5, font: bold, align: 'center');

        // Sheet code, read by the scanner.
        text('SHEET CODE', 17, 76.5, 5, font: bold);
        final bits = OmrLayout.encodeCode(sheetCode);
        for (final (i, c) in layout.codeCells.indexed) {
          const s = OmrLayout.codeCellSize;
          rect(c.x - s / 2, c.y - s / 2, c.x + s / 2, c.y + s / 2, width: 0.35, fill: bits[i]);
        }
        text('${formatSheetCode(sheetCode)} · scan this sheet in the Phoenix app', 112.5, 76.5, 6.5, font: bold);
        text('Phoenix OMR sheet · do not photocopy at a reduced size', 105, 280.6, 5.5, align: 'center', color: PdfColors.grey700);

        // Answer blocks.
        for (final b in layout.blocks) {
          rect(15, b.top, b.right + 1, b.top + OmrLayout.headerBar, width: 0.7);
          text('${b.title} (${b.marks.toStringAsFixed(0)} MARKS)', (15 + b.right + 1) / 2,
              b.top + OmrLayout.headerBar / 2 + 0.2, 9, font: bold, align: 'center');
          rect(15, b.top, b.right + 1, b.bottom, width: 0.7);
        }
        for (final e in layout.numberAt.entries) {
          text('${e.key}', e.value.x, e.value.y, 7, align: 'right');
        }
        for (final row in layout.bubbles.values) {
          for (final (k, c) in row.indexed) {
            circle(c.x, c.y, OmrLayout.bubbleRadius);
            text(String.fromCharCode(65 + k), c.x, c.y + 0.05, 4.6, align: 'center', color: PdfColors.grey700);
          }
        }

        // Instructions beside the first paper.
        final (il, it, ir, ib) = layout.instructionsBox;
        rect(il, it, ir, ib, width: 0.7);
        text('INSTRUCTIONS :', (il + ir) / 2, it + 3, 7, font: bold, align: 'center');
        final wrong = pattern.marking.wrong;
        final lines = [
          '1. Darken the circle fully with a Black / Blue pen.',
          '2. Do not fold or make stray marks on the sheet.',
          '3. No rough work on the answer sheet.',
          '4. Each correct answer: ${pattern.marking.correct.toStringAsFixed(0)} marks.',
          '5. Each wrong answer: -${wrong == wrong.roundToDouble() ? wrong.toStringAsFixed(0) : wrong} marks.',
          '6. Each question has only one correct answer.',
          '7. More than one answer is treated as wrong.',
          '8. Darken your SET (A1 / A2) above.',
        ];
        final wide = ir - il > 100;
        if (wide) {
          // Two columns of four under the answers.
          for (final (i, s) in lines.indexed) {
            text(s, il + 2 + (i ~/ 4) * (ir - il) / 2, it + 6.5 + (i % 4) * 3.2, 6);
          }
        } else {
          final step = ((ib - it - 6) / lines.length).clamp(2.2, 3.4);
          for (final (i, s) in lines.indexed) {
            text(s, il + 1.5, it + 6.5 + i * step, 5.6);
          }
        }
      },
    ),
  ));
  return doc.save();
}

/// "PHX-01A2F"
String formatSheetCode(int code) => 'PHX-${code.toRadixString(16).toUpperCase().padLeft(4, '0')}';
