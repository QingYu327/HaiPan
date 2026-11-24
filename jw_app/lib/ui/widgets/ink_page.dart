import 'package:flutter/material.dart';

import '../../theme/ink_tokens.dart';
import 'app_icons.dart';
import 'ink_panel.dart';

/// 标准页面骨架：透明底（由 InkBackground 画），大标题 + 可选副标题，
/// 内容滚动、底部自动避让悬浮胶囊导航。
class InkPageScaffold extends StatelessWidget {
  const InkPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.children = const [],
    this.body,
    this.fab,
    this.showBack = false,
    this.scrollable = true,
    this.padding,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  /// 填充标题下方剩余高度的主体（与 [children] 二选一，异步页面用）。
  final Widget? body;
  final Widget? fab;

  /// 二级页标记：显示返回按钮（左缘手势返回仍保留）。
  final bool showBack;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;

  /// 固定在底部的操作条（会叠在导航之上）。
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    // 二级页统一用左上角大标题，操作按钮与标题同一行右侧，
    // 不再额外保留一条只有按钮的空 AppBar。
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: title,
          subtitle: subtitle,
          actions: actions,
          // 小窗/分屏/自由窗口下系统返回手势可能被窗口管理器占用，
          // 始终给二级页一个可见的返回按钮兜底。
          leading: showBack
              ? IconButton(
                  tooltip: '返回',
                  icon: const Icon(AppIcons.back, size: 22),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
        ),
        if (body != null) Expanded(child: body!) else ...children,
      ],
    );
    final fixed = body != null || !scrollable;

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      // 有底部操作条时不延伸 body，避免列表最后一项被按钮压住；
      // 无底部条时铺到底，让内容从悬浮胶囊底下穿过。
      extendBody: bottom == null,
      body: SafeArea(
        top: true,
        bottom: false,
        child: fixed
            // 固定高度页（异步列表/表单）：只留左右与顶部内边距，
            // 让内容铺到手势条，滚动时从悬浮胶囊底下穿过（毛玻璃才有效果）；
            // 底部避让由各页自己的列表 padding 负责。
            ? Padding(
                padding: (padding ?? inkPagePadding(context))
                    .resolve(Directionality.of(context))
                    .copyWith(bottom: 0),
                child: content,
              )
            : SingleChildScrollView(
                primary: false,
                padding: padding ?? inkPagePadding(context),
                child: content,
              ),
      ),
      floatingActionButton: fab == null
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: _navSpace(context)),
              child: fab,
            ),
      bottomNavigationBar: bottom == null
          ? null
          : DecoratedBox(
              // 底部操作条铺满屏宽并压到手势条，避免透出背景纹理显得零碎
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  context.ink.cardFill,
                  context.scheme.surface,
                ),
                border: Border(
                  top: BorderSide(
                    color: context.ink.hairline,
                    width: InkStroke.hairline,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    InkSpacing.l,
                    InkSpacing.s,
                    InkSpacing.l,
                    InkSpacing.l,
                  ),
                  child: bottom,
                ),
              ),
            ),
    );

    return showBack ? _EdgeBackSwipe(child: scaffold) : scaffold;
  }

  static double _navSpace(BuildContext context) {
    final metrics = InkNavMetrics.maybeOf(context);
    if (metrics != null && metrics.visible) return metrics.bottomInset;
    return MediaQuery.paddingOf(context).bottom + InkSpacing.l;
  }
}

/// 左缘横滑返回：从屏幕左侧 32dp 内起手，右滑超过屏宽 22%
/// 或快速甩动即返回，拖拽时页面跟手轻微位移。
class _EdgeBackSwipe extends StatefulWidget {
  const _EdgeBackSwipe({required this.child});

  final Widget child;

  @override
  State<_EdgeBackSwipe> createState() => _EdgeBackSwipeState();
}

class _EdgeBackSwipeState extends State<_EdgeBackSwipe> {
  static const double _edgeWidth = 32;
  bool _fromEdge = false;
  double _dx = 0;

  void _reset() {
    if (_dx == 0 && !_fromEdge) return;
    setState(() {
      _fromEdge = false;
      _dx = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _fromEdge = details.globalPosition.dx <= _edgeWidth;
        if (_fromEdge) setState(() => _dx = 0);
      },
      onHorizontalDragUpdate: (details) {
        if (!_fromEdge) return;
        setState(() => _dx = (_dx + details.delta.dx).clamp(0.0, width));
      },
      onHorizontalDragEnd: (details) {
        if (!_fromEdge) return;
        final velocity = details.primaryVelocity ?? 0;
        final shouldPop = _dx > width * 0.22 || (velocity > 700 && _dx > 24);
        _reset();
        if (shouldPop) Navigator.of(context).maybePop();
      },
      onHorizontalDragCancel: _reset,
      child: Transform.translate(
        offset: Offset(_dx * 0.3, 0),
        child: widget.child,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: InkSpacing.m,
        bottom: InkSpacing.l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: InkSpacing.xs),
              ],
              Expanded(
                child: Text(
                  title,
                  style: InkTextStyles.display.copyWith(
                    color: context.scheme.onSurface,
                  ),
                ),
              ),
              ...actions,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: InkSpacing.s),
            Text(subtitle!, style: context.tsCaption),
          ],
        ],
      ),
    );
  }
}

/// 区块标题：小号标签 + 可选右侧动作。标题在卡片外，卡内不放标题栏。
class InkSectionHeader extends StatelessWidget {
  const InkSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      InkSpacing.xs,
      InkSpacing.l,
      InkSpacing.xs,
      InkSpacing.s,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tsSection),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: context.tsCaption),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 内容卡片：半透明填充 + hairline 描边 + 极淡阴影，圆角 16。
