import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 单浅色语义色板。页面与自建组件只允许引用语义角色，不写局部色值。
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
    required this.brand,
    required this.action,
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
  final Color brand;
  final Color action;

  static const light = PinePalette(
    background: Color(0xFFF7F6F2),
    surface: Color(0xFFFFFFFF),
    presence: Color(0xFFF1EDE6),
    textPrimary: Color(0xFF2B2925),
    textSecondary: Color(0xFF514B43),
    textAuxiliary: Color(0xFF70675D),
    textPresence: Color(0xFF2B2925),
    focus: Color(0xFF2E6573),
    shortBreak: Color(0xFF38684C),
    longBreak: Color(0xFF775A28),
    paused: Color(0xFF686357),
    overtime: Color(0xFF6F587C),
    adjudication: Color(0xFFA3322B),
    divider: Color(0xFF8B8276),
    logicalDayDivider: Color(0xFF70675D),
    taskColors: <Color>[
      Color(0xFFA5465C),
      Color(0xFF247565),
      Color(0xFF356FA8),
      Color(0xFF875E12),
      Color(0xFF73549A),
      Color(0xFF52752B),
    ],
    brand: Color(0xFFD97757),
    action: Color(0xFFA8472F),
  );

  static PinePalette of(BuildContext context) => light;
}

/// 单浅色语义令牌与旧名兼容层。
///
/// models.dart 与尚未迁移的表现层仍引用旧名；保留别名可避免逻辑层改动。
/// 新代码使用 PinePalette.of(context)，统一消费单浅色角色。
class PineColors {
  const PineColors._();

  static const paper = Color(0xFFF7F6F2);
  static const sheet = Color(0xFFFFFFFF);
  static const sunken = Color(0xFFF1EDE6);
  static const sand = Color(0xFFF1EDE6);

  static const ink = Color(0xFF2B2925);
  static const ink2 = Color(0xFF514B43);
  static const ink3 = Color(0xFF70675D);
  static const inkFaint = Color(0xFF70675D);

  static const line = Color(0xFF8B8276);
  static const lineStrong = Color(0xFF70675D);

  static const accent = Color(0xFFA8472F);
  static const accentSoft = Color(0xFFF1EDE6);
  static const celadon = Color(0xFF38684C);
  static const ochre = Color(0xFF775A28);
  static const crimson = Color(0xFFA3322B);
  static const signature = Color(0xFFD97757);
  static const surfaceHairline = Color(0xFFDED8CE);
  static const actionHover = Color(0xFF943D29);
  static const actionPressed = Color(0xFF7E3424);
  static const dangerHover = Color(0xFF8C2924);
  static const dangerPressed = Color(0xFF76221E);

  static const card = sheet;
  static const sub = ink2;
  static const faint = inkFaint;
  static const pine = celadon;
  static const focus = Color(0xFF2E6573);
  static const mint = celadon;
  static const gold = Color(0xFF775A28);
  static const goldInk = gold;
  static const track = lineStrong;

  static const background = paper;
  static const surface = sheet;
  static const presence = sunken;
  static const textPrimary = ink;
  static const textSecondary = ink2;
  static const textAuxiliary = ink3;
  static const textPresence = ink;
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

/// 打包宋体仅用于标题；正文和等宽数字均使用打包无衬线族。
class PineText {
  const PineText._();

  static const List<String> monoFallback = bodyFallback;
  static const String headingFamily = 'Noto Serif SC';
  static const String bodyFamily = 'Noto Sans SC';
  static const List<String> headingFallback = <String>[
    'Noto Serif CJK SC',
    'Songti SC',
    'STSong',
    'serif'
  ];
  static const List<String> bodyFallback = <String>[
    'Noto Sans CJK SC',
    'PingFang SC',
    'Microsoft YaHei',
    'sans-serif'
  ];

  static TextStyle serif({
    double size = PineType.body,
    Color color = PineColors.ink,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0,
    double? height,
    List<FontFeature>? features,
  }) =>
      TextStyle(
        fontFamily: headingFamily,
        fontFamilyFallback: headingFallback,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        fontFeatures: features,
      );

  static TextStyle sans({
    double size = PineType.body,
    Color color = PineColors.ink,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) =>
      TextStyle(
        fontFamily: bodyFamily,
        fontFamilyFallback: bodyFallback,
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
        fontFamily: bodyFamily,
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

  static const double active = 24;
  static const double settled = 16;
  static const double adjudication = 8;

  static const double card = settled;
  static const double control = settled;
  static const double seal = adjudication;
}

class PineShadow {
  const PineShadow._();
  static const List<BoxShadow> none = <BoxShadow>[];
  static const ambient = card;
  static const overlay = composer;

  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(color: Color(0x0A2B2925), offset: Offset(0, 2), blurRadius: 8),
  ];
  static const List<BoxShadow> composer = <BoxShadow>[
    BoxShadow(color: Color(0x142B2925), offset: Offset(0, 8), blurRadius: 24),
  ];
}

class PineDecoration {
  const PineDecoration._();

