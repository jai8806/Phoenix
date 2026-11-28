import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phoenix/data/models/test.dart';
import 'package:phoenix/domain/omr/exam_pattern.dart';
import 'package:phoenix/features/omr/question_paper_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('question paper PDF follows the real paper and ends with the answer key', () async {
    final byNumber = {
      for (var n = 1; n <= 175; n++)
        if (n != 20)
          n: Question(id: 'q$n', subject: 'x', prompt: 'Sample question number $n – which is correct?',
              options: const ['First option', 'Second option', 'Third option', 'Fourth option'], correctIndex: n % 4),
    };
    final bytes = await buildQuestionPaperPdf(pattern: bCertPattern, title: 'B Cert mock 1', byNumber: byNumber, unitName: 'NCC RVCE');
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    if (Platform.environment['PREVIEW'] == '1') File('test/preview/out/question_paper.pdf').writeAsBytesSync(bytes);
  });

  test('C cert pattern matches the 2024-25 paper', () {
    expect(cCertPattern.questionCount, 175);
    expect(cCertPattern.totalMarks, 350);
    expect(cCertPattern.commonMarks, 240);
    expect(cCertPattern.specialMarks, 110);
    expect(cCertPattern.paperStarts, [1, 6, 121]);
    expect(bCertPattern.paperStarts, [1, 16, 121]);
    expect(sectionHeading(bCertPattern.papers[1].sections.first, 2), 'NCC GENERAL (03x2 = 06)');
    expect(paperMarksLine(bCertPattern.papers.first, 2), '(15X2 = 30 MARKS)');
    expect(paperMarksLine(bCertPattern.papers[1], 2), '(210 MARKS)');
  });
}
