/// 水墨淡雅设计令牌（自建副本）
///
/// 数值取自个人 ink_kit 1.1.0，单调一处出口：颜色、间距、圆角、描边、
/// 动效只允许从这里取，业务页面不再写十六进制与手写 fontSize。
library;

import 'package:flutter/material.dart';

/// 固定色板（不做 Material You 动态取色）。
abstract final class InkColors {
  // ---- 水墨基色 ----
  static const Color inkBlueDeep = Color(0xFF234B69);
  static const Color inkSky = Color(0xFF6FA8CB);
  static const Color inkMist = Color(0xFFE9F1F7);

  /// 品牌主色：淡墨蓝。
  static const Color primary = Color(0xFF35678F);
  static const Color primaryDark = Color(0xFF8FB9D6);

  static const Color accent = inkSky;
  static const Color accentDark = Color(0xFFA9CDE4);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3E739B), Color(0xFF7EB3D4)],
  );

  static const LinearGradient brandGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF25506F), Color(0xFF4E86A8)],
  );

  // ---- 语义色（低饱和，不随品牌色变化）----
  static const Color success = Color(0xFF2F7A5C);
  static const Color successDark = Color(0xFF6FC7A2);
  static const Color warning = Color(0xFF99661C);
  static const Color warningDark = Color(0xFFE0B071);
  static const Color danger = Color(0xFFA5443E);
  static const Color dangerDark = Color(0xFFE2938D);
  static const Color info = Color(0xFF35708F);
  static const Color infoDark = accentDark;
  static const Color disabled = Color(0xFF9DAAB4);
  static const Color disabledDark = Color(0xFF5D6E7A);

  // ---- 浅色：宣纸白 ----
  static const Color lightBackground = Color(0xFFF7F9FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainer = Color(0xFFF2F6F8);
  static const Color lightSurfaceVariant = Color(0xFFEBF1F4);
  static const Color lightPrimaryContainer = Color(0xFFDDEAF3);
  static const Color lightOnPrimaryContainer = Color(0xFF1E4258);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightOnSecondary = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF1E2C35);
  static const Color lightOnSurfaceVariant = Color(0xFF4C5E6A);
  static const Color lightOutline = Color(0xFFD8E1E7);
  static const Color lightOutlineVariant = Color(0x59E9EFF2);

  // ---- 深色：淡墨夜色 ----
  static const Color darkBackground = Color(0xFF0F171D);
  static const Color darkSurface = Color(0xFF152026);
  static const Color darkSurfaceContainer = Color(0xFF1B272E);
  static const Color darkSurfaceVariant = Color(0xFF212F37);
  static const Color darkPrimaryContainer = Color(0xFF274557);
  static const Color darkOnPrimaryContainer = Color(0xFFD6E8F3);
  static const Color darkOnPrimary = Color(0xFF0A1E2B);
  static const Color darkOnSecondary = Color(0xFF0A1E2B);
  static const Color darkOnSurface = Color(0xFFEDF3F6);
  static const Color darkOnSurfaceVariant = Color(0xFFB4C5CF);
  static const Color darkOutline = Color(0xFF2A3A44);
  static const Color darkOutlineVariant = Color(0x59202E37);
}

/// 间距阶梯（只用 4 的倍数，页面左右统一 16）。
abstract final class InkSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: l);
}

abstract final class InkRadius {
  static const double card = 16;
  static const double control = 12;
  static const double sheet = 16;
  static const double fab = 18;
  static const double pill = 999;
}

abstract final class InkStroke {
  /// 0.6dp 在高 dpi 上落成 1~2 物理像素，避免换色后出现硬线。
  static const double hairline = 0.6;
  static const double emphasized = 1.0;
}

