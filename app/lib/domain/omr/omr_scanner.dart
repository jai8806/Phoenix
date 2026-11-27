import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'omr_layout.dart';

/// How one question was read.
enum MarkState { answered, blank, multiple }

class QuestionRead {
  const QuestionRead(this.state, this.choice, this.darkness, {this.flag});
  final MarkState state;
  final int? choice; // 0..3 when answered
  final List<double> darkness; // per option, 0 (paper) .. 1 (ink)

  /// Why a person should look at it: 'faint', 'unclear' or 'multiple'.
  final String? flag;
}

class OmrScan {
  const OmrScan({required this.reads, this.setLabel, this.sheetCode, this.problem});

  final Map<int, QuestionRead> reads;
  final String? setLabel;
  final int? sheetCode;

  /// Set when the sheet couldn't be read at all, with advice for the cadet.
  final String? problem;

  bool get ok => problem == null;
  Iterable<int> get flagged => reads.entries.where((e) => e.value.flag != null).map((e) => e.key);

  /// Sheet number -> chosen option; null for blank. Multiple marks count as wrong, so they map to -1.
  Map<int, int?> get answers => {
        for (final e in reads.entries)
          e.key: switch (e.value.state) {
            MarkState.answered => e.value.choice,
            MarkState.blank => null,
            MarkState.multiple => -1,
          },
      };
}

/// A grayscale picture as plain bytes, for speed.
class Gray {
  Gray(this.width, this.height, this.data);
  final int width;
  final int height;
  final Uint8List data;

  factory Gray.fromImage(img.Image im) {
    final out = Uint8List(im.width * im.height);
    var i = 0;
    for (final p in im) {
      out[i++] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
    }
    return Gray(im.width, im.height, out);
  }

  int at(int x, int y) => data[y * width + x];

  /// Bilinear sample, 255 (white) outside the picture.
  double sample(double x, double y) {
    if (x < 0 || y < 0 || x >= width - 1 || y >= height - 1) return 255;
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    final a = at(x0, y0), b = at(x0 + 1, y0), c = at(x0, y0 + 1), d = at(x0 + 1, y0 + 1);
    return a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy;
  }
}

/// Maps sheet millimetres to picture pixels.
class Homography {
  Homography(this.m);
  final List<double> m; // 3x3, row-major, m[8] == 1

  (double, double) map(double x, double y) {
    final w = m[6] * x + m[7] * y + m[8];
    return ((m[0] * x + m[1] * y + m[2]) / w, (m[3] * x + m[4] * y + m[5]) / w);
  }

  /// The homography taking each [from] point to the matching [to] point.
  static Homography fromPoints(List<(double, double)> from, List<(double, double)> to) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final (x, y) = from[i];
      final (u, v) = to[i];
      a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }
    // Gauss-Jordan elimination with partial pivoting.
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      final p = a[col][col];
      if (p.abs() < 1e-12) throw StateError('degenerate points');
      for (var c = col; c < 9; c++) {
        a[col][c] /= p;
      }
      for (var r = 0; r < 8; r++) {
        if (r == col) continue;
        final f = a[r][col];
        if (f == 0) continue;
        for (var c = col; c < 9; c++) {
          a[r][c] -= f * a[col][c];
        }
      }
    }
    return Homography([for (var r = 0; r < 8; r++) a[r][8], 1]);
  }
}

class _Blob {
  int count = 0, minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  double sumX = 0, sumY = 0, sumV = 0;
  double get mean => sumV / count;
  double get cx => sumX / count;
  double get cy => sumY / count;
  int get w => maxX - minX + 1;
  int get h => maxY - minY + 1;
}

/// Reads a photo of a Phoenix OMR sheet.
OmrScan scanOmrImage(Uint8List photo, OmrLayout layout) {
  final decoded = img.decodeImage(photo);
  if (decoded == null) return const OmrScan(reads: {}, problem: "That file isn't a picture we can open.");
  var im = img.bakeOrientation(decoded);
  // Work at a fixed resolution: enough for the bubbles, fast on any phone.
  const target = 1600;
  final longSide = math.max(im.width, im.height);
  if (longSide > target) {
    im = img.copyResize(im, width: (im.width * target / longSide).round(), interpolation: img.Interpolation.average);
  }
  return scanGray(Gray.fromImage(im), layout);
}