  static BoxDecoration sheet({
    Color color = PineColors.sheet,
    double radius = PineRadius.settled,
    bool composer = false,
    bool shadowed = false,
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

  static const chipBorder = 1.0;
  static const cardRadius = PineRadius.settled;
  static const chipRadius = PineRadius.settled;

  // 旧桌面环径在对应视图迁移时继续重排，本批不改布局。
  static const double cabinColumn = 452;
  static const double ringMax = 244;
  static const double ringMid = 200;
  static const double ringMin = 184;

  static const hairline = 1.0;
  static const List<BoxShadow> shadow = <BoxShadow>[];
}

/// 预设六色任务标识；旧数据保存的是色值，不受色集收敛影响。
const List<Color> kTaskPalette = <Color>[
  Color(0xFFA5465C),
  Color(0xFF247565),
  Color(0xFF356FA8),
  Color(0xFF875E12),
  Color(0xFF73549A),
  Color(0xFF52752B),
];

class PineTimerArc {
  const PineTimerArc._();
  static const double compactBox = 160;
  static const double spaciousBox = 192;
  static const double sweepDegrees = 288;
  static const double startDegrees = 216;
  static const double stroke = 4;
  static const double endDot = 8;
  static const double separator = 2;
}

const List<FontFeature> kNumericFont = <FontFeature>[
  FontFeature.tabularFigures(),
];

ThemeData buildPineTheme() {
  const palette = PinePalette.light;
  final actionHeight = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
      ? PineSize.primaryActionDesktop
      : PineSize.primaryActionAndroid;

  final base = ThemeData(
    useMaterial3: true,
    fontFamily: PineText.bodyFamily,
    fontFamilyFallback: PineText.bodyFallback,
    brightness: Brightness.light,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: palette.action,
      onPrimary: Colors.white,
      secondary: palette.action,
      onSecondary: Colors.white,
      tertiary: palette.longBreak,
      onTertiary: Colors.white,
      error: palette.adjudication,
      onError: Colors.white,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      outline: palette.divider,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(
          fontFamily: PineText.bodyFamily,
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
      titleTextStyle: PineText.serif(
          size: PineType.aggregate,
          color: palette.textPrimary,
          height: PineLineHeight.aggregate),
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
      fillColor: palette.surface,
      contentPadding: const EdgeInsets.all(PineSpacing.section),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PineRadius.settled),
        borderSide: BorderSide(color: palette.divider, width: Paper.chipBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(PineRadius.settled),
        borderSide: BorderSide(color: palette.divider, width: Paper.chipBorder),
      ),
      focusedBorder: const PineInputFocusBorder(),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PineRadius.settled),
          borderSide: BorderSide(color: palette.adjudication)),
      focusedErrorBorder:
          PineInputFocusBorder(side: BorderSide(color: palette.adjudication)),
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
      style: pinePrimaryButtonStyle().merge(FilledButton.styleFrom(
        backgroundColor: palette.action,
        foregroundColor: Colors.white,
        minimumSize: Size.fromHeight(actionHeight),
        textStyle: PineText.sans(
          size: PineType.body,
          color: Colors.white,
          weight: FontWeight.w600,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(PineRadius.settled)),
        ),
      )),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textSecondary,
        backgroundColor: palette.surface,
        minimumSize: Size.fromHeight(actionHeight),
        textStyle: PineText.sans(size: PineType.body),
        side: BorderSide(color: palette.divider, width: Paper.chipBorder),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(PineRadius.settled)),
        ),
      ).copyWith(
        visualDensity: VisualDensity.standard,
        animationDuration: Duration.zero,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled) ||
                    states.contains(WidgetState.pressed)
                ? palette.presence
                : states.contains(WidgetState.hovered)
                    ? palette.background
                    : palette.surface),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? palette.textAuxiliary
                : palette.textSecondary),
        shape: WidgetStateProperty.resolveWith((states) =>
            PineButtonBorder(focused: states.contains(WidgetState.focused))),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(foregroundColor: palette.textSecondary).copyWith(
        animationDuration: Duration.zero,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? palette.textAuxiliary
                : states.contains(WidgetState.pressed)
                    ? PineColors.actionPressed
                    : states.contains(WidgetState.hovered)
                        ? palette.action
                        : palette.textSecondary),
        textStyle: WidgetStateProperty.resolveWith((states) => PineText.sans()
            .copyWith(
                decoration: states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.pressed)
                    ? TextDecoration.underline
                    : TextDecoration.none)),
        shape: WidgetStateProperty.resolveWith((states) =>
            PineButtonBorder(focused: states.contains(WidgetState.focused))),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: palette.textPrimary,
        iconSize: PineSize.stateGraphic,
        minimumSize:
            const Size(PineSize.minTouchAndroid, PineSize.minTouchAndroid),
        visualDensity: VisualDensity.compact,
      ).copyWith(
          shape: WidgetStateProperty.resolveWith((states) =>
              PineButtonBorder(focused: states.contains(WidgetState.focused)))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PineRadius.settled),
      ),
      titleTextStyle: PineText.serif(
          size: PineType.aggregate,
          color: palette.textPrimary,
          height: PineLineHeight.aggregate),
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
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? Colors.white
              : palette.textPrimary),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.action
            : palette.presence,
      ),
      trackOutlineColor: WidgetStatePropertyAll(palette.divider),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.action
            : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      side: BorderSide(color: palette.divider, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PineRadius.adjudication),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.action,
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
  );
}

