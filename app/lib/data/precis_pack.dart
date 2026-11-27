import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/precis_search.dart';

/// Where the downloaded précis passages are kept on the phone, so Ustaad can
/// answer offline. Readable only by this app.
abstract interface class PrecisPackStore {
  Future<List<PrecisPassage>?> load();
  Future<void> save(List<PrecisPassage> passages);
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

  @override
  Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

/// In-memory store for tests and sample mode.
class MemoryPrecisPackStore implements PrecisPackStore {
  List<PrecisPassage>? saved;

  @override
  Future<List<PrecisPassage>?> load() async => saved;

  @override
  Future<void> save(List<PrecisPassage> passages) async => saved = List.of(passages);

  @override
  Future<void> clear() async => saved = null;
}
