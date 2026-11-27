/// A figure from the précis (map, sign, badge, diagram), stored privately.
class PrecisFigure {
  const PrecisFigure({
    required this.id,
    required this.title,
    required this.chapterCode,
    required this.path,
    this.page,
    this.width,
    this.height,
  });

  final String id;
  final String title;
  final String chapterCode;

  /// Path inside the private precis-figures bucket.
  final String path;
  final int? page;
  final int? width;
  final int? height;

  double get aspect => (width ?? 4) / (height ?? 3);

  Map<String, dynamic> toJson() =>
      {'id': id, 't': title, 'c': chapterCode, 'p': page, 'path': path, 'w': width, 'h': height};

  factory PrecisFigure.fromJson(Map<String, dynamic> j) => PrecisFigure(
        id: j['id'] as String,
        title: j['t'] as String? ?? '',
        chapterCode: j['c'] as String,
        path: j['path'] as String,
        page: (j['p'] as num?)?.toInt(),
        width: (j['w'] as num?)?.toInt(),
        height: (j['h'] as num?)?.toInt(),
      );
}
