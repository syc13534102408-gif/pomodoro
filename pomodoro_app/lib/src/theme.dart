import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// P4 双模式语义色板。页面与自建组件只允许引用语义角色，不写局部色值。
class PinePalette {
  const PinePalette({
    required this.background,
    required this.surface,
    required this.presence,
    required this.textPrimary,
    required this.textSecondary,
    required this.textAuxiliary,
    required this.textPresence,
    required this.focus,
    required this.shortBreak,
    required this.longBreak,
    required this.paused,
    required this.overtime,
    required this.adjudication,
    required this.divider,
    required this.logicalDayDivider,
    required this.taskColors,
  });

  final Color background;
  final Color surface;
  final Color presence;
  final Color textPrimary;
  final Color textSecondary;
  final Color textAuxiliary;
  final Color textPresence;
  final Color focus;
  final Color shortBreak;
  final Color longBreak;
  final Color paused;
  final Color overtime;
  final Color adjudication;
  final Color divider;
  final Color logicalDayDivider;
  final List<Color> taskColors;

  static const light = PinePalette(
    background: Color(0xFFF7F6F2),
    surface: Color(0xFFFFFFFF),
    presence: Color(0xFFECEFF3),
    textPrimary: Color(0xFF202228),
    textSecondary: Color(0xFF454952),
    textAuxiliary: Color(0xFF646B76),
    textPresence: Color(0xFF202228),
    focus: Color(0xFF146CA4),
    shortBreak: Color(0xFF24784F),
    longBreak: Color(0xFF8A5A00),
    paused: Color(0xFF596577),
    overtime: Color(0xFF7551A6),
    adjudication: Color(0xFFA7352D),
    divider: Color(0xFF727A86),
    logicalDayDivider: Color(0xFF596577),
    taskColors: <Color>[
      Color(0xFFA5465C),
      Color(0xFF247565),
      Color(0xFF356FA8),
      Color(0xFF875E12),
      Color(0xFF73549A),
      Color(0xFF52752B),
    ],
  );

  static const dark = PinePalette(
    background: Color(0xFF101114),
    surface: Color(0xFF181A1F),
    presence: Color(0xFF20242B),
    textPrimary: Color(0xFFF2F3F5),
    textSecondary: Color(0xFFC7CAD1),
    textAuxiliary: Color(0xFF9CA2AE),
    textPresence: Color(0xFFF2F3F5),
    focus: Color(0xFF7AB8FF),
    shortBreak: Color(0xFF75D0A4),
    longBreak: Color(0xFFE7B86A),
    paused: Color(0xFFA4ADBD),
    overtime: Color(0xFFC4A5F5),
    adjudication: Color(0xFFFF8F85),
    divider: Color(0xFF68707E),
    logicalDayDivider: Color(0xFF8A93A3),
    taskColors: <Color>[
      Color(0xFFE89AA6),
      Color(0xFF7CC6B3),
      Color(0xFF8EB7ED),
      Color(0xFFD8B36A),
      Color(0xFFB7A0E3),
      Color(0xFFA9C77A),
    ],
  );

  static PinePalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// 默认暗色的语义令牌与旧名兼容层。
///
/// models.dart 与尚未迁移的表现层仍引用旧名；保留别名可避免逻辑层改动。
/// 新代码使用 PinePalette.of(context)，确保跟随当前明暗模式。
class PineColors {
  const PineColors._();

  static const paper = Color(0xFF101114);
  static const sheet = Color(0xFF181A1F);
  static const sunken = Color(0xFF20242B);
  static const sand = Color(0xFF20242B);

  static const ink = Color(0xFFF2F3F5);
  static const ink2 = Color(0xFFC7CAD1);
  static const ink3 = Color(0xFF9CA2AE);
  static const inkFaint = Color(0xFF9CA2AE);

  static const line = Color(0xFF68707E);
  static const lineStrong = Color(0xFF8A93A3);

  static const accent = Color(0xFF7AB8FF);
  static const accentDeep = Color(0xFF7AB8FF);
  static const accentSoft = Color(0xFF20242B);
  static const celadon = Color(0xFF75D0A4);
  static const ochre = Color(0xFFE7B86A);
  static const crimson = Color(0xFFFF8F85);

  // 图表旧名只保留不透明语义色，不再使用透明叠加。
  static const ink82 = Color(0xFFF2F3F5);
  static const ink46 = Color(0xFFC7CAD1);
  static const ink22 = Color(0xFF9CA2AE);

  static const card = sheet;
  static const sub = ink2;
  static const faint = inkFaint;
  static const pine = celadon;
  static const focus = accent;
  static const mint = celadon;
  static const gold = sand;
  static const goldInk = ochre;
  static const track = lineStrong;

