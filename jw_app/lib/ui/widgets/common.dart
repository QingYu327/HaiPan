import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/data_providers.dart';
import '../../theme/ink_page_transition.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../../util/term_utils.dart';
import '../login/login_page.dart';
import 'app_icons.dart';
import 'ink_notice.dart';

/// 各作用域是否已由用户手动选择过学期（置位后不再自动回退）
final manualTermSelectionProvider = StateProvider.family<bool, String>(
  (ref, scope) => false,
);

/// 本次会话各作用域已连续自动回退的次数。
/// 教务持续返回空（或接口异常被当成空）时最多退两学期，
/// 避免一路退到入学学期并把用户留在多年前的旧数据上。
final _autoFallbackSteps = <String, int>{};
const int _maxAutoFallbackSteps = 2;

/// 当前学期有数据时调用，清掉连续回退计数，避免以后新学期的首次回退被历史次数挡住。
void resetAutoFallback(String scope) => _autoFallbackSteps[scope] = 0;

/// 学期无数据时自动回退到上一学期（成绩/考试用）。
/// 仅当用户尚未手动选择过学期时才回退；用户手动选回最新学期后可停留查看。
void autoFallbackTerm(WidgetRef ref, String scope) {
  if (ref.read(manualTermSelectionProvider(scope))) return; // 已手动选择
  final steps = _autoFallbackSteps[scope] ?? 0;
  if (steps >= _maxAutoFallbackSteps) {
    AppLog.w('学期回退', '$scope 已连续回退 $steps 次仍无数据，停止自动回退');
    return;
  }
  final current = ref.read(termProvider(scope));
  final enrollment = ref.read(enrollmentYearProvider);
  final terms = TermUtils.availableTerms(earliest: enrollment);
  final idx = terms.indexWhere(
    (t) => t.xnm == current.xnm && t.xqm == current.xqm,
  );
  if (idx < 0 || idx >= terms.length - 1) return; // 已是最早学期，不回退
  final earlier = terms[idx + 1];
  _autoFallbackSteps[scope] = steps + 1;
  AppLog.w('学期回退', '$scope ${current.shortLabel} 无数据 → ${earlier.shortLabel}');
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(termProvider(scope).notifier).state = earlier;
  });
}

/// 错误视图（带重试）
class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const ErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    // 不把 Dio/HTTP 等底层错误码直接抛给用户，详细原因统一进日志页排查。
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.cloudOff,
              size: 48,
              color: context.ink.secondaryLabel,
            ),
            const SizedBox(height: 12),
            Text(
              '暂时无法获取数据',
              textAlign: TextAlign.center,
              style: context.tsBodyStrong,
            ),
            const SizedBox(height: 6),
            Text(
              '网络或校园服务响应较慢，请稍后重试',
              textAlign: TextAlign.center,
              style: context.tsCaption.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空状态
class EmptyView extends StatelessWidget {
  final String text;
  const EmptyView(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.inbox, size: 48, color: context.ink.secondaryLabel),
          const SizedBox(height: 12),
          Text(
            text,
            style: context.tsBody.copyWith(
              color: context.scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 游客未登录且无可读缓存数据时的友好占位（首次使用引导去登录），
/// 避免把接口报错代码原样暴露给用户。
class GuestEmptyView extends ConsumerWidget {
  final String message;
  const GuestEmptyView({super.key, this.message = '首次使用请先登录获取数据'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.lock, size: 48, color: context.ink.secondaryLabel),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.tsBodyStrong,
            ),
            const SizedBox(height: 6),
            Text(
              '登录后即可查看，离线缓存数据也可在游客模式下浏览',
              textAlign: TextAlign.center,
              style: context.tsCaption.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                InkPageRoute(
                  builder: (_) => const LoginPage(showGuestButton: false),
                ),
              ),
              icon: const Icon(AppIcons.login, size: 18),
              label: const Text('去登录'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 加载中：呼吸光晕 + 文案，替代只有转圈圈的干等。
class InkLoadingView extends StatefulWidget {
  const InkLoadingView({super.key, this.message = '正在获取数据…'});

  final String message;

  @override
  State<InkLoadingView> createState() => _InkLoadingViewState();
}

class _InkLoadingViewState extends State<InkLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  late final Animation<double> _glow = Tween<double>(begin: 0.10, end: 0.26)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                FadeTransition(
                  opacity: _glow,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: InkSpacing.l),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Opacity(
              opacity: 0.55 + 0.35 * _c.value,
              child: Text(widget.message, style: context.tsCaption),
            ),
          ),
        ],
      ),
    );
  }
}

/// 首次加载失败保护：先保持加载动画并自动重试，多次仍失败才给友好提示。
///
/// 冷启动时通道/会话可能还在建立，请求很快失败；直接把异常码显示出来
/// 会让用户以为 App 坏了，这里用加载动画遮住这段过渡时间。
class RetryLoadView extends StatefulWidget {
  const RetryLoadView({
    super.key,
    required this.onRetry,
    this.message = '正在重新连接教务系统…',
    this.autoRetries = 2,
    this.firstDelay = const Duration(milliseconds: 900),
  });

