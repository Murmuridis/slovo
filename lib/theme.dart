import 'package:flutter/material.dart';

/// Цвета: пергамент, чернила, киноварь и золото — как в старопечатной книге.
class Palette {
  static const parchment = Color(0xFFF4ECDB);
  static const parchmentDeep = Color(0xFFEBDFC6);
  static const card = Color(0xFFFBF6EA);
  static const ink = Color(0xFF2B2119);
  static const inkSoft = Color(0xFF6B5A48);
  static const cinnabar = Color(0xFF8E2A22);
  static const gold = Color(0xFFB08A3E);

  static const nightBg = Color(0xFF17130F);
  static const nightCard = Color(0xFF231D17);
  static const nightInk = Color(0xFFEDE2CC);
  static const nightInkSoft = Color(0xFFB5A58C);
  static const nightAccent = Color(0xFFD9A35B);
}

const quoteFont = 'OldStandard';
const uiFont = 'PTSerif';

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = dark
      ? const ColorScheme.dark(
          primary: Palette.nightAccent,
          onPrimary: Palette.nightBg,
          secondary: Palette.gold,
          onSecondary: Palette.nightBg,
          surface: Palette.nightCard,
          onSurface: Palette.nightInk,
          surfaceContainerHighest: Color(0xFF2E261F),
          onSurfaceVariant: Palette.nightInkSoft,
          outline: Color(0xFF5E5040),
          error: Color(0xFFE57368),
        )
      : const ColorScheme.light(
          primary: Palette.cinnabar,
          onPrimary: Colors.white,
          secondary: Palette.gold,
          onSecondary: Colors.white,
          surface: Palette.card,
          onSurface: Palette.ink,
          surfaceContainerHighest: Palette.parchmentDeep,
          onSurfaceVariant: Palette.inkSoft,
          outline: Color(0xFFCDBB98),
          error: Color(0xFFB3261E),
        );
  final bg = dark ? Palette.nightBg : Palette.parchment;
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    fontFamily: uiFont,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: quoteFont,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
        letterSpacing: 0.5,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1E1914) : Palette.parchmentDeep,
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontFamily: uiFont, fontSize: 12, color: scheme.onSurface),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: scheme.outline.withValues(alpha: 0.5)),
  );
}
