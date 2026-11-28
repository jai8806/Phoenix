import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/test.dart';
import '../../domain/omr/exam_pattern.dart';

/// The question paper laid out like the real certificate paper: the same
/// header, papers, section headings and numbering. With [answerKey], a key
/// page follows (for cross-checking a draft); [draft] stamps every page.
Future<Uint8List> buildQuestionPaperPdf({
  required ExamPattern pattern,
  required String title,
  required Map<int, Question> byNumber,
  String? unitName,
  DateTime? date,
  bool answerKey = true,
  bool draft = true,
}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: regular));
  const small = 8.5;
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5);
  final year = (date ?? DateTime.now()).year;
  const letters = ['A', 'B', 'C', 'D'];

  pw.Widget header() => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Center(child: pw.Text(pattern.directorate, style: bold.copyWith(fontSize: 12))),
        pw.Center(child: pw.Text('${pattern.heading} – $year', style: bold.copyWith(fontSize: 12))),
        pw.Center(child: pw.Text(pattern.candidates, style: bold)),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text(title, style: const pw.TextStyle(fontSize: 10))),
        pw.SizedBox(height: 8),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Centre: ______________________________'),
          pw.Text('Common subject: ${fmtNum(pattern.commonMarks)} Marks'),
        ]),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Unit: ${unitName ?? '______________________________'}'),
          pw.Text('Special Subject: ${fmtNum(pattern.specialMarks)} Marks'),
        ]),
        pw.Text('Total Marks: ${fmtNum(pattern.totalMarks)} Marks'),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Pass Marks: ${fmtNum(pattern.passPercent)}% in each paper'),
          pw.Text('Time allotted: ${pattern.durationMinutes ~/ 60} Hrs'),
        ]),
        pw.SizedBox(height: 6),
        pw.Text('General Instructions:', style: bold),
        for (final (i, line) in pattern.instructions.indexed) pw.Text('${i + 1}. $line'),
        pw.SizedBox(height: 4),
        pw.Divider(),
      ]);

  pw.Widget question(int n, Question? q) {
    if (q == null) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text('$n.  [No question yet]', style: pw.TextStyle(color: PdfColors.red700)),
      );
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 24, child: pw.Text('$n.', style: bold.copyWith(fontSize: 10))),
          pw.Expanded(child: pw.Text(q.prompt)),
        ]),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 24, top: 2),
          child: pw.Wrap(spacing: 14, runSpacing: 2, children: [
            for (final (i, o) in q.options.indexed)
              pw.SizedBox(width: 230, child: pw.Text('${letters[i]}) $o')),
          ]),
        ),
      ]),
    );
  }

  final body = <pw.Widget>[header()];
  var n = 1;
  for (final paper in pattern.papers) {
    body.add(pw.SizedBox(height: 8));
    body.add(pw.Center(child: pw.Text(paper.title, style: bold.copyWith(fontSize: 12))));
    body.add(pw.Center(child: pw.Text(paperMarksLine(paper, pattern.marking.correct), style: bold)));
    for (final s in paper.sections) {
      if (paper.sections.length > 1) {
        body.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
          child: pw.Text(sectionHeading(s, pattern.marking.correct), style: bold),
        ));
      } else {
        body.add(pw.SizedBox(height: 6));
      }
      for (var i = 0; i < s.count; i++) {
        body.add(question(n, byNumber[n]));
        n++;
      }
    }
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    theme: pw.ThemeData.withFont(base: regular, bold: regular).copyWith(defaultTextStyle: pw.TextStyle(font: regular, fontSize: 9.5)),
    header: draft
        ? (_) => pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('DRAFT – FOR CROSS-CHECKING · NOT FOR CADETS',
                  style: pw.TextStyle(color: PdfColors.red700, fontSize: small)),
            )
        : null,
    footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Mock paper made in Phoenix · ${pattern.basedOn} pattern', style: const pw.TextStyle(fontSize: 7)),
      pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: small)),
    ]),
    build: (_) => body,
  ));

  if (answerKey) {
    final cells = <pw.Widget>[];
    for (var k = 1; k <= pattern.questionCount; k++) {
      final q = byNumber[k];
      cells.add(pw.Container(
        width: 62,
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text('$k – ${q == null ? '?' : letters[q.correctIndex]}', style: const pw.TextStyle(fontSize: 9)),
      ));
    }
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: pw.ThemeData.withFont(base: regular, bold: regular),
      build: (_) => [
        pw.Text('ANSWER KEY · $title', style: bold.copyWith(fontSize: 13)),
        pw.Text('${pattern.name} pattern · generated ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: small)),
        pw.SizedBox(height: 10),
        pw.Wrap(children: cells),
      ],
    ));
  }
  return doc.save();
}