OmrScan scanGray(Gray g, OmrLayout layout) {
  final corners = _findMarkers(g);
  if (corners == null) {
    return const OmrScan(
      reads: {},
      problem: "Couldn't find the four black corner squares. Lay the sheet flat, fit all four corners in the "
          'photo, and avoid shadows over them.',
    );
  }
  // Try the four ways the sheet could be turned. Turned the right way, every
  // printed bubble outline is where the layout says, and the code checks out.
  const mmCorners = OmrLayout.fiducials;
  Homography? best;
  var bestScore = double.negativeInfinity;
  int? code;
  for (var turn = 0; turn < 4; turn++) {
    final rotated = [for (var i = 0; i < 4; i++) corners[(i + turn) % 4]];
    final h = Homography.fromPoints([for (final c in mmCorners) (c.x, c.y)], rotated);
    final read = _readCode(g, h, layout);
    final score = _outlineScore(g, h, layout) + (read != null ? 0.05 : 0);
    if (score > bestScore) {
      bestScore = score;
      best = h;
      code = read;
    }
  }
  final h = best!;

  final reads = <int, QuestionRead>{};
  for (final e in layout.bubbles.entries) {
    reads[e.key] = _readQuestion(g, h, e.value);
  }
  final set = _readChoice(g, h, layout.setBubbles.values.toList());
  return OmrScan(
    reads: reads,
    sheetCode: code,
    setLabel: set == null ? null : layout.setBubbles.keys.elementAt(set),
  );
}

