import 'package:flutter/material.dart';

import 'ink_tokens.dart';

/// 水墨页面转场：参考 Android 17 的「容器后退 + 弹性入场」。
///
/// - 新页面：淡入 + 自下 3% 上移 + 0.96→1 的回弹缩放；
/// - 被覆盖页面：缩小到 0.94 并压暗，形成层级后退感；
/// - 退出沿用反向曲线，快速收回，不回弹，避免拖影。
///
/// 由 [AppTheme] 注入 `PageTransitionsTheme`，业务侧照常使用
/// `MaterialPageRoute`；iOS 保留系统横滑返回。
class InkPageTransitionsBuilder extends PageTransitionsBuilder {
  const InkPageTransitionsBuilder();

  /// 二级路由的不透明背景（启动时注入，与全局背景保持一致）。
  /// 有它之后新页面整体不透明，过渡期不会透出底页内容形成残影。
  static Widget Function(BuildContext context)? backdropBuilder;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 首屏不做入场动画，但被二级页覆盖时同样后退，形成层级感。
    if (route.isFirst) {
      return _InkCoverTransition(
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    }
    return _InkRouteTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// 二级页路由：入场 200ms、退出 120ms，返回更干脆，减少等待感。
class InkPageRoute<T> extends MaterialPageRoute<T> {
  InkPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);
}

/// 被覆盖时的「容器后退」：缩小并压暗。
class _InkCoverTransition extends StatelessWidget {
  const _InkCoverTransition({
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cover = CurvedAnimation(
      parent: secondaryAnimation,
      curve: InkMotion.standard,
      reverseCurve: Curves.easeInCubic,
    );
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 0.94).animate(cover),
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0.70).animate(cover),
        child: child,
      ),
    );
  }
}

class _InkRouteTransition extends StatelessWidget {
  const _InkRouteTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: InkMotion.decelerate,
      reverseCurve: Curves.easeInCubic,
    );
    // 只驱动缩放，允许轻微越界形成回弹。
    final spring = CurvedAnimation(
      parent: animation,
      curve: InkMotion.spring,
      reverseCurve: Curves.easeInCubic,
    );

    // 内容层：上移 + 回弹缩放。
    // 不做整体淡入：路由已铺不透明背景，淡入会让页面先白一下再显内容。
    Widget content = SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.03),
        end: Offset.zero,
      ).animate(enter),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(spring),
        child: child,
      ),
    );
    // 背景层：立即铺满且不参与淡入，保证新页面整体不透明。
    final backdrop = InkPageTransitionsBuilder.backdropBuilder?.call(context);
    if (backdrop != null) {
      content = Stack(
        fit: StackFit.expand,
        children: [backdrop, content],
      );
    }

    // 被覆盖时再叠加一层容器后退。
    return _InkCoverTransition(
      secondaryAnimation: secondaryAnimation,
      child: content,
    );
  }
}
