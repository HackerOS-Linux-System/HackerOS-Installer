import 'package:flutter/material.dart';

class AppTheme {
  // ── Kolory ──────────────────────────────────────────────────────────────────
  static const Color bgDeep          = Color(0xFF070A10);
  static const Color bgBase          = Color(0xFF0C1018);
  static const Color surface         = Color(0xFF131926);
  static const Color surfaceElevated = Color(0xFF1A2233);
  static const Color surfaceBorder   = Color(0xFF212D40);
  static const Color surfaceHover    = Color(0xFF1E2A3A);

  static const Color accent          = Color(0xFF3D8EF5);
  static const Color accentSecondary = Color(0xFF7B5CF6);
  static const Color accentGaming    = Color(0xFFFF6B35);
  static const Color accentSuccess   = Color(0xFF2ECC8A);
  static const Color accentWarning   = Color(0xFFF59E0B);
  static const Color accentDanger    = Color(0xFFEF4444);
  static const Color accentOfficial  = Color(0xFF3B82F6);

  static const Color textPrimary     = Color(0xFFE2E8F4);
  static const Color textSecondary   = Color(0xFF8896AA);
  static const Color textMuted       = Color(0xFF4A5568);

  // ── ThemeData ────────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgBase,
    fontFamily: 'Sora',
    colorScheme: const ColorScheme.dark(
      primary:      accent,
      secondary:    accentSecondary,
      surface:      surface,
      error:        accentDanger,
      onPrimary:    Colors.white,
      onSecondary:  Colors.white,
      onSurface:    textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bgBase,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Sora', fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
      iconTheme: IconThemeData(color: textPrimary),
    ),
    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontFamily: 'Sora', fontSize: 44, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -1.5),
      displayMedium: TextStyle(fontFamily: 'Sora', fontSize: 34, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -1.0),
      headlineLarge: TextStyle(fontFamily: 'Sora', fontSize: 26, fontWeight: FontWeight.w600, color: textPrimary),
      headlineMedium:TextStyle(fontFamily: 'Sora', fontSize: 21, fontWeight: FontWeight.w600, color: textPrimary),
      titleLarge:    TextStyle(fontFamily: 'Sora', fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
      titleMedium:   TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
      bodyLarge:     TextStyle(fontFamily: 'Sora', fontSize: 14, color: textSecondary, height: 1.6),
      bodyMedium:    TextStyle(fontFamily: 'Sora', fontSize: 13, color: textSecondary, height: 1.5),
      labelLarge:    TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: 0.2),
      labelMedium:   TextStyle(fontFamily: 'Sora', fontSize: 11, fontWeight: FontWeight.w500, color: textSecondary, letterSpacing: 0.5),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
          disabledBackgroundColor: surfaceElevated,
          disabledForegroundColor: textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
          side: const BorderSide(color: surfaceBorder, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: surfaceBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: surfaceBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: accent, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: accentDanger)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: const TextStyle(fontFamily: 'Sora', color: textSecondary, fontSize: 13),
      hintStyle: const TextStyle(fontFamily: 'Sora', color: textMuted, fontSize: 13),
    ),
    cardTheme: CardTheme(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: surfaceBorder),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(color: surfaceBorder, thickness: 1, space: 0),
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
      textColor: textPrimary,
      iconColor: textSecondary,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : textMuted,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : Colors.transparent,
      ),
      side: const BorderSide(color: textMuted, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : surfaceElevated,
      ),
    ),
  );
}

// ─── Gradienty ────────────────────────────────────────────────────────────────

class AppGradients {
  static const LinearGradient accent = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [AppTheme.accent, AppTheme.accentSecondary],
  );
  static const LinearGradient gaming = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B35), Color(0xFFFF1493)],
  );
  static const LinearGradient official = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
  );
  static const LinearGradient success = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF2ECC8A), Color(0xFF059669)],
  );
  static const LinearGradient bgDark = LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [AppTheme.bgDeep, AppTheme.bgBase],
  );

  static LinearGradient forEdition(String edition) =>
  edition == 'gaming' ? gaming : official;
}
