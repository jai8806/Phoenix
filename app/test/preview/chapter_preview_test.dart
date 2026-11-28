// Renders a real chapter for a visual check:
//   PREVIEW=1 flutter test test/preview/chapter_preview_test.dart --update-goldens
// Needs content/build (not in the
// repo), so it skips itself when that folder is missing.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phoenix/app.dart';
import 'package:phoenix/core/router/app_router.dart';
import 'package:phoenix/data/precis_pack.dart';
import 'package:phoenix/data/providers.dart';
import 'package:phoenix/domain/precis_search.dart';

import '../live_mode_test.dart' show FakeUnitRepo, LiveAuth, cadet, now;

class _RealRepo extends FakeUnitRepo {
  _RealRepo(this.real);
  final List<PrecisPassage> real;
  @override
  Future<List<PrecisPassage>> precisPassages() async => real;
}

Future<void> _font(String family, String path) async {
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

void main() {
  final file = File('../content/build/army_sdsw_oct2025/passages.jsonl');
  testWidgets('chapter preview', (tester) async {
    await tester.runAsync(() async {
      await _font('Inter', 'assets/fonts/Inter.ttf');
      await _font('BarlowCondensed', 'assets/fonts/BarlowCondensed-Bold.ttf');
      await _font('MaterialIcons', '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    });
    final real = <PrecisPassage>[];
    for (final l in file.readAsLinesSync()) {
      final p = jsonDecode(l) as Map<String, dynamic>;
      final pages = (p['book_pages'] as List).cast<int>();
      real.add(PrecisPassage(id: real.length + 1, title: 'Special Subject (Army) SD/SW (Oct 2025)',
          heading: '${p['chapter_code']} · ${p['chapter_title']} · ${p['section']}', content: p['text'] as String,
          page: pages.first, pageEnd: pages.length > 1 ? pages.last : null));
    }
    final dark = Platform.environment['PREVIEW_DARK'] == '1';
    tester.view.physicalSize = const Size(1170, 2532 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(LiveAuth(cadet)),
      initialUserProvider.overrideWithValue(cadet),
      unitRepositoryFactoryProvider.overrideWithValue((_) => _RealRepo(real)),
      clockProvider.overrideWithValue(() => now),
      precisPackStoreProvider.overrideWithValue(MemoryPrecisPackStore()),
    ]);
    addTearDown(c.dispose);
    if (dark) c.read(themeModeProvider.notifier).set(ThemeMode.dark);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const PhoenixApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ustaad'));
    await tester.pumpAndSettle();
    c.read(routerProvider).push(Routes.chapter(Platform.environment['PREVIEW_CODE'] ?? 'MR III',
        book: 'Special Subject (Army) SD/SW (Oct 2025)'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(PhoenixApp), matchesGoldenFile('chapter_preview${dark ? '_dark' : ''}.png'));
  }, skip: !file.existsSync() || Platform.environment['PREVIEW'] != '1');
}