/// How well the printed bubble outlines line up: darkness on the outline
/// circle minus darkness just outside it, over a sample of bubbles.
double _outlineScore(Gray g, Homography h, OmrLayout layout) {
  var sum = 0.0;
  var n = 0;
  final rows = layout.bubbles.values.toList();
  for (var i = 0; i < rows.length; i += 3) {
    for (final b in [rows[i].first, rows[i].last]) {
      var on = 0.0, off = 0.0;
      for (var k = 0; k < 8; k++) {
        final a = k * math.pi / 4;
        final (x1, y1) = h.map(b.x + math.cos(a) * OmrLayout.bubbleRadius, b.y + math.sin(a) * OmrLayout.bubbleRadius);
        final (x2, y2) = h.map(b.x + math.cos(a) * (OmrLayout.bubbleRadius + 0.9), b.y + math.sin(a) * (OmrLayout.bubbleRadius + 0.9));
        on += g.sample(x1, y1);
        off += g.sample(x2, y2);
      }
      sum += (off - on) / 8 / 255;
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

/// Pixels per millimetre around a sheet point.
double _scaleAt(Homography h, MM p) {
  final (x0, y0) = h.map(p.x, p.y);
  final (x1, y1) = h.map(p.x + 1, p.y);
  final (x2, y2) = h.map(p.x, p.y + 1);
  return (math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2)) + math.sqrt(math.pow(x2 - x0, 2) + math.pow(y2 - y0, 2))) / 2;
}

/// Mean brightness inside a circle of [rMm] around a sheet point.
double _meanDisk(Gray g, Homography h, MM c, double rMm) {
  final (cx, cy) = h.map(c.x, c.y);
  final r = rMm * _scaleAt(h, c);
  var sum = 0.0;
  var n = 0;
  final step = math.max(0.75, r / 6);
  for (var dy = -r; dy <= r; dy += step) {
    for (var dx = -r; dx <= r; dx += step) {
      if (dx * dx + dy * dy > r * r) continue;
      sum += g.sample(cx + dx, cy + dy);
      n++;
    }
  }
  return n == 0 ? 255 : sum / n;
}

/// Brightness of the paper around a sheet point: a high percentile of a
/// small window, so ink and printed letters don't count.
double _paperAround(Gray g, Homography h, MM c, double halfW, double halfH) {
  final values = <double>[];
  for (var y = -halfH; y <= halfH; y += 0.5) {
    for (var x = -halfW; x <= halfW; x += 0.5) {
      final (px, py) = h.map(c.x + x, c.y + y);
      values.add(g.sample(px, py));
    }
  }
  values.sort();
  return math.max(40, values[(values.length * 0.9).floor().clamp(0, values.length - 1)]);
}

QuestionRead _readQuestion(Gray g, Homography h, List<MM> bubbles) {
  final mid = MM((bubbles.first.x + bubbles.last.x) / 2, bubbles.first.y);
  final white = _paperAround(g, h, mid, 9.5, 2.6);
  final d = [
    for (final b in bubbles) (1 - _meanDisk(g, h, b, OmrLayout.bubbleRadius * 0.62) / white).clamp(0.0, 1.0),
  ];
  return decideMarks(d);
}

/// The decision from four darkness values: what was marked, and whether a
/// person should check it.
QuestionRead decideMarks(List<double> d) {
  final sorted = [...d]..sort();
  final base = (sorted[0] + sorted[1]) / 2; // unmarked bubbles (outline and letter)
  final threshold = math.max(0.36, base + 0.24);
  final filled = [for (var i = 0; i < d.length; i++) if (d[i] > threshold) i];
  if (filled.length > 1) return QuestionRead(MarkState.multiple, null, d, flag: 'multiple');
  if (filled.isEmpty) {
    // A light mark: maybe a faint pen, maybe a smudge.
    final top = sorted.last;
    return QuestionRead(MarkState.blank, null, d, flag: top > base + 0.14 ? 'faint' : null);
  }
  final choice = filled.single;
  final others = [for (var i = 0; i < d.length; i++) if (i != choice) d[i]]..sort();
  // A second bubble half filled or rubbed out.
  final unclear = others.last > base + 0.14 || d[choice] < threshold + 0.06;
  return QuestionRead(MarkState.answered, choice, d, flag: unclear ? 'unclear' : null);
}

int? _readChoice(Gray g, Homography h, List<MM> bubbles) {
  final white = _paperAround(g, h, MM(bubbles.first.x + 5, (bubbles.first.y + bubbles.last.y) / 2), 4, 7);
  final d = [for (final b in bubbles) 1 - _meanDisk(g, h, b, OmrLayout.bubbleRadius * 0.62) / white];
  final best = d.indexOf(d.reduce(math.max));
  final other = d.where((x) => x != d[best]).fold(0.0, math.max);
  return d[best] > 0.35 && d[best] - other > 0.2 ? best : null;
}

int? _readCode(Gray g, Homography h, OmrLayout layout) {
  final cells = layout.codeCells;
  final white = _paperAround(g, h, MM(cells[cells.length ~/ 2].x, cells.first.y - 3.2), 40, 0.8);
  final bits = [
    for (final c in cells) (1 - _meanDisk(g, h, c, OmrLayout.codeCellSize * 0.28) / white) > 0.45,
  ];
  return OmrLayout.decodeCode(bits);
}

/// The four corner markers' centres in picture pixels, in clockwise order
/// starting from the one nearest the top-left; null when not found.
List<(double, double)>? findMarkersForTest(Gray g) => _findMarkers(g);

List<(double, double)>? _findMarkers(Gray g) {
  final w = g.width, h = g.height;
  // Integral image for a local mean, so shadows don't hide the markers.
  final integral = Uint32List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0;
    for (var x = 0; x < w; x++) {
      row += g.data[y * w + x];
      integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + row;
    }
  }
  final r = math.max(8, math.min(w, h) ~/ 14);
  final dark = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
      final sum = integral[y1 * (w + 1) + x1] - integral[y0 * (w + 1) + x1] - integral[y1 * (w + 1) + x0] + integral[y0 * (w + 1) + x0];
      final mean = sum / ((x1 - x0) * (y1 - y0));
      final v = g.data[y * w + x];
      if (v < mean * 0.72 && v < 150) dark[y * w + x] = 1;
    }
  }
  // Connected dark regions.
  final label = Int32List(w * h);
  final blobs = <_Blob>[];
  final stack = <int>[];
  for (var start = 0; start < w * h; start++) {
    if (dark[start] == 0 || label[start] != 0) continue;
    final b = _Blob();
    blobs.add(b);
    final id = blobs.length;
    stack
      ..clear()
      ..add(start);
    label[start] = id;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final x = p % w, y = p ~/ w;
      b
        ..count += 1
        ..sumX += x
        ..sumY += y
        ..sumV += g.data[p];
      if (x < b.minX) b.minX = x;
      if (x > b.maxX) b.maxX = x;
      if (y < b.minY) b.minY = y;
      if (y > b.maxY) b.maxY = y;
      if (x > 0 && dark[p - 1] == 1 && label[p - 1] == 0) {
        label[p - 1] = id;
        stack.add(p - 1);
      }
      if (x < w - 1 && dark[p + 1] == 1 && label[p + 1] == 0) {
        label[p + 1] = id;
        stack.add(p + 1);
      }
      if (y > 0 && dark[p - w] == 1 && label[p - w] == 0) {
        label[p - w] = id;
        stack.add(p - w);
      }
      if (y < h - 1 && dark[p + w] == 1 && label[p + w] == 0) {
        label[p + w] = id;
        stack.add(p + w);
      }
    }
  }
  final minSide = math.min(w, h);
  final candidates = blobs.where((b) {
    final side = (b.w + b.h) / 2;
    if (side < minSide * 0.012 || side > minSide * 0.09) return false;
    final aspect = b.w / b.h;
    if (aspect < 0.55 || aspect > 1.8) return false;
    if (b.count / (b.w * b.h) <= 0.62) return false;
    return _onWhitePaper(g, b);
  }).toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  final pool = candidates.take(16).toList();
  if (pool.length < 4) return null;

  // The four markers form the biggest sheet-shaped quadrilateral.
  const sheetAspect = (287 - 10) / (200 - 10); // height / width between marker centres
  double bestScore = -1;
  List<_Blob>? best;
  for (var a = 0; a < pool.length; a++) {
    for (var b = a + 1; b < pool.length; b++) {
      for (var c = b + 1; c < pool.length; c++) {
        for (var d = c + 1; d < pool.length; d++) {
          final quad = _clockwise([pool[a], pool[b], pool[c], pool[d]]);
          final sizes = quad.map((q) => q.count.toDouble()).toList()..sort();
          if (sizes.first < sizes.last * 0.35) continue; // markers are the same size
          final area = _area(quad);
          if (area <= 0) continue;
          final s1 = _dist(quad[0], quad[1]) + _dist(quad[2], quad[3]);
          final s2 = _dist(quad[1], quad[2]) + _dist(quad[3], quad[0]);
          final aspect = math.max(s1, s2) / math.min(s1, s2);
          final aspectFit = math.exp(-math.pow((aspect - sheetAspect) / 0.25, 2));
          // Opposite sides about equal (allowing for perspective).
          final para = math.min(_dist(quad[0], quad[1]), _dist(quad[2], quad[3])) / math.max(_dist(quad[0], quad[1]), _dist(quad[2], quad[3])) *
              math.min(_dist(quad[1], quad[2]), _dist(quad[3], quad[0])) / math.max(_dist(quad[1], quad[2]), _dist(quad[3], quad[0]));
          final score = area * aspectFit * para;
          if (score > bestScore) {
            bestScore = score;
            best = quad;
          }
        }
      }
    }
  }
  if (best == null || bestScore < minSide * minSide * 0.05) return null;
  // Start from the marker nearest the picture's top-left; the sheet code
  // check later fixes a sheet that is turned round.
  var start = 0;
  for (var i = 1; i < 4; i++) {
    if (best[i].cx + best[i].cy < best[start].cx + best[start].cy) start = i;
  }
  return [for (var i = 0; i < 4; i++) (best[(start + i) % 4].cx, best[(start + i) % 4].cy)];
}