class InkCard extends StatelessWidget {
  const InkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(InkSpacing.l),
    this.onTap,
    this.tone,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// 仅用于「提示卡」着色，普通内容卡留 null。
  final InkTone? tone;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final tint = tone == null ? null : inkToneColor(context, tone!);
    final content = Padding(padding: padding, child: child);

    return Padding(
      padding: margin,
      child: Container(
        decoration: BoxDecoration(
          color: tint == null
              ? ink.cardFill
              : Color.alphaBlend(tint.withValues(alpha: 0.08), ink.cardFill),
          borderRadius: BorderRadius.circular(InkRadius.card),
          border: Border.all(
            color: tint == null ? ink.hairline : tint.withValues(alpha: 0.35),
            width: InkStroke.hairline,
          ),
          boxShadow: InkGlass.cardShadows(context.isDark),
        ),
        child: onTap == null
            ? content
            : Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(InkRadius.card),
                  child: content,
                ),
              ),
      ),
    );
  }
}

/// 统一的图标徽标：36 圆角方块 + 10% 色调底 + 20 图标。
/// 信息卡、入口行、状态卡都用它，避免各处图标大小/底色不一致。
class InkIconBadge extends StatelessWidget {
  const InkIconBadge({
    super.key,
    required this.icon,
    this.tone,
    this.size = 36,
  });

  final IconData icon;
  final InkTone? tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = tone == null
        ? context.scheme.onSurfaceVariant
        : inkToneColor(context, tone!);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: size * 0.56, color: tint),
    );
  }
}

/// 设置项：图标 + 标题 + 可选副标题 + 右侧控件；组内自动画分隔线。
class InkSettingTile extends StatelessWidget {
  const InkSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconTone,
    this.titleTone,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final InkTone? iconTone;

  /// 仅用于危险项（退出登录等）的标题着色。
  final InkTone? titleTone;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 组内最后一项传 false。
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: InkSpacing.l,
                vertical: InkSpacing.m,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    InkIconBadge(icon: icon!, tone: iconTone),
                    const SizedBox(width: InkSpacing.m),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: titleTone == null
                              ? context.tsBody
                              : context.tsBody.copyWith(
                                  color: inkToneColor(context, titleTone!),
                                ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: context.tsCaption),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: InkSpacing.m),
                    trailing!,
                  ] else if (onTap != null)
                    Icon(
                      AppIcons.chevronRight,
                      size: 20,
                      color: context.ink.secondaryLabel,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: EdgeInsets.only(
              left: icon == null ? InkSpacing.l : InkSpacing.l + 48,
              right: InkSpacing.l,
            ),
            child: Divider(height: 1, thickness: InkStroke.hairline),
          ),
      ],
    );
  }
}

/// 行内提示条：说明 / 风险 / 成功反馈。
class InkBanner extends StatelessWidget {
  const InkBanner({
    super.key,
    required this.message,
    this.tone = InkTone.info,
    this.icon,
    this.action,
  });

  final String message;
  final InkTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = inkToneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: InkSpacing.m,
        vertical: InkSpacing.s + 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(InkRadius.control),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
          width: InkStroke.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? AppIcons.info, size: 18, color: color),
          const SizedBox(width: InkSpacing.s),
          Expanded(
            child: Text(
              message,
              style: context.tsCaption.copyWith(color: color),
            ),
          ),
          if (action != null) ...[const SizedBox(width: InkSpacing.s), action!],
        ],
      ),
    );
  }
}

/// 单个统计值：数值 + 说明。
class InkStat {
  const InkStat(this.value, this.label, {this.tone});

  final String value;
  final String label;
  final InkTone? tone;
}

/// 一行统计卡：所有格子等高（IntrinsicHeight + stretch），禁止一高一矮。
class InkStatsRow extends StatelessWidget {
  const InkStatsRow({
    super.key,
    required this.stats,
    this.showDividers = true,
    this.valueSize = 20,
  });

  final List<InkStat> stats;
  final bool showDividers;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0 && showDividers)
              VerticalDivider(
                width: 1,
                thickness: InkStroke.hairline,
                color: ink.hairline,
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: InkSpacing.xs,
                  vertical: InkSpacing.xs,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      stats[i].value,
                      maxLines: 1,
                      style: context.tabular.copyWith(
                        fontSize: valueSize,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: stats[i].tone == null
                            ? context.scheme.onSurface
                            : inkToneColor(context, stats[i].tone!),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stats[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: InkTextStyles.label.copyWith(
                        color: ink.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 小标签：低饱和底 + 语义色字，圆角胶囊。入口行、状态、倒计时统一用它。
class InkTag extends StatelessWidget {
  const InkTag({super.key, required this.text, this.tone = InkTone.neutral});

  final String text;
  final InkTone tone;

  @override
  Widget build(BuildContext context) {
    final color = inkToneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: InkSpacing.s,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(InkRadius.pill),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: InkTextStyles.label.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 底部弹层（圆角 20 + 顶部拖把手）。
Future<void> showInkSheet(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // 弹层进出：安卓 17 式长尾减速，收起时更快，避免拖沓。
    sheetAnimationStyle: const AnimationStyle(
      duration: InkMotion.sheet,
      reverseDuration: InkMotion.fast,
      curve: InkMotion.decelerate,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: InkGlassPanel(
        fill: context.scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(InkRadius.sheet + 4),
        ),
        padding: const EdgeInsets.fromLTRB(
          InkSpacing.l,
          InkSpacing.s,
          InkSpacing.l,
          InkSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.tsSection),
            const SizedBox(height: InkSpacing.l),
            child,
          ],
        ),
      ),
    ),
  );
}