abstract final class InkMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration tabSwitch = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 520);
  static const Duration noticeExpand = Duration(milliseconds: 220);
  static const Duration noticeCollapse = Duration(milliseconds: 180);

  /// 底部弹层：比普通页面稍长一点，收尾更有「落定」感。
  static const Duration sheet = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.fastOutSlowIn;

  /// 安卓 17 式弹性：只用于缩放/位移，不用于透明度，避免越界。
  static const Curve spring = Curves.easeOutBack;

  /// 安卓 17 式减速：长尾收束，适合大面积页面进场。
  static const Curve decelerate = Curves.easeOutQuint;
}

abstract final class InkGlass {
  static const double cardFillLight = 0.84;
  static const double cardFillDark = 0.76;

  static const double navHeight = 72;
  static const double navMargin = 16;
  static const double navBottomMargin = 16;
  static const double navRadius = InkRadius.pill;

  /// 悬浮胶囊：透明液体玻璃，不做毛玻璃（blur 必须为 0）。
  static const double navBlur = 0;

  /// 液体玻璃底色：只留一层很薄的雾面，主要靠高光与描边成型。
  /// 数值越小越通透；过大会在浅色背景上发灰。
  static const double navFillLight = 0.20;
  static const double navFillDark = 0.22;

  /// 悬浮胶囊的投影：柔和、范围大，制造"离开纸面"的层次。
  ///
  /// 玻璃是半透明的，投影会从胶囊内部透出来把整条导航压灰，
  /// 因此浅色主题刻意压得很淡，只在底部留一点悬浮感。
  static List<BoxShadow> navShadows(bool isDark) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.05),
      blurRadius: 24,
      spreadRadius: -2,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.02),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> cardShadows(bool isDark) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.05),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
  ];
}

/// 外壳把「底部导航实际占用高度」下发下来，内容页统一从这里取避让值。
class InkNavMetrics extends InheritedWidget {
  const InkNavMetrics({
    super.key,
    required this.bottomInset,
    required this.visible,
    required super.child,
  });

  final double bottomInset;
  final bool visible;

  static InkNavMetrics? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InkNavMetrics>();

  @override
  bool updateShouldNotify(InkNavMetrics oldWidget) =>
      bottomInset != oldWidget.bottomInset || visible != oldWidget.visible;
}

/// 内容页底部避让：胶囊 + 手势条 + 呼吸间距。
EdgeInsets inkPagePadding(
  BuildContext context, {
  double top = 4,
  double extraBottom = 0,
}) {
  final metrics = InkNavMetrics.maybeOf(context);
  final media = MediaQuery.paddingOf(context).bottom;
  // 在 shell 内：避让胶囊（其高度已含手势条）；独立路由：只避让手势条。
  final navSpace = metrics != null && metrics.visible
      ? metrics.bottomInset
      : media;
  return EdgeInsets.fromLTRB(
    InkSpacing.l,
    top,
    InkSpacing.l,
    navSpace + 24 + extraBottom,
  );
}

/// 课表课程色（低饱和底 + 深色字），按课程名固定分配。
/// 网格里唯一允许出现的多彩颜色，集中到这里方便统一调。
abstract final class InkCourseTints {
  static const List<(Color, Color)> light = [
    (Color(0xFFE3EEF6), Color(0xFF2A5A7A)), // 蓝
    (Color(0xFFE4F0E9), Color(0xFF2F6B4F)), // 绿
    (Color(0xFFEDE9F6), Color(0xFF53407A)), // 紫
    (Color(0xFFF7EEDF), Color(0xFF8A5A22)), // 橙
    (Color(0xFFE2F1F2), Color(0xFF24666B)), // 青
    (Color(0xFFF6E8EC), Color(0xFF8A3B51)), // 粉
    (Color(0xFFE7EAF3), Color(0xFF3E4C79)), // 靛
    (Color(0xFFEFEBE7), Color(0xFF5B4A3D)), // 棕
  ];

