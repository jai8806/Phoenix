import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Extra semantic colours Material's ColorScheme has no slot for.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.success, required this.warning});

  final Color success;
  final Color warning;

  @override
  StatusColors copyWith({Color? success, Color? warning}) =>
      StatusColors(success: success ?? this.success, warning: warning ?? this.warning);

  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    return StatusColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

abstract final class AppTheme {
  static const _headingFamily = 'BarlowCondensed';
  static const _bodyFamily = 'Inter';

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: PhoenixColors.navy700,
    onPrimary: Colors.white,
    primaryContainer: PhoenixColors.navy100,
    onPrimaryContainer: PhoenixColors.navy900,
    secondary: PhoenixColors.sky600,
    onSecondary: Colors.white,
    secondaryContainer: PhoenixColors.sky100,
    onSecondaryContainer: Color(0xFF0B2A45),
    tertiary: PhoenixColors.red600,
    onTertiary: Colors.white,
    tertiaryContainer: PhoenixColors.red100,
    onTertiaryContainer: Color(0xFF4A0410),
    error: Color(0xFFB3261E),
    onError: Colors.white,
    surface: PhoenixColors.lightBg,
    onSurface: PhoenixColors.lightText,
    onSurfaceVariant: PhoenixColors.lightMuted,
    outline: PhoenixColors.lightOutline,
    outlineVariant: PhoenixColors.lightBorder,
    surfaceContainerLowest: PhoenixColors.lightCard,
    surfaceContainerLow: PhoenixColors.lightCard,
    surfaceContainer: Color(0xFFF0F2F6),
    surfaceContainerHigh: Color(0xFFEAEDF3),
    surfaceContainerHighest: Color(0xFFE3E7EE),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF8DB8F2),
    onPrimary: Color(0xFF0B2447),
    primaryContainer: Color(0xFF1E3A66),
    onPrimaryContainer: PhoenixColors.navy100,
    secondary: PhoenixColors.sky300,
    onSecondary: Color(0xFF062B47),
    secondaryContainer: Color(0xFF13446B),
    onSecondaryContainer: PhoenixColors.sky100,
    tertiary: Color(0xFFFF8A95),
    onTertiary: Color(0xFF5C0613),
    tertiaryContainer: Color(0xFF8C1022),
    onTertiaryContainer: PhoenixColors.red100,
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    surface: PhoenixColors.darkBg,
    onSurface: PhoenixColors.darkText,
    onSurfaceVariant: PhoenixColors.darkMuted,
    outline: PhoenixColors.darkOutline,
    outlineVariant: PhoenixColors.darkBorder,
    surfaceContainerLowest: Color(0xFF080E19),
    surfaceContainerLow: PhoenixColors.darkCard,
    surfaceContainer: Color(0xFF152034),
    surfaceContainerHigh: PhoenixColors.darkCardHigh,
    surfaceContainerHighest: Color(0xFF213049),
  );

  static ThemeData get light => _build(_lightScheme,
      const StatusColors(success: PhoenixColors.success, warning: PhoenixColors.warning));

  static ThemeData get dark => _build(_darkScheme,
      const StatusColors(success: PhoenixColors.successDark, warning: PhoenixColors.warningDark));

  static ThemeData _build(ColorScheme scheme, StatusColors status) {
    final base = scheme.brightness == Brightness.light
        ? Typography.material2021().black
        : Typography.material2021().white;
    final body = base.apply(
      fontFamily: _bodyFamily,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle? heading(TextStyle? s, {double? size}) => s?.copyWith(
          fontFamily: _headingFamily,
          fontWeight: FontWeight.w700,
          fontSize: size ?? s.fontSize,
          letterSpacing: 0.2,
          height: 1.15,
        );
    final text = body.copyWith(
      displayLarge: heading(body.displayLarge),
      displayMedium: heading(body.displayMedium),
      displaySmall: heading(body.displaySmall),
      headlineLarge: heading(body.headlineLarge),
      headlineMedium: heading(body.headlineMedium),
      headlineSmall: heading(body.headlineSmall),
      titleLarge: heading(body.titleLarge, size: 24),
      titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: body.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );

    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
      side: BorderSide(color: scheme.outlineVariant),
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      fontFamily: _bodyFamily,
      extensions: [status],
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
        height: 68,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: Space.lg)),
    );
  }
}

extension StatusColorsX on BuildContext {
  StatusColors get status => Theme.of(this).extension<StatusColors>()!;
}
