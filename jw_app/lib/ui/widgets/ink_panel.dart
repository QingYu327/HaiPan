import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../theme/ink_tokens.dart';

/// 背景预设：ink 保留宣纸光晕，其余为低饱和渐变，solid / image 由用户指定。
const Map<String, (List<Color>, List<Color>)> inkBgPresets = {
  'mist': (
    [Color(0xFFEDF4F8), Color(0xFFD4E4EE)],
    [Color(0xFF101B22), Color(0xFF1A2A34)],
  ),
  'dusk': (
    [Color(0xFFF8EEE8), Color(0xFFE7D6CF)],
    [Color(0xFF1C1518), Color(0xFF2A1E24)],
  ),
  'bamboo': (
    [Color(0xFFEEF4EB), Color(0xFFD7E5D3)],
    [Color(0xFF121C16), Color(0xFF1D2A20)],
  ),
  'sunrise': (
    [Color(0xFFFCF4E7), Color(0xFFF3E0C5)],
    [Color(0xFF221A12), Color(0xFF2E2418)],
  ),
  'night': (
    [Color(0xFFE9EFF7), Color(0xFFC9D8E8)],
    [Color(0xFF0A1117), Color(0xFF16242E)],
  ),
};

/// 背景：宣纸光晕 / 预设渐变 / 纯色 / 自定义图片，全部读取用户设置。
class InkBackground extends ConsumerStatefulWidget {
  const InkBackground({
    super.key,
    this.child,
    this.animate = true,
  });

  final Widget? child;

  /// 缓慢呼吸（18s 一轮）；静态页面可传 false 省电。
  final bool animate;

  @override
  ConsumerState<InkBackground> createState() => _InkBackgroundState();
}

class _InkBackgroundState extends ConsumerState<InkBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final settings = ref.watch(settingsProvider);
    final base = scheme.surface;
    final glow = isDark
        ? scheme.primary.withValues(alpha: 0.10)
        : scheme.primary.withValues(alpha: 0.06);

    Widget paint(double t) {
      final style = settings.backgroundStyle;
      if (style == 'solid') {
        return ColoredBox(color: Color(settings.backgroundSeed));
      }
      if (style == 'image') {
        return _ImageBackdrop(
          path: settings.backgroundImage,
          blur: settings.backgroundBlur,
          fallback: base,
        );
      }
      if (inkBgPresets.containsKey(style)) {
        final preset = inkBgPresets[style]!;
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark ? preset.$2 : preset.$1,
                  ),
                ),
              ),
            ),
            Positioned(
              top: -130 + t * 20,
              right: -90,
              child: _Orb(
                color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.22),
                size: 300,
              ),
            ),
            Positioned(
              bottom: -150 - t * 16,
              left: -110,
              child: _Orb(
                color: Colors.white.withValues(alpha: isDark ? 0.04 : 0.18),
                size: 340,
              ),
            ),
          ],
        );
      }
      // 默认宣纸底
      return Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: base)),
          Positioned(
            top: -140 + t * 24,
            right: -100,
            child: _Orb(color: glow, size: 320),
          ),
          Positioned(
            bottom: -160 - t * 18,
            left: -120,
            child: _Orb(color: glow, size: 360),
          ),
        ],
      );
    }

    final background = widget.animate
        ? AnimatedBuilder(animation: _ctrl, builder: (_, _) => paint(_ctrl.value))
        : paint(0);

    if (widget.child == null) return background;
    return Stack(
      children: [
        Positioned.fill(child: background),
        Positioned.fill(child: widget.child!),
      ],
    );
  }
}

/// 图片背景：仅使用本地图片，模糊按设置叠加；加载失败回退底色。
class _ImageBackdrop extends StatelessWidget {
  const _ImageBackdrop({
    required this.path,
    required this.blur,
    required this.fallback,
  });

  final String path;
  final double blur;
  final Color fallback;

  @override
  Widget build(BuildContext context) {
    Widget image = Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    if (blur > 0.1) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: image,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: fallback),
        if (path.isNotEmpty) image,
      ],
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}

/// 半透明面板：导航胶囊、浮层、需要透出背景的容器。
///
/// 默认 `blur: 0`：只靠半透明 + 描边 + 顶边高光，不做毛玻璃。
class InkGlassPanel extends StatelessWidget {
  const InkGlassPanel({
    super.key,
    required this.child,
    this.fill,
    this.borderRadius,
    this.blur = 0,
    this.borderColor,
    this.shadows,
    this.padding,
    this.liquid = false,
  });

  final Widget child;
  final Color? fill;
  final BorderRadius? borderRadius;
  final double blur;
  final Color? borderColor;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry? padding;

  /// 透明液体玻璃：不做毛玻璃，用高透明底 + 斜向高光 + 白色内描边，
  /// 让背景从面板中直接透出。导航胶囊使用该模式。
  final bool liquid;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final radius = borderRadius ?? BorderRadius.circular(InkRadius.card);
    final isDark = context.isDark;
    final edge = borderColor ??
        (liquid
            ? Colors.white.withValues(alpha: isDark ? 0.26 : 0.85)
            : ink.hairline);

    Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? ink.cardFill,
        borderRadius: radius,
        border: Border.all(
          color: edge,
          width: liquid ? InkStroke.emphasized : InkStroke.hairline,
        ),
      ),
      child: Stack(
        children: [
          // 液体玻璃的斜向高光：左上更亮，向右下淡出。
          if (liquid)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.08 : 0.20),
                        Colors.white.withValues(alpha: isDark ? 0.02 : 0.03),
                        Colors.white.withValues(alpha: isDark ? 0.05 : 0.08),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // 顶边高光：只留最上面一条，中间亮、两端透明。
          Positioned(
            top: 0,
            left: 12,
            right: 12,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: isDark ? 0.18 : 0.85),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );

    if (blur > 0) {
      panel = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: panel,
        ),
      );
    } else {
      panel = ClipRRect(borderRadius: radius, child: panel);
    }
    // 投影必须画在裁剪层外面，否则会被 ClipRRect 一起裁掉。
    if (shadows != null && shadows!.isNotEmpty) {
      panel = DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
        child: panel,
      );
    }
    return panel;
  }
}