  static const List<(Color, Color)> dark = [
    (Color(0xFF1E3446), Color(0xFF9DC6E0)),
    (Color(0xFF1D3A2F), Color(0xFF8FCBAB)),
    (Color(0xFF2C2A42), Color(0xFFB4A8E0)),
    (Color(0xFF3A3020), Color(0xFFDDBB85)),
    (Color(0xFF1B3638), Color(0xFF8CC7C9)),
    (Color(0xFF3A2429), Color(0xFFDFA3B2)),
    (Color(0xFF252A3F), Color(0xFFA9B4E2)),
    (Color(0xFF2E2A26), Color(0xFFC9B7A5)),
  ];

  static List<(Color, Color)> of(BuildContext context) =>
      context.isDark ? dark : light;
}

/// 语义色调。低饱和，避免抢走品牌色。
enum InkTone { neutral, info, success, warning, danger }

Color inkToneColor(BuildContext context, InkTone tone) {
  final ink = context.ink;
  return switch (tone) {
    InkTone.neutral => context.scheme.onSurfaceVariant,
    InkTone.info => ink.info,
    InkTone.success => ink.success,
    InkTone.warning => ink.warning,
    InkTone.danger => ink.danger,
  };
}

/// 挂在 ThemeData 上的扩展色板：ColorScheme 表达不了的语义色放这里。
@immutable
class InkPalette extends ThemeExtension<InkPalette> {
  const InkPalette({
    required this.isDark,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.disabled,
    required this.cardFill,
    required this.glassNavFill,
    required this.hairline,
    required this.brandGradient,
    required this.secondaryLabel,
    required this.groupedBackground,
    required this.pressedTint,
    required this.skeleton,
  });

  final bool isDark;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color disabled;
  final Color cardFill;
  final Color glassNavFill;
  final Color hairline;
  final LinearGradient brandGradient;
  final Color secondaryLabel;
  final Color groupedBackground;
  final Color pressedTint;
  final Color skeleton;

  static const InkPalette light = InkPalette(
    isDark: false,
    success: InkColors.success,
    warning: InkColors.warning,
    danger: InkColors.danger,
    info: InkColors.info,
    disabled: InkColors.disabled,
    cardFill: Color(0xD6FFFFFF),
    glassNavFill: Color(0x33FFFFFF),
    hairline: InkColors.lightOutline,
    brandGradient: InkColors.brandGradient,
    secondaryLabel: Color(0xFF566975),
    groupedBackground: Color(0xFFF1F5F7),
    pressedTint: Color(0x14000000),
    skeleton: Color(0xFFE7EEF2),
  );

  static const InkPalette dark = InkPalette(
    isDark: true,
    success: InkColors.successDark,
    warning: InkColors.warningDark,
    danger: InkColors.dangerDark,
    info: InkColors.infoDark,
    disabled: InkColors.disabledDark,
    cardFill: Color(0xC2152026),
    glassNavFill: Color(0x38152026),
    hairline: InkColors.darkOutline,
    brandGradient: InkColors.brandGradientDark,
    secondaryLabel: Color(0xFF9EB0BC),
    groupedBackground: Color(0xFF121C22),
    pressedTint: Color(0x1AFFFFFF),
    skeleton: Color(0xFF1F2C34),
  );

  static InkPalette of(BuildContext context) =>
      Theme.of(context).extension<InkPalette>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  InkPalette copyWith({
    bool? isDark,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? disabled,
    Color? cardFill,
    Color? glassNavFill,
    Color? hairline,
    LinearGradient? brandGradient,
    Color? secondaryLabel,
    Color? groupedBackground,
    Color? pressedTint,
    Color? skeleton,
  }) {
    return InkPalette(
      isDark: isDark ?? this.isDark,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      disabled: disabled ?? this.disabled,
      cardFill: cardFill ?? this.cardFill,
      glassNavFill: glassNavFill ?? this.glassNavFill,
      hairline: hairline ?? this.hairline,
      brandGradient: brandGradient ?? this.brandGradient,
      secondaryLabel: secondaryLabel ?? this.secondaryLabel,
      groupedBackground: groupedBackground ?? this.groupedBackground,
      pressedTint: pressedTint ?? this.pressedTint,
      skeleton: skeleton ?? this.skeleton,
    );
  }

