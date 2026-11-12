import 'package:flutter/material.dart';

/// V3「Claude 素纸书房 · 檀褐 Rosewood」设计令牌（2026-11-12 定稿）。
///
/// 权威来源：`outputs/redesign-v3-2026-11-12/01-claude-studio.html` 与
/// `design-spec-v3.md`。**页面代码禁止出现十六进制色值**，一律走这里。
///
/// 兼容约定：下方「旧名兼容」段保留了 v1.3.27 及之前所有令牌名
/// （`card/sub/faint/pine/focus/mint/gold/goldInk/track`），因为 `models.dart`
/// 的 `SessionMode.color/lineColor` 与其它逻辑层代码引用了它们；逻辑层一行未动，
/// 只把取值映射到新色板。新增代码请直接用定稿语义名。
class PineColors {
  const PineColors._();

  // ── 纸面四阶 ───────────────────────────────────────────────────────────
  /// 主宣纸：页面主底
  static const paper = Color(0xFFFAF8F2);

  /// 手稿书页：卡片 / Composer 笺纸
  static const sheet = Color(0xFFFFFEFA);

  /// 亚麻凹槽：比例尺槽 / 输入底
  static const sunken = Color(0xFFF0EBE2);

  /// 楮皮侧栏 / 装帧底
  static const sand = Color(0xFFE9E2D6);

  // ── 松烟墨四阶 ─────────────────────────────────────────────────────────
  /// 浓墨（对纸 15.7:1）
  static const ink = Color(0xFF221D19);

  /// 中墨（对纸 7.5:1）
  static const ink2 = Color(0xFF56504A);

  /// 淡墨：元信息、刻度注记
  static const ink3 = Color(0xFF857F78);

  /// 极淡墨：空刻度、完成划线
  static const inkFaint = Color(0xFFBCB5AC);

  // ── 装帧线 ─────────────────────────────────────────────────────────────
  /// 1px 裁切线
  static const line = Color(0xFFE4DED3);

  /// 定界线 / 控件描边
  static const lineStrong = Color(0xFFD0C8BA);

  // ── 主强调 · 檀褐 ──────────────────────────────────────────────────────
  /// 檀褐（对纸 5.73:1，白字对其 5.99:1）：主行动、定界线、比例尺游标、方印
  static const accent = Color(0xFF8F5240);

  /// 按下态深笔
  static const accentDeep = Color(0xFF7A4434);

  /// 淡敷底 / 选中底
  static const accentSoft = Color(0xFFF3E6E1);

  // ── 辅助矿物色 ─────────────────────────────────────────────────────────
  /// 青瓷松绿：同步点 / 短休
  static const celadon = Color(0xFF55705C);

  /// 赭石：超时加分 / 吃饭
  static const ochre = Color(0xFF8A6A33);

  /// 茜红：危险操作
  static const crimson = Color(0xFF9E3328);

  // ── 水墨四阶（图表堆叠柱专用，固定顺序不可换）─────────────────────────
  /// 浓墨 82%
  static const ink82 = Color(0xD1221D19);

  /// 中墨 46%
  static const ink46 = Color(0x7556504A);

  /// 淡墨 22%
  static const ink22 = Color(0x38857F78);

  // ── 旧名兼容（逻辑层引用，勿删）────────────────────────────────────────
  static const card = sheet;
  static const sub = ink2;
  static const faint = inkFaint;
  static const pine = celadon;
  static const focus = accent;
  static const mint = celadon;

  /// 长休 / 完成的「实底」：浅赭纸底。`ink` 压在其上 ≥4.5:1
  /// （stage_color_test 断言），故不能直接用较暗的 `ochre`。
  static const gold = sand;

  /// 赭石线色：长休的线条 / 超时加分，对纸 ≥3.0:1 且与 `gold` 不同。
  static const goldInk = ochre;

  /// 进度轨道：比 hairline 更显眼但不能抢主体（stage_color_test 断言 1.2–1.8）。
  static const track = lineStrong;

  /// 语义色派生浅底（α=.14 叠在纸面），供段选、选中行、徽章底使用。
  /// 一律由代码派生，禁止各页手写近似色值。
  static Color tint(Color semantic) =>
      Color.alphaBlend(semantic.withAlpha(36), paper);
}

/// 字号阶梯：一屏最多六档。新代码只准引用这里，禁止写 `fontSize: 12.5`。
/// `clock` 是定稿手稿页的 64px 活字大字（w500 / letter-spacing -0.025em）。
class PineType {
  const PineType._();

