import 'package:flutter/material.dart';

/// 与网页端 index.html 中的 CSS 变量保持一致。
class PineColors {
  const PineColors._();

  static const deep = Color(0xFF101513);
  static const dark = Color(0xFF181F1C);
  static const panel = Color(0xFF202824);
  static const raised = Color(0xFF29322E);
  static const ink = Color(0xFFF4F0E6);
  static const paper = Color(0xFFD9D7CE);
  static const muted = Color(0xFF939C96);
  static const tomato = Color(0xFFFF765D);
  static const mint = Color(0xFF79C7A4);
  static const gold = Color(0xFFF0BC62);
  static const line = Color(0x24F4F0E6);
  static const lineStrong = Color(0x45F4F0E6);
}

/// 任务可选配色，取自网页端调色板。
const List<Color> kTaskPalette = [
  PineColors.tomato,
  PineColors.mint,
  PineColors.gold,
  Color(0xFF9FB8D8),
  Color(0xFFC99CC0),
  Color(0xFF8FBFA8),
  Color(0xFFD9A06A),
  Color(0xFFA9AED8),
];

ThemeData buildPineTheme() {
  const ink = PineColors.ink;
  const paper = PineColors.paper;
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: PineColors.deep,
    canvasColor: PineColors.deep,
    colorScheme: const ColorScheme.dark(
      primary: PineColors.tomato,
      onPrimary: PineColors.deep,
      secondary: PineColors.mint,
      onSecondary: PineColors.deep,
      tertiary: PineColors.gold,
      surface: PineColors.dark,
      onSurface: ink,
      error: PineColors.tomato,
      outline: PineColors.line,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: paper, displayColor: ink)
        .copyWith(
          headlineSmall: const TextStyle(
            color: ink,
            fontSize: 24,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          titleLarge: const TextStyle(
            color: ink,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          bodyMedium: const TextStyle(color: paper, fontSize: 14, height: 1.45),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PineColors.deep,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    ),
    cardTheme: const CardThemeData(
      color: PineColors.dark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: PineColors.line),
      ),
    ),
    dividerTheme: const DividerThemeData(color: PineColors.line, thickness: 1),
    listTileTheme: const ListTileThemeData(
      iconColor: PineColors.muted,
      textColor: paper,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PineColors.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PineColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PineColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PineColors.gold),
      ),
      labelStyle: const TextStyle(color: PineColors.muted, fontSize: 13),
      hintStyle: const TextStyle(color: PineColors.muted, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PineColors.tomato,
        foregroundColor: const Color(0xFF141A19),
        minimumSize: const Size.fromHeight(50),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: PineColors.gold),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: PineColors.muted,
        iconSize: 20,
        visualDensity: VisualDensity.compact,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: PineColors.dark,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: PineColors.line),
      ),
      titleTextStyle:
          TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w600),
      contentTextStyle: TextStyle(color: paper, fontSize: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PineColors.dark,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: PineColors.panel,
      contentTextStyle: TextStyle(color: ink, fontSize: 14),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? PineColors.gold
            : PineColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? PineColors.gold.withValues(alpha: 0.35)
            : PineColors.line,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? PineColors.mint
            : Colors.transparent,
      ),
      side: const BorderSide(color: PineColors.lineStrong, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
  );
}
