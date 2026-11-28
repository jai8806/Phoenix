// Renders every picture note for a visual check:
//   PREVIEW=1 flutter test test/preview/visual_notes_preview_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phoenix/core/theme/app_theme.dart';
import 'package:phoenix/features/shared/visual_notes.dart';

Future<void> _font(String family, String path) async {
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

void main() {
  testWidgets('picture notes preview', (tester) async {
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('BarlowCondensed', 'assets/fonts/BarlowCondensed-Bold.ttf');
      await _font('MaterialIcons', '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    });
    final dark = Platform.environment['PREVIEW_DARK'] == '1';
    for (final n in visualNotes) {
      tester.view.physicalSize = const Size(1170, 3600);
      tester.view.devicePixelRatio = 3;
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: VisualNoteCard(n))),
      ));
      await tester.pump();
      if (Platform.environment['PREVIEW'] == '1') {
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/note_${n.id}${dark ? '_dark' : ''}.png'));
      }
    }
    tester.view.reset();
  });
}