  static const double clock = 64;
  static const double num = 24;
  static const double body = 15;
  static const double label = 13;
  static const double meta = 12;
  static const double caption = 11;
}

/// 字体三线：宋体衬线（标题/计时/按钮/页签）、苹方（正文）、等宽（时间戳）。
///
/// 雷区：宋体在低端 Android 上 `w600` 可能回退发虚，标题统一 `w500` +
/// `letterSpacing .01em`；`fontFamilyFallback` 保证无宋体时退到通用 serif。
class PineText {
  const PineText._();

  static const String serifFamily = 'Songti SC';
  static const List<String> serifFallback = <String>[
    'STSong',
    'Source Han Serif SC',
    'Noto Serif SC',
    'serif',
  ];
  static const List<String> monoFallback = <String>[
    'SF Mono',
    'Menlo',
    'monospace',
  ];

  /// 标题 / 大字 / 按钮 / 页签。`size` 只准传 `PineType.*`。
  static TextStyle serif({
    double size = PineType.body,
    Color color = PineColors.ink,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = 0.01,
    double? height,
    List<FontFeature>? features,
  }) =>
      TextStyle(
        fontFamily: serifFamily,
        fontFamilyFallback: serifFallback,
        fontSize: size,
        color: color,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures: features,
      );

  /// 正文说明：系统无衬线（苹方）。
  static TextStyle sans({
    double size = PineType.body,
    Color color = PineColors.ink,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) =>
      TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: height,
      );

  /// 时间戳 / 编号：等宽 + tabular-nums，避免秒数跳动时宽度抖动。
  static TextStyle mono({
    double size = PineType.meta,
    Color color = PineColors.ink2,
    FontWeight weight = FontWeight.w500,
  }) =>
      TextStyle(
        fontFamily: 'SF Mono',
        fontFamilyFallback: monoFallback,
        fontSize: size,
        color: color,
        fontWeight: weight,
        fontFeatures: kNumericFont,
      );
}

/// 圆角：定稿是「书页切角」不是软糖卡 —— 卡片 10、控件 6~9、方印 3~4、pill 999。
class PineRadius {
  const PineRadius._();

  static const double card = 10;
  static const double control = 8;
  static const double seal = 3;
  static const double pill = 999;
}

/// 两级阴影：卡片 / Composer。用负 spread 实现稿里的 `-12px` 收缩，
/// 顶部 1px 内白高光由 [PineDecoration] 的渐变模拟（Flutter 无 inset 阴影）。
class PineShadow {
  const PineShadow._();

  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x241C1A17),
      offset: Offset(0, 6),
      blurRadius: 18,
      spreadRadius: -12,
    ),
  ];

  static const List<BoxShadow> composer = <BoxShadow>[
    BoxShadow(
      color: Color(0x2E1C1A17),
      offset: Offset(0, 10),
      blurRadius: 26,
      spreadRadius: -12,
    ),
  ];
}

/// 素纸容器的统一装饰：1px 裁切线 + 顶部内白高光 + 轻纸边影。
class PineDecoration {
  const PineDecoration._();

  /// [composer] 为真时换成 Composer 的更强一级阴影与定界线。
  static BoxDecoration sheet({
    Color color = PineColors.sheet,
    double radius = PineRadius.card,
    bool composer = false,
    bool shadowed = true,
    Color? borderColor,
  }) {
    final border = borderColor ?? (composer ? PineColors.lineStrong : PineColors.line);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const <double>[0, 0.015, 1],
        colors: <Color>[
          Color.alphaBlend(const Color(0x59FFFFFF), color),
          color,
          color,
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border, width: Paper.hairline),
      boxShadow: shadowed ? (composer ? PineShadow.composer : PineShadow.card) : null,
    );
  }
}

/// 纸面几何常量。半径/投影/描边统一由这里取值。
class Paper {
  const Paper._();

  /// 卡片默认 1px 装帧线（v3 定稿：不再靠纯明度差分层）。
  static const cardBorder = 1.0;

  /// 输入框等 1px hairline 描边
  static const chipBorder = 1.0;

  static const cardRadius = PineRadius.card;

  static const chipRadius = PineRadius.control;

  static const tinyRadius = PineRadius.seal;

  /// 桌面「专注舱」的版心与环径（垂直预算的自变量，P5 重排时重新标定）。
  static const double cabinColumn = 452;
  static const double ringMax = 244;
  static const double ringMid = 200;
  static const double ringMin = 184;

  /// 最细线宽（分隔线等）
  static const hairline = 1.0;

  /// 按压位移（纸面方案不平移，恒 0；保留字段兼容旧调用）。
  static const offset = 0.0;