/// A corner marker is a solid black square with white paper all round it;
/// a dark bit of table or a shadow is not.
bool _onWhitePaper(Gray g, _Blob b) {
  final pad = ((b.w + b.h) / 2 * 0.55).round();
  final x0 = b.minX - pad, x1 = b.maxX + pad, y0 = b.minY - pad, y1 = b.maxY + pad;
  if (x0 < 0 || y0 < 0 || x1 >= g.width || y1 >= g.height) return false;
  final ring = <int>[];
  final step = math.max(1, (x1 - x0) ~/ 24);
  for (var x = x0; x <= x1; x += step) {
    ring
      ..add(g.at(x, y0))
      ..add(g.at(x, y1));
  }
  for (var y = y0; y <= y1; y += step) {
    ring
      ..add(g.at(x0, y))
      ..add(g.at(x1, y));
  }
  ring.sort();
  final low = ring[(ring.length * 0.1).floor()];
  final median = ring[ring.length ~/ 2];
  return median > b.mean * 2.0 && low > b.mean * 1.6 && median > 90;
}

List<_Blob> _clockwise(List<_Blob> q) {
  final mx = q.fold(0.0, (a, b) => a + b.cx) / 4, my = q.fold(0.0, (a, b) => a + b.cy) / 4;
  return [...q]..sort((a, b) => math.atan2(a.cy - my, a.cx - mx).compareTo(math.atan2(b.cy - my, b.cx - mx)));
}

double _dist(_Blob a, _Blob b) => math.sqrt(math.pow(a.cx - b.cx, 2) + math.pow(a.cy - b.cy, 2));

double _area(List<_Blob> q) {
  var s = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4];
    s += a.cx * b.cy - b.cx * a.cy;
  }
  return s / 2;
}
