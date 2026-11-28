import 'package:material_ui/material_ui.dart';

/// Design tokens. The palette comes from the NCC flag: red (Army),
/// dark blue (Navy) and light blue (Air Force), laid over calm neutrals so
/// the colour carries meaning instead of decoration.
abstract final class PhoenixColors {
  // Brand
  static const navy900 = Color(0xFF0E1B33);
  static const navy700 = Color(0xFF1B3A6B);
  static const navy100 = Color(0xFFD8E3F6);
  static const sky600 = Color(0xFF2F7FC1);
  static const sky300 = Color(0xFF6CB4EE);
  static const sky100 = Color(0xFFDCEEFB);
  static const red600 = Color(0xFFC8102E);
  static const red100 = Color(0xFFFADADD);

  // Status
  static const success = Color(0xFF1E8E5A);
  static const successDark = Color(0xFF5FD39A);
  static const warning = Color(0xFFB7791F);
  static const warningDark = Color(0xFFF2C14E);

  // Light neutrals
  static const lightBg = Color(0xFFF6F7FA);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightText = navy900;
  static const lightMuted = Color(0xFF4A5568);
  static const lightBorder = Color(0xFFE2E6EE);
  static const lightOutline = Color(0xFFC7CDD8);

  // Dark neutrals
  static const darkBg = Color(0xFF0B1220);
  static const darkCard = Color(0xFF121B2D);
  static const darkCardHigh = Color(0xFF1A263C);
  static const darkText = Color(0xFFE6EAF2);
  static const darkMuted = Color(0xFFA3ADBF);
  static const darkBorder = Color(0xFF263042);
  static const darkOutline = Color(0xFF3A4558);
}

/// 4/8 pt spacing scale.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

/// Breakpoint where the Command Center switches from a drawer to a side rail.
const double wideLayoutBreakpoint = 840;

/// Content never stretches wider than this on big screens.
const double maxContentWidth = 960;