  final Future<void> Function() onRetry;
  final String message;
  final int autoRetries;
  final Duration firstDelay;

  @override
  State<RetryLoadView> createState() => _RetryLoadViewState();
}

class _RetryLoadViewState extends State<RetryLoadView> {
  Timer? _timer;
  int _attempts = 0;
  bool _busy = false;
  bool _giveUp = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    final delay = widget.firstDelay + Duration(milliseconds: 1500 * _attempts);
    _timer = Timer(delay, _run);
  }

  Future<void> _run() async {
    if (!mounted || _busy) return;
    if (_attempts >= widget.autoRetries) {
      setState(() => _giveUp = true);
      return;
    }
    _busy = true;
    if (mounted) setState(() {});
    try {
      await widget.onRetry();
    } catch (_) {
      // 失败由下一次调度继续重试
    }
    if (!mounted) return;
    _busy = false;
    _attempts++;
    if (_attempts >= widget.autoRetries) {
      setState(() => _giveUp = true);
    } else {
      setState(() {});
      _schedule();
    }
  }

  void _manualRetry() {
    setState(() {
      _giveUp = false;
      _attempts = 0;
      _busy = false;
    });
    _schedule();
  }

  @override
  Widget build(BuildContext context) {
    if (!_giveUp) {
      return InkLoadingView(
        message: _busy || _attempts > 0 ? '网络较慢，正在重试连接…' : widget.message,
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.cloudOff, size: 48, color: context.ink.secondaryLabel),
            const SizedBox(height: 12),
            Text('暂时无法获取数据', style: context.tsBodyStrong),
            const SizedBox(height: 6),
            Text(
              '网络或校园服务响应较慢，请稍后重试',
              textAlign: TextAlign.center,
              style: context.tsCaption.copyWith(
                color: context.scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _manualRetry,
              icon: const Icon(AppIcons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

const loadingView = InkLoadingView();

/// 学期选择器（下拉菜单，写入页面独立 termProvider）
class TermPickerButton extends ConsumerWidget {
  final String scope; // 学期作用域：timetable / grade / exam / academic
  const TermPickerButton({super.key, required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = ref.watch(termProvider(scope));
    // 只显示入学以后的学期（按学号前 4 位判定）
    final terms = TermUtils.availableTerms(
      earliest: ref.watch(enrollmentYearProvider),
    );
    return InkSelect<Term>(
      value: term,
      variant: InkSelectVariant.pill,
      triggerLabel: term.shortLabel,
      options: [
        for (final t in terms) InkSelectOption(value: t, label: t.label),
      ],
      onChanged: (t) {
        // 用户手动选择学期：标记为已手动，后续不再自动回退（可停留查看空学期）
        ref.read(termProvider(scope).notifier).state = t;
        ref.read(manualTermSelectionProvider(scope).notifier).state = true;
        _autoFallbackSteps[scope] = 0;
        AppLog.d('学期', '$scope 切换为 ${t.shortLabel}');
        showInkToast(context, '已切换到 ${t.shortLabel}');
      },
    );
  }
}

/// 下拉选项：值 + 展示文案
class InkSelectOption<T> {
  const InkSelectOption({required this.value, required this.label});

  final T value;
  final String label;
}

enum InkSelectVariant {
  /// 页面标题右侧的小胶囊
  pill,

  /// 表单/卡片内的整行输入框
  field,
}

/// 水墨风下拉选择：触发器与弹出菜单统一取主题令牌，
/// 菜单行高 46、选中打勾、圆角 16 + 发丝描边，最多滚动 5 行左右。
class InkSelect<T> extends StatefulWidget {
  const InkSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.variant = InkSelectVariant.field,
    this.placeholder = '请选择',
    this.triggerLabel,
  });

  final T? value;
  final List<InkSelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final InkSelectVariant variant;
  final String placeholder;

  /// 触发器上显示的短文案（如「2026-上」）；为空时用选中项完整文案。
  final String? triggerLabel;

  @override
  State<InkSelect<T>> createState() => _InkSelectState<T>();
}

class _InkSelectState<T> extends State<InkSelect<T>> {
  // 挂在触发器外层，用于计算菜单的锚点位置
  final GlobalKey _anchorKey = GlobalKey();

  String get _label {
    for (final o in widget.options) {
      if (o.value == widget.value) return o.label;
    }
    return widget.placeholder;
  }

  /// 触发器：背景由 Material 承载，涟漪层向内缩 3dp，
  /// 这样圆角涟漪不会被背景色盖住，也能与背景边缘区分开。
  Widget _trigger(BuildContext context) {
    final scheme = context.scheme;
    final rippleRadius = BorderRadius.circular(InkRadius.control - 2);
    switch (widget.variant) {
      case InkSelectVariant.pill:
        return Material(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(InkRadius.control),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: InkWell(
              borderRadius: rippleRadius,
              onTap: _openMenu,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: InkSpacing.m - 3,
                  vertical: InkSpacing.s - 3,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.triggerLabel ?? _label,
                      style: context.tsCaption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: InkSpacing.xs),
                    Icon(
                      AppIcons.expandMore,
                      size: 18,
                      color: scheme.onSecondaryContainer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      case InkSelectVariant.field:
        return Material(
          color: context.ink.groupedBackground,
          borderRadius: BorderRadius.circular(InkRadius.control),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: InkWell(
                borderRadius: rippleRadius,
                onTap: _openMenu,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: InkSpacing.m - 3,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tsBody,
                        ),
                      ),
                      const SizedBox(width: InkSpacing.xs),
                      Icon(
                        AppIcons.expandMore,
                        size: 18,
                        color: context.ink.secondaryLabel,
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

  Future<void> _openMenu() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || overlayBox == null) return;

    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final overlaySize = overlayBox.size;
    final triggerRight = origin.dx + box.size.width;
    final menuTop = origin.dy + box.size.height + 6;

    // 触发器明显靠近右边缘时菜单右对齐，其余（含居中的整行输入框）左对齐，
    // 避免菜单缩在输入框右侧、看起来没对齐。1px 容差用于抵消浮点误差。
    final nearRight = origin.dx > overlaySize.width - triggerRight + 1;
    final position = RelativeRect.fromLTRB(
      origin.dx,
      menuTop,
      overlaySize.width - (nearRight ? triggerRight : origin.dx),
      overlaySize.height - menuTop,
    );

    final scheme = context.scheme;
    final ink = context.ink;
    final selected = await showMenu<T>(
      context: context,
      position: position,
      initialValue: widget.value,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.16),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      constraints: const BoxConstraints(
        minWidth: 232,
        maxWidth: 336,
        maxHeight: 320,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(InkRadius.card),
        side: BorderSide(color: ink.hairline, width: InkStroke.hairline),
      ),
      popUpAnimationStyle: const AnimationStyle(
        duration: InkMotion.normal,
        reverseDuration: InkMotion.fast,
        curve: InkMotion.decelerate,
        reverseCurve: Curves.easeInCubic,
      ),
      items: [
        for (final o in widget.options)
          _InkMenuEntry<T>(
            value: o.value,
            label: o.label,
            selected: o.value == widget.value,
          ),
      ],
    );
    if (selected != null && selected != widget.value) {
      widget.onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _anchorKey,
      child: Semantics(button: true, child: _trigger(context)),
    );
  }
}

/// 菜单行：用自定义 [PopupMenuEntry] 代替 [PopupMenuItem]，
/// 关闭系统整行直角高亮，改由行内自绘「圆角 + 内缩」的涟漪与选中底色。
class _InkMenuEntry<T> extends PopupMenuEntry<T> {
  const _InkMenuEntry({
    required this.value,
    required this.label,
    required this.selected,
  });

  final T value;
  final String label;
  final bool selected;

  @override
  double get height => 46;

  /// 返回 false：不参与系统 highlightColor 整行高亮
  @override
  bool represents(T? value) => false;

  @override
  State<_InkMenuEntry<T>> createState() => _InkMenuEntryState<T>();
}

class _InkMenuEntryState<T> extends State<_InkMenuEntry<T>> {
  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final radius = BorderRadius.circular(InkRadius.control - 2);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: InkSpacing.xs,
        vertical: 1,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: () => Navigator.pop(context, widget.value),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: InkSpacing.s + 2),
            decoration: widget.selected
                ? BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: radius,
                  )
                : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tsBody.copyWith(
                      color: widget.selected
                          ? scheme.primary
                          : scheme.onSurface,
                      fontWeight: widget.selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(width: InkSpacing.s),
                SizedBox(
                  width: 20,
                  child: widget.selected
                      ? Icon(AppIcons.check, size: 18, color: scheme.primary)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 下拉刷新容器。
///
/// - [child] 是滚动组件时（默认）：直接包一层 `RefreshIndicator`；
/// - [fill] 为 true：把非滚动内容（空态/错误态）撑满一屏，保证仍可下拉。
class InkRefresh extends StatelessWidget {
  const InkRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.fill = false,
    this.successMessage = '已刷新',
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final bool fill;

  /// 刷新成功后的灵动岛文案，各页面可换成更具体的反馈词。
  final String successMessage;

  /// 统一刷新反馈：完成后顶部灵动岛提示，失败给出错误提示。
  Future<void> _run(BuildContext context) async {
    try {
      await onRefresh();
      if (context.mounted) showInkToast(context, successMessage);
    } catch (_) {
      if (context.mounted) {
        showInkToast(context, '刷新失败，请稍后重试', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _run(context),
      color: context.scheme.primary,
      backgroundColor: context.scheme.surface,
      child: fill
          ? LayoutBuilder(
              builder: (context, constraints) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: constraints.maxHeight, child: child),
                ],
              ),
            )
          : child,
    );
  }
}
