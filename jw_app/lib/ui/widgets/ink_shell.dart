import 'package:flutter/material.dart';

import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import 'ink_panel.dart';

/// 一个底部导航项。
class InkNavItem {
  const InkNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 悬浮胶囊导航外壳。
///
/// - `extendBody`：内容铺到底边，胶囊浮在上面；
/// - 胶囊放在 `bottomNavigationBar` 槽位（不是 Stack 浮层），避免键盘/系统栏变化留残影；
/// - 高度 72、左右与底部留白各 16、全圆角、透明液体玻璃 + 柔和投影；
/// - 切 tab：复刻 esplock —— 新页按方向横滑 6%、淡入 0.2→1 并 0.985 缩放；
/// - 导航指示器与页面切换同步，点击即朝目标滑动。
class InkAppShell extends StatefulWidget {
  const InkAppShell({
    super.key,
    required this.items,
    required this.pages,
    this.initialIndex = 0,
    this.onChanged,
    this.secondaryPage,
    this.background,
  }) : assert(items.length == pages.length, '导航项与页面数量必须一致');

  final List<InkNavItem> items;
  final List<Widget> pages;
  final int initialIndex;
  final ValueChanged<int>? onChanged;

  /// 二级页覆盖层（例如详情页）。非空时导航收起。
  final Widget? secondaryPage;

  /// 自定义背景（默认由全局外壳提供，一般不用传）。
  final Widget? background;

