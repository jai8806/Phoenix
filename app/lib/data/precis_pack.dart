import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/precis_search.dart';
import 'models/figure.dart';

/// Where the downloaded précis passages are kept on the phone, so Ustaad can
/// answer offline. Readable only by this app.
abstract interface class PrecisPackStore {
  Future<List<PrecisPassage>?> load();
  Future<void> save(List<PrecisPassage> passages);
  Future<List<PrecisFigure>> loadFigures();
  Future<void> saveFigures(List<PrecisFigure> figures);
  Future<void> clear();
}

class FilePrecisPackStore implements PrecisPackStore {
  Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/precis_pack.json');

  @override
  Future<List<PrecisPassage>?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return [for (final p in data['passages'] as List) PrecisPassage.fromJson(p as Map<String, dynamic>)];
    } catch (_) {
      return null; // a corrupt pack is simply downloaded again
    }
  }

  @override
  Future<void> save(List<PrecisPassage> passages) async {
    final f = await _file();
    await f.writeAsString(jsonEncode({
      'saved_at': DateTime.now().toIso8601String(),
      'passages': [for (final p in passages) p.toJson()],
    }));
  }

  Future<File> _figuresFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/precis_figures.json');

  @override
  Future<List<PrecisFigure>> loadFigures() async {
    try {
      final f = await _figuresFile();
      if (!await f.exists()) return const [];
      return [for (final j in jsonDecode(await f.readAsString()) as List) PrecisFigure.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveFigures(List<PrecisFigure> figures) async =>
      (await _figuresFile()).writeAsString(jsonEncode([for (final f in figures) f.toJson()]));

  @override
  Future<void> clear() async {
    for (final f in [await _file(), await _figuresFile()]) {
      if (await f.exists()) await f.delete();
    }
  }
}

/// In-memory store for tests and sample mode.
class MemoryPrecisPackStore implements PrecisPackStore {
  List<PrecisPassage>? saved;
  List<PrecisFigure> savedFigures = const [];

  @override
  Future<List<PrecisFigure>> loadFigures() async => savedFigures;

  @override
  Future<void> saveFigures(List<PrecisFigure> figures) async => savedFigures = List.of(figures);

  @override
  Future<List<PrecisPassage>?> load() async => saved;

  @override
  Future<void> save(List<PrecisPassage> passages) async => saved = List.of(passages);

  @override
  Future<void> clear() async {
    saved = null;
    savedFigures = const [];
  }
}
