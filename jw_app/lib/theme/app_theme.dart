import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ink_page_transition.dart';
import 'ink_tokens.dart';

/// 全局主题：水墨淡雅（Material 3，固定配色，不做动态取色）。
///
/// 对齐个人 ink_kit 1.1.0：页面底由 `InkBackground` 绘制，Scaffold 保持透明。
class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = isDark ? _darkScheme : _lightScheme;
    final ink = isDark ? InkPalette.dark : InkPalette.light;
    final textTheme = buildInkTextTheme(scheme);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: scheme.surface,
      splashFactory: NoSplash.splashFactory,
      highlightColor: ink.pressedTint,
      splashColor: Colors.transparent,
      hoverColor: ink.pressedTint,
      dividerColor: ink.hairline,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[ink],
    );

    return base.copyWith(
      // 统一转场：安卓 17 式容器后退 + 弹性入场；iOS 保留系统横滑返回。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: InkPageTransitionsBuilder(),
          TargetPlatform.fuchsia: InkPageTransitionsBuilder(),
          TargetPlatform.linux: InkPageTransitionsBuilder(),
          TargetPlatform.windows: InkPageTransitionsBuilder(),
          TargetPlatform.macOS: InkPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: ink.cardFill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InkRadius.card),
          side: BorderSide(color: ink.hairline, width: InkStroke.hairline),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: ink.hairline,
        thickness: InkStroke.hairline,
        space: InkSpacing.l,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: ink.disabled.withValues(alpha: 0.35),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.5),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: InkSpacing.xl),
          textStyle: InkTextStyles.bodyStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(InkRadius.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: InkSpacing.xl),
          textStyle: InkTextStyles.bodyStrong,
          side: BorderSide(color: ink.hairline, width: InkStroke.emphasized),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(InkRadius.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: InkTextStyles.bodyStrong,
          padding: const EdgeInsets.symmetric(
            horizontal: InkSpacing.m,
            vertical: InkSpacing.s,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(InkRadius.control),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ink.groupedBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: InkSpacing.l,
          vertical: InkSpacing.m,
        ),
        hintStyle: InkTextStyles.body.copyWith(color: ink.secondaryLabel),
        labelStyle: InkTextStyles.caption.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(InkRadius.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(InkRadius.control),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(InkRadius.control),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(InkRadius.control),
          borderSide: BorderSide(color: ink.danger, width: 1.2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : ink.hairline,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.primaryContainer.withValues(alpha: 0.6),
        labelStyle: InkTextStyles.label.copyWith(color: scheme.primary),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(
          horizontal: InkSpacing.s,
          vertical: InkSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InkRadius.pill),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? InkColors.darkSurfaceVariant
            : InkColors.inkBlueDeep,
        contentTextStyle: InkTextStyles.body.copyWith(color: Colors.white),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InkRadius.control),
        ),
        insetPadding: const EdgeInsets.all(InkSpacing.l),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InkRadius.card + 4),
        ),
        titleTextStyle: InkTextStyles.section.copyWith(color: scheme.onSurface),
        contentTextStyle: InkTextStyles.body.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      // 下拉/溢出菜单：与卡片同一套圆角、描边与字号
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
        elevation: 8,
        textStyle: InkTextStyles.body.copyWith(color: scheme.onSurface),
        menuPadding: const EdgeInsets.symmetric(vertical: InkSpacing.xs + 2),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(InkRadius.card),
          side: BorderSide(color: ink.hairline, width: InkStroke.hairline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: ink.hairline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(InkRadius.sheet + 4),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: InkTextStyles.body.copyWith(color: scheme.onSurface),
        subtitleTextStyle: InkTextStyles.caption.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: InkSpacing.l,
          vertical: InkSpacing.xs,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: ink.hairline,
        circularTrackColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? InkColors.darkSurfaceVariant : InkColors.inkBlueDeep,
          borderRadius: BorderRadius.circular(InkRadius.control),
        ),
        textStyle: InkTextStyles.label.copyWith(color: Colors.white),
      ),
    );
  }

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: InkColors.primary,
    onPrimary: InkColors.lightOnPrimary,
    primaryContainer: InkColors.lightPrimaryContainer,
    onPrimaryContainer: InkColors.lightOnPrimaryContainer,
    secondary: InkColors.inkSky,
    onSecondary: InkColors.lightOnSecondary,
    secondaryContainer: InkColors.inkMist,
    onSecondaryContainer: InkColors.lightOnPrimaryContainer,
    tertiary: InkColors.success,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFDCEFE7),
    onTertiaryContainer: Color(0xFF1E4437),
    error: InkColors.danger,
    onError: Colors.white,
    errorContainer: Color(0xFFF7E4E2),
    onErrorContainer: Color(0xFF5C2420),
    surface: InkColors.lightBackground,
    onSurface: InkColors.lightOnSurface,
    onSurfaceVariant: InkColors.lightOnSurfaceVariant,
    surfaceContainerHighest: InkColors.lightSurfaceVariant,
    outline: InkColors.lightOutline,
    outlineVariant: InkColors.lightOutlineVariant,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: InkColors.darkSurface,
    onInverseSurface: InkColors.darkOnSurface,
    inversePrimary: InkColors.primaryDark,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: InkColors.primaryDark,
    onPrimary: InkColors.darkOnPrimary,
    primaryContainer: InkColors.darkPrimaryContainer,
    onPrimaryContainer: InkColors.darkOnPrimaryContainer,
    secondary: InkColors.accentDark,
    onSecondary: InkColors.darkOnSecondary,
    secondaryContainer: Color(0xFF23343F),
    onSecondaryContainer: Color(0xFFD6E8F3),
    tertiary: InkColors.successDark,
    onTertiary: Color(0xFF08251B),
    tertiaryContainer: Color(0xFF1D3B31),
    onTertiaryContainer: Color(0xFFBFE6D5),
    error: InkColors.dangerDark,
    onError: Color(0xFF2B0F0D),
    errorContainer: Color(0xFF4A211E),
    onErrorContainer: Color(0xFFF1C7C4),
    surface: InkColors.darkBackground,
    onSurface: InkColors.darkOnSurface,
    onSurfaceVariant: InkColors.darkOnSurfaceVariant,
    surfaceContainerHighest: InkColors.darkSurfaceVariant,
    outline: InkColors.darkOutline,
    outlineVariant: InkColors.darkOutlineVariant,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: InkColors.lightSurface,
    onInverseSurface: InkColors.lightOnSurface,
    inversePrimary: InkColors.primary,
  );
}