  /// 常态投影（卡片级）。
  static const List<BoxShadow> shadow = PineShadow.card;

  /// 描边 + 圆角 + 可选投影的通用装饰（默认 1px 裁切线、10 圆角）。
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

/// 任务可选配色。8 色，顺序兼容既有 colorIndex 0–7，换成定稿矿物/墨阶低饱和调。
const List<Color> kTaskPalette = <Color>[
  PineColors.accent, // 0 檀褐
  PineColors.celadon, // 1 青瓷
  PineColors.ochre, // 2 赭石
  PineColors.ink2, // 3 中墨
  PineColors.crimson, // 4 茜红
  PineColors.ink3, // 5 淡墨
  PineColors.accentDeep, // 6 深笔
  PineColors.lineStrong, // 7 定界
];

/// 计时与数据统一走等宽字形，避免秒数跳动时宽度抖动。
const List<FontFeature> kNumericFont = <FontFeature>[
  FontFeature.tabularFigures(),
];

ThemeData buildPineTheme() {
  const ink = PineColors.ink;
  const ink2 = PineColors.ink2;
  const line = PineColors.line;
  const accent = PineColors.accent;
  const celadon = PineColors.celadon;
  const ochre = PineColors.ochre;

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: PineColors.paper,
    canvasColor: PineColors.paper,
    colorScheme: const ColorScheme.light(
      primary: PineColors.accent,
      onPrimary: PineColors.sheet,
      secondary: PineColors.celadon,
      onSecondary: PineColors.sheet,
      tertiary: PineColors.ochre,
      onTertiary: PineColors.ink,
      surface: PineColors.sheet,
      onSurface: ink,
      error: PineColors.crimson,
      onError: PineColors.sheet,
      outline: PineColors.lineStrong,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
          headlineSmall: PineText.serif(
            size: PineType.num,
            height: 1.15,
            weight: FontWeight.w500,
          ),
          titleLarge: PineText.serif(
            size: PineType.body,
            weight: FontWeight.w500,
          ),
          bodyMedium: PineText.sans(size: PineType.body, height: 1.5),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: PineColors.paper,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: PineText.serif(size: PineType.num, weight: FontWeight.w500),
    ),
    cardTheme: const CardThemeData(
      color: PineColors.sheet,
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
      iconColor: ink2,
      textColor: ink,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PineColors.sunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Paper.chipRadius),
        borderSide: const BorderSide(color: PineColors.lineStrong, width: Paper.chipBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Paper.chipRadius),
        borderSide: const BorderSide(color: PineColors.lineStrong, width: Paper.chipBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Paper.chipRadius),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      labelStyle: PineText.sans(size: PineType.label, color: ink2),
      hintStyle: PineText.sans(size: PineType.label, color: PineColors.ink3),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: PineColors.sheet,
        minimumSize: const Size.fromHeight(46),
        textStyle: PineText.serif(size: PineType.body, color: PineColors.sheet),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Paper.chipRadius)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: PineColors.sheet,
        minimumSize: const Size.fromHeight(46),
        textStyle: PineText.serif(size: PineType.body),
        side: const BorderSide(color: PineColors.lineStrong, width: Paper.chipBorder),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Paper.chipRadius)),
        ),
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
      backgroundColor: PineColors.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Paper.cardRadius),
      ),
      titleTextStyle: PineText.serif(size: PineType.num, weight: FontWeight.w500),
      contentTextStyle: PineText.sans(size: PineType.body),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: PineColors.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Paper.cardRadius)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PineColors.sheet,
      contentTextStyle: PineText.sans(size: PineType.body),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(PineColors.sheet),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? accent : line,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? accent
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(PineColors.sheet),
      side: const BorderSide(color: PineColors.lineStrong, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Paper.tinyRadius),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: PineColors.sunken,
      linearMinHeight: 6,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: PineColors.sheet,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: PineColors.accentSoft,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => PineText.serif(
          size: PineType.caption,
          color: states.contains(WidgetState.selected) ? accent : ink2,
          weight: states.contains(WidgetState.selected)
              ? FontWeight.w500
              : FontWeight.w400,
        ),
      ),
    ),
    timePickerTheme: const TimePickerThemeData(
      backgroundColor: PineColors.sheet,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Paper.cardRadius)),
      ),
    ),
    // 语义色供系统组件兜底（正文代码请直接用 `PineColors.*`）。
    extensions: const <ThemeExtension<dynamic>>[
      _SemanticColors(mint: celadon, gold: ochre),
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
