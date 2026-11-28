// Measures Ustaad's offline answers against a question set.
//
//   cd app && dart run tool/eval_ustaad.dart ../content/build ../tools/eval/ustaad_questions.json [-v]
//
// Loads every content/build/*/passages.jsonl the way the app receives them,
// asks each question, and checks the answer for the words a correct answer
// must contain ("any": one of them; "all": each, "a|b" meaning either).
import 'dart:convert';
import 'dart:io';

import 'package:phoenix/domain/precis_search.dart';
import 'package:phoenix/domain/quick_facts.dart';

Future<void> main(List<String> args) async {
  final buildDir = Directory(args[0]);
  final questions = (jsonDecode(File(args[1]).readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final verbose = args.contains('-v');

  final passages = <PrecisPassage>[];
  for (final dir in buildDir.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path))) {
    final f = File('${dir.path}/passages.jsonl');
    if (!f.existsSync()) continue;
    for (final line in f.readAsLinesSync()) {
      final p = jsonDecode(line) as Map<String, dynamic>;
      final pages = (p['book_pages'] as List).cast<int>();
      passages.add(PrecisPassage(
        id: passages.length + 1,
        title: p['edition'] != null && p['edition'] != '' ? '${p['title']} (${p['edition']})' : p['title'] as String,
        heading: '${p['chapter_code']} · ${p['chapter_title']} · ${p['section']}',
        content: p['text'] as String,
        page: pages.isEmpty ? null : pages.first,
        pageEnd: pages.length > 1 ? pages.last : null,
      ));
    }
  }
  final search = PrecisSearch(passages);
  final export = args.firstWhere((a) => a.startsWith('--export='), orElse: () => '');
  if (export.isNotEmpty) {
    // What the app sends the AI for each question, for tools/eval/ai_eval.py.
    final out = File(export.substring(9)).openWrite();
    for (final item in questions) {
      final q = item['q'] as String;
      final fact = quickFactFor(q);
      out.writeln(jsonEncode({
        ...item,
        'fact': fact?.answer,
        'passages': [
          for (final p in search.retrieve(q, k: 8))
            {'title': p.title, 'heading': p.heading, 'page': p.page, 'page_end': p.pageEnd, 'content': p.content},
        ],
      }));
    }
    await out.close();
    return;
  }
  final k = int.tryParse(args.firstWhere((a) => a.startsWith('--k='), orElse: () => '--k=0').substring(4)) ?? 0;
  if (k > 0) {
    // Retrieval recall: is the answer anywhere in the top k passages (plus any quick fact)?
    var hit = 0;
    for (final item in questions) {
      final q = item['q'] as String;
      final fact = quickFactFor(q);
      final text = [if (fact != null) fact.answer, for (final p in search.retrieve(q, k: k)) p.content].join(' ').toLowerCase();
      bool has(String alt) => alt.split('|').any(text.contains);
      final ok = item['any'] != null ? (item['any'] as List).cast<String>().any(has) : (item['all'] as List).cast<String>().every(has);
      if (ok) hit++;
      if (!ok || verbose) stdout.writeln('${ok ? 'HIT ' : 'MISS'}  $q');
    }
    stdout.writeln('\nanswer in top $k passages: $hit / ${questions.length}');
    return;
  }
  final sw = Stopwatch()..start();
  var pass = 0;
  for (final item in questions) {
    final q = item['q'] as String;
    final ans = askUstaad(q, search);
    final text = ans.displayText.toLowerCase();
    bool has(String alt) => alt.split('|').any(text.contains);
    final ok = item['any'] != null
        ? (item['any'] as List).cast<String>().any(has)
        : (item['all'] as List).cast<String>().every(has);
    if (ok) pass++;
    if (!ok || verbose) {
      stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $q');
      stdout.writeln('      ${ans.displayText.replaceAll('\n', ' / ').substring(0, ans.displayText.length.clamp(0, 260))}');
      stdout.writeln('      ${ans.source}');
    }
  }
  stdout.writeln('\n$pass / ${questions.length} correct · ${passages.length} passages · '
      '${(sw.elapsedMilliseconds / questions.length).toStringAsFixed(1)} ms per question');
}
