import 'exam_pattern.dart';

/// A point on the sheet in millimetres, origin at the top-left of A4.
class MM {
  const MM(this.x, this.y);
  final double x;
  final double y;
  @override
  String toString() => '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

class PaperBlock {
  const PaperBlock({required this.title, required this.marks, required this.top, required this.bottom, required this.right});
  final String title;
  final double marks;
  final double top; // header bar top
  final double bottom;
  final double right; // block's right edge (Paper II leaves room for instructions)
}

/// Where everything is on a Phoenix OMR sheet. The printed sheet and the
/// scanner both use this, so they always agree.
class OmrLayout {
  OmrLayout._(this.pattern);

  static const pageWidth = 210.0;
  static const pageHeight = 297.0;
  static const fiducialSize = 7.0;
  static const bubbleRadius = 1.75;
  static const codeBits = 24;
  static const codeCellSize = 2.8;

  /// Corner markers' centres: top-left, top-right, bottom-right, bottom-left.
  static const fiducials = [MM(10, 10), MM(200, 10), MM(200, 287), MM(10, 287)];

  final ExamPattern pattern;

  /// Question number -> centres of its A, B, C, D bubbles.
  final Map<int, List<MM>> bubbles = {};

  /// Question number -> where its number is printed (right-aligned at x).
  final Map<int, MM> numberAt = {};

  /// Set bubbles: 'A1', 'A2'.
  final Map<String, MM> setBubbles = {};

  /// Cells of the sheet code, most significant bit first.
  final List<MM> codeCells = [];

  final List<PaperBlock> blocks = [];

  /// Instructions box beside the first paper.
  late final (double, double, double, double) instructionsBox; // left, top, right, bottom

  static const left = 16.0;
  static const right = 194.0;
  static const answersTop = 84.0;
  static const answersBottom = 276.0;
  static const headerBar = 6.5;
  static const blockGap = 2.5;

  factory OmrLayout.forPattern(ExamPattern pattern) {
    final l = OmrLayout._(pattern);
    // Info block: set bubbles and the sheet code.
    l.setBubbles['A1'] = const MM(107, 48);
    l.setBubbles['A2'] = const MM(107, 56);
    for (var i = 0; i < codeBits; i++) {
      l.codeCells.add(MM(30 + i * 3.3, 76.5));
    }

    // Columns and rows for each paper.
    final layouts = <(int cols, int rows)>[];
    for (final (i, p) in pattern.papers.indexed) {
      final cols = i == 0 && p.count <= 15 ? 5 : 8;
      layouts.add((cols, (p.count / cols).ceil()));
    }
    final rows = layouts.fold(0, (a, c) => a + c.$2);
    final fixed = pattern.papers.length * (headerBar + blockGap + 2);
    final pitch = ((answersBottom - answersTop - fixed) / rows).clamp(5.6, 7.0);

    var y = answersTop;
    var number = 1;
    for (final (i, p) in pattern.papers.indexed) {
      final (cols, rowCount) = layouts[i];
      final blockRight = cols == 5 ? 134.0 : right;
      final top = y;
      y += headerBar + 2 + pitch / 2;
      final colWidth = (blockRight - left) / cols;
      for (var c = 0; c < cols; c++) {
        for (var r = 0; r < rowCount; r++) {
          final n = number + c * rowCount + r;
          if (n >= number + p.count) continue;
          final x0 = left + c * colWidth;
          final cy = y + r * pitch;
          l.numberAt[n] = MM(x0 + 5.6, cy);
          l.bubbles[n] = [for (var k = 0; k < 4; k++) MM(x0 + 8.6 + k * 3.85, cy)];
        }
      }
      y += rowCount * pitch - pitch / 2 + blockGap;
      l.blocks.add(PaperBlock(
        title: p.title,
        marks: p.count * pattern.marking.correct,
        top: top,
        bottom: y,
        right: blockRight,
      ));
      if (i == 0 && cols == 5) l.instructionsBox = (blockRight + 2, top, right + 1, y);
      number += p.count;
    }
    // No room beside the first paper: instructions go under the last one.
    if (layouts.first.$1 != 5) l.instructionsBox = (15, y + 1.5, right + 1, 278.5);
    return l;
  }

  /// Largest sheet code.
  static const maxCode = (1 << 16) - 1;

  /// The 24 bits printed for [code] (16-bit code + 8-bit check), MSB first.
  static List<bool> encodeCode(int code) {
    assert(code >= 0 && code <= maxCode);
    final value = (code << 8) | _check(code);
    return [for (var i = codeBits - 1; i >= 0; i--) (value >> i) & 1 == 1];
  }

  /// The code read back from [bits], or null when the check digit doesn't match.
  static int? decodeCode(List<bool> bits) {
    if (bits.length != codeBits) return null;
    var value = 0;
    for (final b in bits) {
      value = (value << 1) | (b ? 1 : 0);
    }
    final code = value >> 8;
    return (value & 0xFF) == _check(code) ? code : null;
  }

  /// CRC-8 (polynomial 0x07) of the two code bytes.
  static int _check(int code) {
    var crc = 0x5A;
    for (final byte in [code >> 8, code & 0xFF]) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) & 0xFF : (crc << 1) & 0xFF;
      }
    }
    return crc;
  }
}
