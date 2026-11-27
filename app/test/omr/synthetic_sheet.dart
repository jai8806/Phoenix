// Draws filled-in Phoenix OMR sheets and "photographs" them, for testing the
// scanner without a camera.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:phoenix/domain/omr/omr_layout.dart';
import 'package:phoenix/domain/omr/omr_scanner.dart';

/// What the cadet marked: question -> options filled (empty = blank).
typedef Marks = Map<int, List<int>>;

class PhotoOptions {
  const PhotoOptions({
    this.turns = 0,
    this.tilt = 0.05,
    this.shadow = 0.35,
    this.noise = 10,
    this.blur = 1,
    this.jpegQuality = 72,
    this.penDarkness = 55,
    this.faint = const {},
  });

  final int turns; // quarter turns of the sheet in the photo
  final double tilt; // perspective strength
  final double shadow; // 0 none .. 1 strong gradient
  final int noise;
  final int blur;
  final int jpegQuality;
  final int penDarkness; // ink brightness, 0 black .. 255 white

  /// Questions marked with a weak, half-hearted fill.
  final Set<int> faint;
}

const _ppm = 8.0; // pixels per millimetre for the flat sheet

img.Image drawSheet(OmrLayout layout, Marks marks, {required int code, String? set, PhotoOptions o = const PhotoOptions(), math.Random? rng}) {
  rng ??= math.Random(1);
  final w = (OmrLayout.pageWidth * _ppm).round(), h = (OmrLayout.pageHeight * _ppm).round();
  final sheet = img.Image(width: w, height: h)..clear(img.ColorRgb8(250, 250, 246));
  int p(double mm) => (mm * _ppm).round();
  final black = img.ColorRgb8(15, 15, 15);
  for (final f in OmrLayout.fiducials) {
    const s = OmrLayout.fiducialSize / 2;
    img.fillRect(sheet, x1: p(f.x - s), y1: p(f.y - s), x2: p(f.x + s), y2: p(f.y + s), color: black);
  }
  // Some printed text in the header, as distraction.
  for (var i = 0; i < 40; i++) {
    img.fillRect(sheet, x1: p(30 + i * 3.6), y1: p(18), x2: p(32 + i * 3.6), y2: p(21), color: black);
  }
  void bubble(MM c, {bool filled = false, bool weak = false}) {
    img.drawCircle(sheet, x: p(c.x), y: p(c.y), radius: p(OmrLayout.bubbleRadius), color: img.ColorRgb8(40, 40, 40));
    // The printed letter inside.
    img.fillRect(sheet, x1: p(c.x - 0.45), y1: p(c.y - 0.6), x2: p(c.x + 0.45), y2: p(c.y + 0.6), color: img.ColorRgb8(120, 120, 120));
    if (filled) {
      final ink = weak ? 172 : o.penDarkness; // light pencil
      final r = OmrLayout.bubbleRadius * (weak ? 0.8 : 0.85 + rng!.nextDouble() * 0.25);
      final dx = (rng!.nextDouble() - 0.5) * 0.5, dy = (rng.nextDouble() - 0.5) * 0.5;
      img.fillCircle(sheet, x: p(c.x + dx), y: p(c.y + dy), radius: p(r), color: img.ColorRgb8(ink, ink, ink + 25));
    }
  }
  for (final e in layout.bubbles.entries) {
    final chosen = marks[e.key] ?? const [];
    for (final (k, c) in e.value.indexed) {
      bubble(c, filled: chosen.contains(k), weak: o.faint.contains(e.key) && chosen.contains(k));
    }
  }
  for (final e in layout.setBubbles.entries) {
    bubble(e.value, filled: e.key == set);
  }
  final bits = OmrLayout.encodeCode(code);
  for (final (i, c) in layout.codeCells.indexed) {
    const s = OmrLayout.codeCellSize / 2;
    if (bits[i]) {
      img.fillRect(sheet, x1: p(c.x - s), y1: p(c.y - s), x2: p(c.x + s), y2: p(c.y + s), color: black);
    } else {
      img.drawRect(sheet, x1: p(c.x - s), y1: p(c.y - s), x2: p(c.x + s), y2: p(c.y + s), color: black);
    }
  }
  return sheet;
}

/// The sheet as a phone photo: on a table, in perspective, maybe turned,
/// with a shadow, blur, noise and JPEG compression.
Uint8List photograph(img.Image sheet, {PhotoOptions o = const PhotoOptions(), math.Random? rng}) {
  rng ??= math.Random(2);
  final portrait = o.turns.isEven;
  final outW = portrait ? 1500 : 2000, outH = portrait ? 2000 : 1500;
  // Where the sheet's corners land in the photo, with some perspective.
  double jitter(double s) => (rng!.nextDouble() - 0.5) * 2 * s;
  final m = 0.08;
  final t = o.tilt;
  var corners = <(double, double)>[
    (outW * (m + jitter(t)), outH * (m + jitter(t))),
    (outW * (1 - m + jitter(t)), outH * (m + jitter(t))),
    (outW * (1 - m + jitter(t)), outH * (1 - m + jitter(t))),
    (outW * (m + jitter(t)), outH * (1 - m + jitter(t))),
  ];
  // A turned sheet: its top-left corner lands elsewhere.
  corners = [for (var i = 0; i < 4; i++) corners[(i + o.turns) % 4]];
  final sw = sheet.width.toDouble(), sh = sheet.height.toDouble();
  final toSheet = Homography.fromPoints(corners, [(0, 0), (sw, 0), (sw, sh), (0, sh)]);
  final out = img.Image(width: outW, height: outH);
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final (sx, sy) = toSheet.map(x.toDouble(), y.toDouble());
      double v;
      if (sx < 0 || sy < 0 || sx >= sw - 1 || sy >= sh - 1) {
        v = 95 + ((x ~/ 40 + y ~/ 40).isEven ? 10 : 0); // table
      } else {
        v = sheet.getPixel(sx.toInt(), sy.toInt()).r.toDouble();
      }
      // Light falls off towards one corner.
      final light = 1 - o.shadow * (x / outW * 0.6 + y / outH * 0.4);
      v = v * light + (rng.nextDouble() - 0.5) * 2 * o.noise;
      final c = v.clamp(0, 255).toInt();
      out.setPixelRgb(x, y, c, c, c);
    }
  }
  final blurred = o.blur > 0 ? img.gaussianBlur(out, radius: o.blur) : out;
  return img.encodeJpg(blurred, quality: o.jpegQuality);
}