  static const background = paper;
  static const surface = sheet;
  static const presence = sunken;
  static const textPrimary = ink;
  static const textSecondary = ink2;
  static const textAuxiliary = ink3;
  static const textPresence = ink;
  static const shortBreak = celadon;
  static const longBreak = ochre;
  static const paused = Color(0xFFA4ADBD);
  static const overtime = Color(0xFFC4A5F5);
  static const adjudication = crimson;
  static const divider = line;
  static const logicalDayDivider = lineStrong;

  /// 旧选中底接口统一映射到陪驻角色，不做透明叠色。
  static Color tint(Color semantic) => presence;
}

/// 五档字阶。旧名是兼容别名，不再派生更小档位。
class PineType {
  const PineType._();

  static const double session = 40;
  static const double presence = 28;
  static const double aggregate = 24;
  static const double body = 16;
  static const double auxiliary = 13;

  static const double clock = session;
  static const double num = aggregate;
  static const double label = auxiliary;
  static const double meta = auxiliary;
  static const double caption = auxiliary;
}

class PineLineHeight {
  const PineLineHeight._();

  static const double session = 48 / PineType.session;
  static const double presence = 34 / PineType.presence;
  static const double aggregate = 30 / PineType.aggregate;
  static const double body = 24 / PineType.body;
  static const double auxiliary = 18 / PineType.auxiliary;
}

/// 系统无衬线为正文，等宽数字只服务读数与完成时刻。
class PineText {
  const PineText._();

  static const List<String> monoFallback = <String>[
    'SF Mono',
    'Menlo',
    'monospace',
  ];

  static TextStyle serif({
    double size = PineType.body,
    Color color = PineColors.ink,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0,
    double? height,
    List<FontFeature>? features,
  }) =>
      sans(
        size: size,
        color: color,
        weight: weight,
        height: height,
      ).copyWith(letterSpacing: letterSpacing, fontFeatures: features);

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

  static TextStyle mono({
    double size = PineType.auxiliary,
    Color color = PineColors.ink2,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) =>
      TextStyle(
        fontFamily: 'SF Mono',
        fontFamilyFallback: monoFallback,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: height,
        fontFeatures: kNumericFont,
      );

  static TextStyle session({Color color = PineColors.textPrimary}) => mono(
        size: PineType.session,
        color: color,
        weight: FontWeight.w600,
        height: PineLineHeight.session,
      );

  static TextStyle presence({Color color = PineColors.textPresence}) => mono(
        size: PineType.presence,
        color: color,
        weight: FontWeight.w600,
        height: PineLineHeight.presence,
      );

  static TextStyle aggregate({Color color = PineColors.textPrimary}) => sans(
        size: PineType.aggregate,
        color: color,
        weight: FontWeight.w600,
        height: PineLineHeight.aggregate,
      );
}

class PineSpacing {
  const PineSpacing._();

  static const double micro = 4;
  static const double near = 8;
  static const double section = 16;
  static const double far = 32;
  static const double major = 64;
}

class PineRadius {
  const PineRadius._();

  static const double active = 16;
  static const double settled = 8;
  static const double adjudication = 4;

  static const double card = settled;
  static const double control = settled;
  static const double seal = adjudication;
  static const double pill = active;
}

/// 新宪章不设置阴影令牌；空列表仅保留旧调用兼容。
class PineShadow {
  const PineShadow._();

  static const List<BoxShadow> card = <BoxShadow>[];
  static const List<BoxShadow> composer = <BoxShadow>[];
}

class PineDecoration {
  const PineDecoration._();

  static BoxDecoration sheet({
    Color color = PineColors.sheet,
    double radius = PineRadius.settled,
    bool composer = false,
    bool shadowed = true,
    Color? borderColor,
  }) {
    final border = borderColor ??
        (composer ? PineColors.logicalDayDivider : PineColors.divider);
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border, width: Paper.hairline),
      boxShadow: shadowed ? PineShadow.card : null,
    );
  }
}

class PineSize {
  const PineSize._();

  static const double minTouchAndroid = 48;
  static const double minTouchDesktop = 32;
  static const double primaryActionAndroid = 52;
  static const double primaryActionDesktop = 44;
  static const double standardItemAndroid = 64;
  static const double standardItemDesktop = 56;
  static const double denseItemAndroid = 52;
  static const double denseItemDesktop = 44;
  static const double stateGraphic = 20;
  static const double taskGraphic = 12;
}

class PineMotion {
  const PineMotion._();

  static const Duration immediate = Duration.zero;
  static const Duration standard = Duration(milliseconds: 160);
  static const Duration maximum = Duration(milliseconds: 200);
}

class Paper {
  const Paper._();

  static const cardBorder = 1.0;
  static const chipBorder = 1.0;
  static const cardRadius = PineRadius.settled;
  static const chipRadius = PineRadius.settled;
  static const tinyRadius = PineRadius.adjudication;