/// 键盘焦点画在外侧，不改变布局或稳定选中状态。
class PineFocusRing extends StatefulWidget {
  const PineFocusRing(
      {super.key, required this.child, this.radius = PineRadius.settled});
  final Widget child;
  final double radius;
  @override
  State<PineFocusRing> createState() => _PineFocusRingState();
}

class _PineFocusRingState extends State<PineFocusRing> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => _focused = value),
        child: CustomPaint(
          foregroundPainter: _focused ? _PineFocusPainter(widget.radius) : null,
          child: widget.child,
        ),
      );
}

class _PineFocusPainter extends CustomPainter {
  const _PineFocusPainter(this.radius);
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1), Radius.circular(radius + 1)),
        paint..color = Colors.white);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(3), Radius.circular(radius + 3)),
        paint..color = PineColors.accent);
  }

  @override
  bool shouldRepaint(_PineFocusPainter oldDelegate) =>
      radius != oldDelegate.radius;
}

/// 原生按钮同样使用外侧白隔离与赤陶焦点，尺寸与命中区域不变。
class PineButtonBorder extends RoundedRectangleBorder {
  const PineButtonBorder({this.focused = false, super.side = BorderSide.none})
      : super(
            borderRadius:
                const BorderRadius.all(Radius.circular(PineRadius.settled)));
  final bool focused;
  @override
  bool operator ==(Object other) =>
      other is PineButtonBorder &&
      other.focused == focused &&
      other.side == side;
  @override
  int get hashCode => Object.hash(focused, side);
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => t < 0.5 ? a : this;
  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => t < 0.5 ? this : b;
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    super.paint(canvas, rect, textDirection: textDirection);
    if (!focused) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1), const Radius.circular(17)),
        paint..color = Colors.white);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(19)),
        paint..color = PineColors.accent);
  }

  @override
  PineButtonBorder copyWith(
          {BorderSide? side, BorderRadiusGeometry? borderRadius}) =>
      PineButtonBorder(focused: focused, side: side ?? this.side);
}

class PineInputFocusBorder extends OutlineInputBorder {
  const PineInputFocusBorder(
      {BorderSide side = const BorderSide(color: PineColors.line)})
      : super(
            borderRadius:
                const BorderRadius.all(Radius.circular(PineRadius.settled)),
            borderSide: side);
  @override
  PineInputFocusBorder copyWith(
          {BorderSide? borderSide,
          BorderRadius? borderRadius,
          double? gapPadding}) =>
      PineInputFocusBorder(side: borderSide ?? this.borderSide);
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => this;
  @override
  void paint(Canvas canvas, Rect rect,
      {double? gapStart,
      double gapExtent = 0,
      double gapPercentage = 0,
      TextDirection? textDirection}) {
    super.paint(canvas, rect,
        gapStart: gapStart,
        gapExtent: gapExtent,
        gapPercentage: gapPercentage,
        textDirection: textDirection);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1), const Radius.circular(17)),
        paint..color = Colors.white);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(19)),
        paint..color = PineColors.accent);
  }
}

/// 六态主行动工艺。加载使用相同默认底，文本仍保留。
ButtonStyle pinePrimaryButtonStyle(
    {Color? background, Color? foreground, bool loading = false}) {
  final neutral =
      background == PineColors.surface || background == PineColors.paper;
  final danger = background == PineColors.crimson;
  return ButtonStyle(
    visualDensity: VisualDensity.standard,
    animationDuration: Duration.zero,
    elevation: const WidgetStatePropertyAll(0),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled) && !loading) {
        return PineColors.presence;
      }
      if (neutral) {
        if (states.contains(WidgetState.pressed)) return PineColors.presence;
        if (states.contains(WidgetState.hovered)) return PineColors.paper;
        return PineColors.surface;
      }
      if (danger) {
        if (states.contains(WidgetState.pressed)) {
          return PineColors.dangerPressed;
        }
        if (states.contains(WidgetState.hovered)) return PineColors.dangerHover;
        return PineColors.crimson;
      }
      if (background != null && background != PineColors.accent) {
        return background;
      }
      if (states.contains(WidgetState.pressed)) return PineColors.actionPressed;
      if (states.contains(WidgetState.hovered)) return PineColors.actionHover;
      return PineColors.accent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.disabled) && !loading
            ? PineColors.textAuxiliary
            : foreground ??
                (neutral ? PineColors.textSecondary : Colors.white)),
    side: WidgetStateProperty.resolveWith((states) =>
        (states.contains(WidgetState.disabled) && !loading) || neutral
            ? const BorderSide(color: PineColors.line)
            : BorderSide.none),
    shape: WidgetStateProperty.resolveWith((states) =>
        PineButtonBorder(focused: states.contains(WidgetState.focused))),
  );
}