  @override
  State<InkAppShell> createState() => InkAppShellState();
}

class InkAppShellState extends State<InkAppShell>
    with SingleTickerProviderStateMixin {
  late int _index = widget.initialIndex;

  /// 导航指示器位置：与页面切换同步更新。
  late int _navIndex = widget.initialIndex;

  /// 当前页进场进度：0 不可见，1 完全显示（复刻 esplock 的 tab 动效）。
  late final AnimationController _tabAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  late final CurvedAnimation _fadeCurve = CurvedAnimation(
    parent: _tabAnim,
    curve: InkMotion.standard,
  );
  late final CurvedAnimation _slideCurve = CurvedAnimation(
    parent: _tabAnim,
    curve: InkMotion.emphasized,
  );
  late final CurvedAnimation _scaleCurve = CurvedAnimation(
    parent: _tabAnim,
    curve: InkMotion.emphasized,
  );

  /// 淡入 0.2→1，保留背景透出感。
  late final Animation<double> _fade =
      Tween<double>(begin: 0.2, end: 1).animate(_fadeCurve);

  /// 轻微缩放 0.985→1。
  late final Animation<double> _scale =
      Tween<double>(begin: 0.985, end: 1).animate(_scaleCurve);

  /// 已挂载过的页面。首次进入才构建，避免冷启动时 5 个页面同时拉数据。
  final Set<int> _visited = {};

  /// 切换方向：1 表示往右（新页从右侧滑入），-1 表示往左。
  int _direction = 1;

  /// 按方向横滑 6% 入场。
  Animation<Offset> get _slide => Tween<Offset>(
        begin: Offset(0.06 * _direction, 0),
        end: Offset.zero,
      ).animate(_slideCurve);

  int get index => _index;

  /// 供页面调用，例如「去设置」：`InkAppShell.of(context).goTo(2)`。
  static InkAppShellState of(BuildContext context) {
    final state = context.findAncestorStateOfType<InkAppShellState>();
    assert(state != null, '未找到 InkAppShell，请确认页面在 shell 内');
    return state!;
  }

  @override
  void initState() {
    super.initState();
    _visited.add(_index);
  }

  @override
  void dispose() {
    _fadeCurve.dispose();
    _slideCurve.dispose();
    _scaleCurve.dispose();
    _tabAnim.dispose();
    super.dispose();
  }

  void goTo(int index) {
    if (index == _index || index < 0 || index >= widget.pages.length) {
      return;
    }
    final direction = index > _index ? 1 : -1;
    // 直接切页并让新页进场：指示器与内容同步朝点击方向移动。
    setState(() {
      _direction = direction;
      _navIndex = index;
      _index = index;
      _visited.add(index);
    });
    widget.onChanged?.call(index);
    AppLog.d('导航', '切换到「${widget.items[index].label}」');
    _tabAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final navBottom = safeBottom > InkGlass.navBottomMargin
        ? safeBottom
        : InkGlass.navBottomMargin;
    final navVisible = widget.secondaryPage == null;
    final navInset = InkGlass.navHeight + navBottom;

    return InkNavMetrics(
      bottomInset: navInset,
      visible: navVisible,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        resizeToAvoidBottomInset: false,
        bottomNavigationBar: AnimatedSlide(
          duration: InkMotion.normal,
          curve: InkMotion.emphasized,
          offset: navVisible ? Offset.zero : const Offset(0, 1.4),
          child: AnimatedOpacity(
            duration: InkMotion.normal,
            opacity: navVisible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !navVisible,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  InkGlass.navMargin,
                  0,
                  InkGlass.navMargin,
                  navBottom,
                ),
                child: InkGlassPanel(
                  borderRadius: BorderRadius.circular(InkGlass.navRadius),
                  blur: InkGlass.navBlur,
                  liquid: true,
                  fill: context.ink.glassNavFill,
                  shadows: InkGlass.navShadows(context.isDark),
                  child: SizedBox(
                    height: InkGlass.navHeight,
                    child: Material(
                      type: MaterialType.transparency,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final scheme = context.scheme;
                          final itemW = constraints.maxWidth /
                              widget.items.length;
                          final pillW = itemW * 0.72;
                          final pill = DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  scheme.secondaryContainer
                                      .withValues(alpha: 0.92),
                                  scheme.secondaryContainer
                                      .withValues(alpha: 0.60),
                                ],
                              ),
                              borderRadius:
                                  BorderRadius.circular(InkRadius.pill),
                              border: Border.all(
                                color: Colors.white.withValues(
                                    alpha: context.isDark ? 0.10 : 0.55),
                                width: 0.8,
                              ),
                            ),
                          );
                          // 指示器停在选中项；切换时滑向下一个位置并轻微拉伸，
                          // 形成「液体被推过去」的连续反馈。
                          return TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: _navIndex.toDouble()),
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.easeOutBack,
                            child: pill,
                            builder: (context, v, pill) {
                              final travel =
                                  ((v - v.roundToDouble()).abs() * 2)
                                      .clamp(0.0, 1.0);
                              final w = pillW * (1 + 0.16 * travel);
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned(
                                    left: v * itemW + (itemW - w) / 2,
                                    top: 10,
                                    bottom: 10,
                                    width: w,
                                    child: pill!,
                                  ),
                                  Row(
                                    children: [
                                      for (var i = 0;
                                          i < widget.items.length;
                                          i++)
                                        _NavItem(
                                          item: widget.items[i],
                                          selected: i == _navIndex,
                                          onTap: () => goTo(i),
                                        ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            if (widget.background != null)
              Positioned.fill(child: widget.background!),
            Positioned.fill(
              child: Stack(
                children: [
                  for (var i = 0; i < widget.pages.length; i++)
                    Positioned.fill(
                      child: Offstage(
                        offstage: i != _index,
                        child: TickerMode(
                          enabled: i == _index,
                          // 仅当前页挂载进场动画，非当前页保持原状态。
                          // esplock 同款：按方向横滑 6% + 淡入 0.2→1 + 0.985 缩放。
                          child: !_visited.contains(i)
                              // 未访问过的页面先不构建，避免首屏并发拉取全部数据
                              ? const SizedBox.shrink()
                              : i == _index
                              ? SlideTransition(
                                  position: _slide,
                                  child: FadeTransition(
                                    opacity: _fade,
                                    child: ScaleTransition(
                                      scale: _scale,
                                      child: widget.pages[i],
                                    ),
                                  ),
                                )
                              : widget.pages[i],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.secondaryPage != null)
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: InkMotion.normal,
                  switchInCurve: InkMotion.standard,
                  child: widget.secondaryPage,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final InkNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Center(
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: InkMotion.fast,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: Tween<double>(begin: 0.72, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: InkMotion.emphasized,
                        ),
                      ),
                      child: FadeTransition(
                        opacity: CurvedAnimation(
                          parent: animation,
                          curve: InkMotion.standard,
                        ),
                        child: child,
                      ),
                    ),
                    child: Icon(
                      selected ? item.selectedIcon : item.icon,
                      key: ValueKey<bool>(selected),
                      size: 24,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: context.tsLabel.copyWith(
                      color: color,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

