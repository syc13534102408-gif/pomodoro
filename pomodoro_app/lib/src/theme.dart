import 'package:flutter/material.dart';

/// 方案 E「松林手帐」设计令牌 v2。
///
/// 只有浅纸一套（D3 定稿）：纸面-卡片明度差 + 柔和投影分层，
/// 阶段色只做语义小面积；主行动墨底纸字（R2）。
class PineColors {
  const PineColors._();

  /// 全局纸面底（scaffold / bottom sheet）
  static const paper = Color(0xFFF6F1E7);

  /// 卡片/便签底（card）
  static const card = Color(0xFFFFFDF8);

  /// 墨色主文字 / 主行动按钮底
  static const ink = Color(0xFF33302A);

  /// 次级文字、未选中、说明
  static const sub = Color(0xFF85796A);

  /// 禁用、空态占位
  static const faint = Color(0xFFC9BFAE);

  /// hairline 分隔 / 轨道 / 1px 描边
  static const line = Color(0xFFE6DECF);

  /// 品牌松绿：Tab 选中、开关开态、勾选、达标/完成章、聚焦边
  static const pine = Color(0xFF4E7A5B);

  /// 专注阶段色 + 危险语义（删除/清空）
  static const focus = Color(0xFFD96B52);

  /// 短休阶段色
  static const mint = Color(0xFF5FAE8B);

  /// 长休阶段色 / 超时 / 「完成」按钮底
  static const gold = Color(0xFFD9A441);

  /// 阶段/语义色派生浅底：`α=.14 叠在纸面`，供段选、选中行、徽章底等使用。
  /// 一律由代码派生，禁止各页手写近似色值。
  static Color tint(Color semantic) =>
      Color.alphaBlend(semantic.withAlpha(36), paper);
}

/// 纸面几何常量。半径/投影/描边统一由这里取值。
class Paper {
  const Paper._();

  /// 不再使用的粗描边占位（纸面卡片默认无描边，靠明度差 + 投影分层）。
  static const cardBorder = 0.0;

  /// 输入框等 1px hairline 描边
  static const chipBorder = 1.0;

  /// 卡片圆角
  static const cardRadius = 20.0;

  /// 控件/输入圆角
  static const chipRadius = 12.0;

  /// 小元件（色条、勾选框、进度、徽章）圆角
  static const tinyRadius = 6.0;

  /// 最细线宽（分隔线等）
  static const hairline = 1.0;

  /// 按压位移（纸面方案不再平移，恒 0；保留字段兼容旧调用）。
  static const offset = 0.0;

  /// 常态投影：柔和浅投影（纸卡浮于纸面）
  static const List<BoxShadow> shadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x1433302A), // ink α0.08
      offset: Offset(0, 3),
      blurRadius: 10,
    ),
  ];

  /// 描边 + 圆角 + 可选投影的通用装饰（默认无描边、20 圆角）。
  static BoxDecoration box({
    Color? color,
    double border = cardBorder,
    double radius = cardRadius,
    bool shadowed = false,
  }) =>
      BoxDecoration(
        color: color ?? PineColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: border > 0
            ? Border.all(color: PineColors.line, width: border)
            : null,
        boxShadow: shadowed ? shadow : null,
      );
}

/// 任务可选配色。8 色，顺序与方案 D 一致（兼容既有 colorIndex 0–7），
/// 仅换为低饱和暖调。
const List<Color> kTaskPalette = [
  Color(0xFFD96B52), // 0
  Color(0xFF5FAE8B), // 1
  Color(0xFFD9A441), // 2
  Color(0xFF7F9CC0), // 3
  Color(0xFFB78FB0), // 4
  Color(0xFF7CBF9D), // 5
  Color(0xFFCE9A64), // 6
  Color(0xFFA3A8CC), // 7
];

/// 计时与数据统一走等宽字形，避免秒数跳动时宽度抖动。
const List<FontFeature> kNumericFont = <FontFeature>[
  FontFeature.tabularFigures(),
];

ThemeData buildPineTheme() {
  const ink = PineColors.ink;
  const line = PineColors.line;
  const mint = PineColors.mint;
  const gold = PineColors.gold;

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: PineColors.paper,
    canvasColor: PineColors.paper,
    colorScheme: const ColorScheme.light(
      primary: PineColors.pine,
      onPrimary: PineColors.card,
      secondary: PineColors.mint,
      onSecondary: PineColors.ink,
      tertiary: PineColors.gold,
      onTertiary: PineColors.ink,
      surface: PineColors.card,
      onSurface: ink,
      error: PineColors.focus,
      onError: PineColors.card,
      outline: line,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
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
          bodyMedium: const TextStyle(color: ink, fontSize: 15, height: 1.5),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PineColors.paper,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    ),
    cardTheme: const CardThemeData(
      color: PineColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Paper.cardRadius)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: line,
      thickness: Paper.hairline,
      space: Paper.hairline,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: PineColors.sub,
      textColor: ink,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PineColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Paper.chipRadius),
        borderSide: const BorderSide(color: line, width: Paper.chipBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Paper.chipRadius),
        borderSide: const BorderSide(color: line, width: Paper.chipBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Paper.chipRadius),
        borderSide: const BorderSide(color: PineColors.pine, width: 1.5),
      ),
      labelStyle: const TextStyle(color: PineColors.sub, fontSize: 13),
      hintStyle: const TextStyle(color: PineColors.sub, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: PineColors.card,
        minimumSize: const Size.fromHeight(46),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: PineColors.card,
        minimumSize: const Size.fromHeight(46),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        side: const BorderSide(color: line, width: Paper.chipBorder),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ink),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: ink,
        iconSize: 20,
        visualDensity: VisualDensity.compact,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: PineColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Paper.cardRadius),
      ),
      titleTextStyle:
          const TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w700),
      contentTextStyle: const TextStyle(color: ink, fontSize: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PineColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: PineColors.card,
      contentTextStyle: TextStyle(color: ink, fontSize: 14),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? PineColors.pine
            : line,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? PineColors.pine
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      side: const BorderSide(color: line, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Paper.tinyRadius),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: PineColors.pine,
      linearTrackColor: PineColors.line,
      linearMinHeight: 6,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: PineColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: Color.alphaBlend(PineColors.pine.withAlpha(36),
          PineColors.card),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? PineColors.pine
              : PineColors.sub,
        ),
      ),
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: PineColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Paper.cardRadius)),
      ),
    ),
    // 阶段/语义色相关主题补充（mint/gold 供个别系统组件使用）。
    extensions: const <ThemeExtension<dynamic>>[
      _SemanticColors(mint: mint, gold: gold),
    ],
  );
}

/// 供系统组件兜底引用的语义色（正文代码请直接用 `PineColors.*`）。
class _SemanticColors extends ThemeExtension<_SemanticColors> {
  const _SemanticColors({required this.mint, required this.gold});

  final Color mint;
  final Color gold;

  @override
  _SemanticColors copyWith({Color? mint, Color? gold}) => _SemanticColors(
        mint: mint ?? this.mint,
        gold: gold ?? this.gold,
      );

  @override
  _SemanticColors lerp(_SemanticColors? other, double t) => _SemanticColors(
        mint: Color.lerp(mint, other?.mint ?? mint, t)!,
        gold: Color.lerp(gold, other?.gold ?? gold, t)!,
      );
}