  @override
  InkPalette lerp(ThemeExtension<InkPalette>? other, double t) {
    if (other is! InkPalette) return this;
    return InkPalette(
      isDark: t < 0.5 ? isDark : other.isDark,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      cardFill: Color.lerp(cardFill, other.cardFill, t)!,
      glassNavFill: Color.lerp(glassNavFill, other.glassNavFill, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      brandGradient: t < 0.5 ? brandGradient : other.brandGradient,
      secondaryLabel: Color.lerp(secondaryLabel, other.secondaryLabel, t)!,
      groupedBackground: Color.lerp(
        groupedBackground,
        other.groupedBackground,
        t,
      )!,
      pressedTint: Color.lerp(pressedTint, other.pressedTint, t)!,
      skeleton: Color.lerp(skeleton, other.skeleton, t)!,
    );
  }
}

/// 组件里最常用的取值，收成 extension。
extension InkContext on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;
  InkPalette get ink => InkPalette.of(this);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// 中文/金额类等宽数字。
  TextStyle get tabular =>
      const TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
}

/// 排版阶梯：只用 30 / 22 / 17 / 15 / 13 / 11 六档。
abstract final class InkTextStyles {
  static const TextStyle display = TextStyle(
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  static const TextStyle title = TextStyle(
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  static const TextStyle section = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontSize: 11,
    height: 1.25,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// 课表网格等紧凑场景。
  static const TextStyle micro = TextStyle(
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle nano = TextStyle(
    fontSize: 9,
    height: 1.1,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle number = TextStyle(
    fontSize: 28,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// 把 [InkTextStyles] 落成 ColorScheme 的 TextTheme。
TextTheme buildInkTextTheme(ColorScheme scheme) {
  TextStyle withColor(TextStyle base, Color color) =>
      base.copyWith(color: color);

  final onSurface = scheme.onSurface;
  final variant = scheme.onSurfaceVariant;

  return TextTheme(
    displaySmall: withColor(InkTextStyles.display, onSurface),
    headlineMedium: withColor(InkTextStyles.title, onSurface),
    headlineSmall: withColor(InkTextStyles.section, onSurface),
    titleMedium: withColor(InkTextStyles.bodyStrong, onSurface),
    bodyLarge: withColor(InkTextStyles.body, onSurface),
    bodyMedium: withColor(InkTextStyles.body, onSurface),
    bodySmall: withColor(InkTextStyles.caption, variant),
    labelLarge: withColor(InkTextStyles.bodyStrong, onSurface),
    labelMedium: withColor(InkTextStyles.caption, variant),
    labelSmall: withColor(InkTextStyles.label, variant),
  );
}

extension InkTextContext on BuildContext {
  TextStyle get tsDisplay =>
      InkTextStyles.display.copyWith(color: scheme.onSurface);
  TextStyle get tsTitle =>
      InkTextStyles.title.copyWith(color: scheme.onSurface);
  TextStyle get tsSection =>
      InkTextStyles.section.copyWith(color: scheme.onSurface);
  TextStyle get tsBody => InkTextStyles.body.copyWith(color: scheme.onSurface);
  TextStyle get tsBodyStrong =>
      InkTextStyles.bodyStrong.copyWith(color: scheme.onSurface);
  TextStyle get tsCaption =>
      InkTextStyles.caption.copyWith(color: scheme.onSurfaceVariant);
  TextStyle get tsSecondary =>
      InkTextStyles.caption.copyWith(color: ink.secondaryLabel);
  TextStyle get tsLabel =>
      InkTextStyles.label.copyWith(color: scheme.onSurfaceVariant);
}