  // 旧桌面环径在对应视图迁移时继续重排，本批不改布局。
  static const double cabinColumn = 452;
  static const double ringMax = 244;
  static const double ringMid = 200;
  static const double ringMin = 184;

  static const hairline = 1.0;
  static const offset = 0.0;
  static const List<BoxShadow> shadow = PineShadow.card;

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

/// 预设六色任务标识；旧数据保存的是色值，不受色集收敛影响。
const List<Color> kTaskPalette = <Color>[
  Color(0xFFE89AA6),
  Color(0xFF7CC6B3),
  Color(0xFF8EB7ED),
  Color(0xFFD8B36A),
  Color(0xFFB7A0E3),
  Color(0xFFA9C77A),
];

const List<FontFeature> kNumericFont = <FontFeature>[
  FontFeature.tabularFigures(),
];

ThemeData buildPineTheme({Brightness brightness = Brightness.light}) {
  final palette =
      brightness == Brightness.dark ? PinePalette.dark : PinePalette.light;
  final actionHeight = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
      ? PineSize.primaryActionDesktop
      : PineSize.primaryActionAndroid;

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: palette.focus,
      onPrimary: palette.background,
      secondary: palette.shortBreak,
      onSecondary: palette.background,
      tertiary: palette.longBreak,
      onTertiary: palette.background,
      error: palette.adjudication,
      onError: palette.background,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      outline: palette.divider,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(
          bodyColor: palette.textPrimary,
          displayColor: palette.textPrimary,
        )
        .copyWith(
          displaySmall: PineText.session(color: palette.textPrimary),
          headlineSmall: PineText.aggregate(color: palette.textPrimary),
          titleLarge: PineText.sans(
            size: PineType.body,
            color: palette.textPrimary,
            weight: FontWeight.w600,
            height: PineLineHeight.body,
          ),
          bodyMedium: PineText.sans(
            size: PineType.body,
            color: palette.textPrimary,
            height: PineLineHeight.body,
          ),
          bodySmall: PineText.sans(
            size: PineType.auxiliary,
            color: palette.textAuxiliary,
            height: PineLineHeight.auxiliary,
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: PineText.aggregate(color: palette.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(PineRadius.settled)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: palette.divider,
      thickness: Paper.hairline,
      space: Paper.hairline,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: palette.textSecondary,
      textColor: palette.textPrimary,
      minTileHeight: PineSize.standardItemAndroid,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.presence,
      contentPadding: const EdgeInsets.all(PineSpacing.section),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PineRadius.settled),
        borderSide: BorderSide(color: palette.divider, width: Paper.chipBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PineRadius.settled),
        borderSide: BorderSide(color: palette.divider, width: Paper.chipBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PineRadius.settled),
        borderSide: BorderSide(color: palette.focus, width: Paper.chipBorder),
      ),
      labelStyle: PineText.sans(
        size: PineType.auxiliary,
        color: palette.textSecondary,
        height: PineLineHeight.auxiliary,
      ),
      hintStyle: PineText.sans(
        size: PineType.auxiliary,
        color: palette.textAuxiliary,
        height: PineLineHeight.auxiliary,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.focus,
        foregroundColor: palette.background,
        minimumSize: Size.fromHeight(actionHeight),
        textStyle: PineText.sans(
          size: PineType.body,
          color: palette.background,
          weight: FontWeight.w600,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(PineRadius.active)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        backgroundColor: palette.surface,
        minimumSize: Size.fromHeight(actionHeight),
        textStyle: PineText.sans(size: PineType.body),
        side: BorderSide(color: palette.divider, width: Paper.chipBorder),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(PineRadius.active)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.textPrimary),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: palette.textPrimary,
        iconSize: PineSize.stateGraphic,
        minimumSize:
            const Size(PineSize.minTouchAndroid, PineSize.minTouchAndroid),
        visualDensity: VisualDensity.compact,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PineRadius.settled),
      ),
      titleTextStyle: PineText.aggregate(color: palette.textPrimary),
      contentTextStyle: PineText.sans(
        size: PineType.body,
        color: palette.textPrimary,
        height: PineLineHeight.body,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PineRadius.settled),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surface,
      contentTextStyle: PineText.sans(
        size: PineType.body,
        color: palette.textPrimary,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(palette.background),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.focus
            : palette.divider,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.focus
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(palette.background),
      side: BorderSide(color: palette.divider, width: Paper.chipBorder),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PineRadius.adjudication),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.focus,
      linearTrackColor: palette.presence,
      linearMinHeight: PineSpacing.micro,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: palette.presence,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => PineText.sans(
          size: PineType.auxiliary,
          color: states.contains(WidgetState.selected)
              ? palette.textPrimary
              : palette.textSecondary,
          weight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          height: PineLineHeight.auxiliary,
        ),
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(PineRadius.settled)),
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[
      _SemanticColors(mint: palette.shortBreak, gold: palette.longBreak),
    ],
  );
}

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
