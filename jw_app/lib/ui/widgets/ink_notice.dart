import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, lerpDouble;

import 'package:flutter/material.dart';

import '../../theme/ink_tokens.dart';
import '../../util/update_downloader.dart';
import 'app_icons.dart';

/// 顶部「灵动岛」通知：收起是药丸，点击展开看详情。
///
/// 通知统一走顶部，不用底部 SnackBar（会遮挡胶囊导航）。
class InkNotice {
  InkNotice._();

  static OverlayEntry? _entry;
  static OverlayEntry? _downloadEntry;

  /// 更新下载进度：顶部灵动岛常驻展示，跨页面可见，终止后自动收起。
  static void showDownloadIsland(BuildContext context) {
    if (_downloadEntry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final entry = OverlayEntry(builder: (_) => const _DownloadIslandNotice());
    _downloadEntry = entry;
    overlay.insert(entry);
  }

  static void removeDownloadIsland() {
    _downloadEntry?.remove();
    _downloadEntry = null;
  }

  static void show(
    BuildContext context,
    String message, {
    String? title,
    InkTone tone = InkTone.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry?.remove();
    _entry = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _IslandNotice(
        title: title,
        message: message,
        tone: tone,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: tone == InkTone.danger
            ? const Duration(seconds: 6)
            : duration,
        onDismiss: () {
          if (entry.mounted) entry.remove();
          if (identical(_entry, entry)) _entry = null;
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

/// 更新下载的常驻灵动岛：黑底药丸 + 百分比 + 底部细进度条。
/// 跟随 [UpdateDownloader] 状态自动更新，结束后短暂停留再收起。
class _DownloadIslandNotice extends StatefulWidget {
  const _DownloadIslandNotice();

  @override
  State<_DownloadIslandNotice> createState() => _DownloadIslandNoticeState();
}

class _DownloadIslandNoticeState extends State<_DownloadIslandNotice>
    with TickerProviderStateMixin {
  final ValueNotifier<UpdateDownloadState> _state =
      UpdateDownloader.instance.state;
  Timer? _hideTimer;

  /// 正在执行退场动画：避免重复触发，也避免新下载开始时被误收起。
  bool _closing = false;
  UpdateDownloadStatus? _lastStatus;

  /// 0 = 收起药丸，1 = 展开卡片；宽度/高度/内容共用一条曲线，避免直接切换子树造成跳变。
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: InkMotion.noticeExpand,
    reverseDuration: InkMotion.noticeCollapse,
  );

  /// 开始下载：药丸从上方轻微下落 + 淡入 + 缩放，避免突然出现。
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _enter,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.55),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
  late final Animation<double> _scaleIn = Tween<double>(
    begin: 0.92,
    end: 1,
  ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutBack));

  /// 下载结束/失败：轻微弹一下，提示结果已变化。
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  bool get _expanded => _morph.value > 0;

  void _toggle() {
    if (_expanded) {
      _morph.reverse();
    } else {
      _morph.forward();
    }
  }

  /// 单行文本宽度（用于收起态贴合文字）
  double _textWidth(String text, TextScaler scaler) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.15,
          letterSpacing: 0,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    return tp.width;
  }

  @override
  void initState() {
    super.initState();
    _lastStatus = _state.value.status;
    _state.addListener(_onState);
    _onState();
    _enter.forward();
  }

  void _onState() {
    final st = _state.value;
    final changed = _lastStatus != null && _lastStatus != st.status;
    _lastStatus = st.status;
    // 完成/失败时弹一下；取消（idle）不弹，直接按退场处理
    if (changed &&
        (st.status == UpdateDownloadStatus.success ||
            st.status == UpdateDownloadStatus.failed)) {
      _pop.forward(from: 0);
    }
    if (st.status == UpdateDownloadStatus.running) {
      _hideTimer?.cancel();
      _hideTimer = null;
      // 退场途中又开始了新下载：重新出现
      if (_closing) {
        _closing = false;
        _enter.forward();
      }
      return;
    }
    if (_hideTimer != null) return;
    // 展开查看详情时多留一会儿，避免刚点开就消失
    final delay = _expanded
        ? const Duration(milliseconds: 3600)
        : const Duration(milliseconds: 1800);
    _hideTimer = Timer(delay, _dismiss);
  }

  /// 先播放退场动画再移除；动画期间有新下载则放弃收起。
  Future<void> _dismiss() async {
    _hideTimer = null;
    if (_closing) return;
    _closing = true;
    try {
      await _enter.reverse();
    } catch (_) {}
    if (!mounted) return;
    if (_state.value.status == UpdateDownloadStatus.running) {
      _closing = false;
      _enter.forward();
      return;
    }
    InkNotice.removeDownloadIsland();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _state.removeListener(_onState);
    _morph.dispose();
    _enter.dispose();
    _pop.dispose();
    super.dispose();
  }

  static String _size(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return mb >= 100
        ? '${mb.toStringAsFixed(0)} MB'
        : '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 2,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: ValueListenableBuilder<UpdateDownloadState>(
          valueListenable: _state,
          builder: (context, st, _) {
            final running = st.status == UpdateDownloadStatus.running;
            final success = st.status == UpdateDownloadStatus.success;
            final failed = st.status == UpdateDownloadStatus.failed;
            final hasTotal = st.total > 0;
            final pctNum = hasTotal
                ? (st.progress * 100).toStringAsFixed(0)
                : null;
            final accent = success
                ? InkColors.successDark
                : failed
                ? InkColors.dangerDark
                : InkColors.infoDark;
            final icon = success
                ? AppIcons.success
                : failed
                ? AppIcons.error
                : AppIcons.download;
            final headline = switch (st.status) {
              UpdateDownloadStatus.running =>
                pctNum == null ? '正在连接下载…' : '正在下载 $pctNum%',
              UpdateDownloadStatus.success => '下载完成',
              UpdateDownloadStatus.failed => '下载失败',
              UpdateDownloadStatus.idle => '下载已取消',
            };
            final detail = switch (st.status) {
              UpdateDownloadStatus.running =>
                hasTotal
                    ? '${_size(st.downloaded)} / ${_size(st.total)}'
                    : '正在获取安装包…',
              UpdateDownloadStatus.success => '点击通知卡片可安装或查看详情',
              UpdateDownloadStatus.failed => st.error ?? '请检查网络后重试',
              UpdateDownloadStatus.idle => '已取消本次下载',
            };

            final mq = MediaQuery.of(context);
            final scaler = mq.textScaler;
            // 药丸左右只留 32，尽可能把「百分比 + 已下载/总大小」放进收起态
            final maxW = mq.size.width - InkSpacing.xxxl;
            // 收起态一屏展示：主文案 + 已下载/总大小（下载中才追加）
            final inlineSize = running && hasTotal
                ? '${_size(st.downloaded)} / ${_size(st.total)}'
                : '';
            final collapsedText = inlineSize.isEmpty
                ? headline
                : '$headline  ·  $inlineSize';
            // 文字宽度按主文案字重测量（偏大），再留 6px 余量，避免末尾出现省略号
            final textAvail = maxW - 54; // 左右内边距 32 + 图标 15 + 间距 7
            final textW = _textWidth(collapsedText, scaler) + 6;
            final wrapped = textW > textAvail;
            final collapsedW = wrapped ? maxW : 16 + 15 + 7 + textW + 16;
            final lineH = math.max(15.0, scaler.scale(13) * 1.15);
            final collapsedH = (10 + 11 + lineH * (wrapped ? 2 : 1))
                .clamp(36.0, 76.0)
                .toDouble();
            // 展开态：加宽以保证说明文字完整显示，高度预留两行，状态变化时不跳动
            final expandedW = math.min(300.0, maxW);
            final expandedH =
                12 + 13 + 10 + 6 + 8 + scaler.scale(11.5) * 1.3 * 2 + 14;

            return FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: ScaleTransition(
                  scale: _scaleIn,
                  child: AnimatedBuilder(
                    animation: _pop,
                    builder: (context, child) => Transform.scale(
                      // 完成/失败时 1 → 1.025 → 1 的轻微弹性
                      scale: 1 + 0.025 * math.sin(_pop.value * math.pi),
                      child: child,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggle,
                      child: Semantics(
                        button: true,
                        label: headline,
                        child: AnimatedBuilder(
                          animation: _morph,
                          builder: (context, _) {
                            // 展开/收起共用对称曲线，内容淡入淡出并轻微缩放
                            final t = Curves.easeInOutCubic.transform(
                              _morph.value,
                            );
                            final w = lerpDouble(collapsedW, expandedW, t)!;
                            final h = lerpDouble(collapsedH, expandedH, t)!;
                            final radius = lerpDouble(collapsedH / 2, 24, t)!;
                            final collapsedOpacity = ((1 - t) / 0.5).clamp(
                              0.0,
                              1.0,
                            );
                            final expandedOpacity = ((t - 0.4) / 0.6).clamp(
                              0.0,
                              1.0,
                            );

                            return TweenAnimationBuilder<Size>(
                              // 展开/收起过程中尺寸每帧都在变，直接跟随；
                              // 状态切换（下载中 → 完成/取消）时才做一次 240ms 平滑过渡
                              duration: _morph.isAnimating
                                  ? Duration.zero
                                  : const Duration(milliseconds: 240),
                              curve: Curves.easeOutCubic,
                              tween: Tween<Size>(end: Size(w, h)),
                              builder: (context, size, child) => Container(
                                width: size.width,
                                height: size.height,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: const Color(0xF5101A20),
                                  borderRadius: BorderRadius.circular(radius),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    width: InkStroke.hairline,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.22,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: child,
                              ),
                              child: Stack(
                                children: [
                                  // 收起态：保持最终尺寸排版，仅淡出，避免文字在变宽过程中重排
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: t > 0.5,
                                      child: Opacity(
                                        opacity: collapsedOpacity,
                                        child: Transform.scale(
                                          scale: 1 - 0.03 * t,
                                          child: OverflowBox(
                                            alignment: Alignment.topCenter,
                                            minWidth: collapsedW,
                                            maxWidth: collapsedW,
                                            minHeight: collapsedH,
                                            maxHeight: collapsedH,
                                            child: SizedBox(
                                              width: collapsedW,
                                              height: collapsedH,
                                              child: _collapsedBody(
                                                headline,
                                                inlineSize,
                                                icon,
                                                accent,
                                                wrapped ? 2 : 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 展开态：淡入 + 轻微放大，和药丸尺寸过渡同步
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      ignoring: t <= 0.5,
                                      child: Opacity(
                                        opacity: expandedOpacity,
                                        child: Transform.scale(
                                          scale: 0.94 + 0.06 * t,
                                          alignment: Alignment.topCenter,
                                          child: OverflowBox(
                                            alignment: Alignment.topCenter,
                                            minWidth: expandedW,
                                            maxWidth: expandedW,
                                            minHeight: expandedH,
                                            maxHeight: expandedH,
                                            child: SizedBox(
                                              width: expandedW,
                                              height: expandedH,
                                              child: _expandedBody(
                                                st,
                                                icon,
                                                accent,
                                                detail,
                                                running,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 收起态：主文案 + 已下载/总大小，宽度随内容（不为了进度条拉长药丸）
  Widget _collapsedBody(
    String headline,
    String inlineSize,
    IconData icon,
    Color accent,
    int maxLines,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 7),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: headline),
                  if (inlineSize.isNotEmpty)
                    TextSpan(
                      text: '  ·  $inlineSize',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                ],
              ),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.15,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 展开态：版本标题 + 进度条，百分比放在进度条右侧
  Widget _expandedBody(
    UpdateDownloadState st,
    IconData icon,
    Color accent,
    String detail,
    bool running,
  ) {
    final title = st.version.isEmpty ? '更新下载' : '海畔 v${st.version}';
    // 完成时补满进度条；取消/失败保留最后一次进度，不给出“假 100%”
    final progress = running
        ? (st.total > 0 ? st.progress : null)
        : st.status == UpdateDownloadStatus.success
        ? 1.0
        : (st.total > 0 ? st.progress : null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                // 进度更新是离散的（约 600ms 一次），这里补间到新值，
                // 避免进度条与百分比一格一格往前跳。
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: progress ?? 0),
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress == null ? null : value.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      color: accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: (progress ?? 0) * 100),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  progress == null ? '—' : '${value.round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    fontFeatures: [FontFeature.tabularFigures()],
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11.5,
              height: 1.3,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

void showInkNotice(
  BuildContext context,
  String message, {
  String? title,
  InkTone tone = InkTone.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  InkNotice.show(
    context,
    message,
    title: title,
    tone: tone,
    actionLabel: actionLabel,
    onAction: onAction,
    duration: duration,
  );
}

/// 兼容旧调用：`error: true` 等价于 danger 语义色。
void showInkToast(BuildContext context, String message, {bool error = false}) {
  showInkNotice(context, message, tone: error ? InkTone.danger : InkTone.info);
}

class _IslandNotice extends StatefulWidget {
  const _IslandNotice({
    required this.title,
    required this.message,
    required this.tone,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.onDismiss,
  });

  final String? title;
  final String message;
  final InkTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_IslandNotice> createState() => _IslandNoticeState();
}

class _IslandNoticeState extends State<_IslandNotice>
    with TickerProviderStateMixin {
  static const double _radiusCard = 26;

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: InkMotion.normal,
    reverseDuration: InkMotion.noticeCollapse,
  );
  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: InkMotion.noticeExpand,
    reverseDuration: InkMotion.noticeCollapse,
  );
  Timer? _timer;
  bool _closing = false;

  // 固定文本样式：仅用于布局测量与展示，不随构建重建
  static const _collapsedStyle = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.0,
    leadingDistribution: TextLeadingDistribution.even,
    decoration: TextDecoration.none,
  );
  static const _bodyStyle = TextStyle(
    color: Colors.white,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    height: 1.35,
    decoration: TextDecoration.none,
  );

  // 布局尺寸只在依赖变化时计算一次，避免动画每帧重排文本导致卡顿
  double _collapsedH = 44;
  double _collapsedW = 150;
  double _expandedW = 300;
  double _expandedH = 96;
  MediaQueryData? _layoutMq;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.of(context);
    if (identical(_layoutMq, mq)) return;
    _layoutMq = mq;
    _computeLayout(mq);
  }

  void _computeLayout(MediaQueryData mq) {
    final screenW = mq.size.width;
    final maxW = screenW - InkSpacing.xxl * 2;
    final scaler = mq.textScaler;
    final collapsedH = (scaler.scale(13) * 2.4 + 12)
        .clamp(38.0, 50.0)
        .toDouble();

    final tp = _measure(
      widget.message,
      maxW - 80,
      _collapsedStyle,
      textScaler: scaler,
    );
    final collapsedW = (collapsedH + 16 + 8 + tp.width + 26)
        .clamp(collapsedH, maxW)
        .toDouble();
    final expandedW = (collapsedW < 300 ? 300.0 : collapsedW)
        .clamp(collapsedH, maxW)
        .toDouble();

    final bodyTp = _measure(
      widget.message,
      expandedW - 32,
      _bodyStyle,
      maxLines: 4,
      textScaler: scaler,
    );
    final hasAction = widget.actionLabel != null && widget.onAction != null;
    final expandedH = (16 + 18 + 6 + bodyTp.height + (hasAction ? 38 : 0) + 16)
        .clamp(96.0, 220.0)
        .toDouble();

    _collapsedH = collapsedH;
    _collapsedW = collapsedW;
    _expandedW = expandedW;
    _expandedH = expandedH;
  }

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _armTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _intro.dispose();
    _expand.dispose();
    super.dispose();
  }

  void _armTimer([Duration? d]) {
    _timer?.cancel();
    _timer = Timer(d ?? widget.duration, () {
      if (_expand.value > 0) return; // 展开看详情时不自动关闭
      _close();
    });
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (_expand.value > 0) await _expand.reverse();
    await _intro.reverse();
    if (mounted) widget.onDismiss();
  }

  Future<void> _toggle() async {
    if (_expand.value > 0) {
      await _expand.reverse();
      if (mounted) _armTimer(const Duration(milliseconds: 2200));
    } else {
      _timer?.cancel();
      await _expand.forward();
    }
  }

  /// 通知挂在黑色底上，语义色取深色主题的亮色档保证对比度。
  Color get _toneColor => switch (widget.tone) {
    InkTone.success => InkColors.successDark,
    InkTone.warning => InkColors.warningDark,
    InkTone.danger => InkColors.dangerDark,
    InkTone.info => InkColors.infoDark,
    InkTone.neutral => Colors.white,
  };

  IconData get _icon => switch (widget.tone) {
    InkTone.success => AppIcons.success,
    InkTone.warning => AppIcons.warning,
    InkTone.danger => AppIcons.error,
    InkTone.info => AppIcons.info,
    InkTone.neutral => Icons.notifications_none_rounded,
  };

  TextPainter _measure(
    String text,
    double width,
    TextStyle style, {
    int maxLines = 1,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: width);
  }

  @override
  Widget build(BuildContext context) {
    final color = _toneColor;
    final hasAction = widget.actionLabel != null && widget.onAction != null;

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 2,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedBuilder(
          animation: Listenable.merge([_intro, _expand]),
          builder: (context, _) {
            final t = Curves.easeOutCubic.transform(_intro.value);
            final e = Curves.easeOutCubic.transform(_expand.value);
            final baseW = lerpDouble(_collapsedH, _collapsedW, t)!;
            final w = lerpDouble(baseW, _expandedW, e)!;
            final h = lerpDouble(_collapsedH, _expandedH, e)!;
            final radius = lerpDouble(_collapsedH / 2, _radiusCard, e)!;
            final collapsedOpacity =
                ((w - _collapsedH - 10) / 40).clamp(0.0, 1.0) * (1 - e);
            final expandedOpacity = t * e;

            return GestureDetector(
              onTap: _toggle,
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                button: true,
                label: widget.message,
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(
                    // 96% 墨黑，带一点青墨色相，和宣纸底拉开层次。
                    color: const Color(0xF5101A20),
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: InkStroke.hairline,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: DefaultTextStyle(
                    style:
                        (Theme.of(context).textTheme.bodyMedium ??
                                const TextStyle())
                            .copyWith(
                              color: Colors.white,
                              decoration: TextDecoration.none,
                            ),
                    child: Stack(
                      children: [
                        // 收起态：单行文字
                        Positioned.fill(
                          child: Opacity(
                            opacity: collapsedOpacity,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(_icon, size: 16, color: color),
                                    const SizedBox(width: 7),
                                    Flexible(
                                      child: Text(
                                        widget.message,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: _collapsedStyle.copyWith(
                                          color: color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 展开态：标题 + 完整说明 + 动作
                        Positioned.fill(
                          child: Opacity(
                            opacity: expandedOpacity,
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: _expandedH,
                              maxHeight: _expandedH,
                              child: SizedBox(
                                height: _expandedH,
                                child: Padding(
                                  padding: const EdgeInsets.all(InkSpacing.l),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(_icon, size: 15, color: color),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              widget.title ?? '通知',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.62,
                                                ),
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.3,
                                                decoration: TextDecoration.none,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Expanded(
                                        child: Text(
                                          widget.message,
                                          maxLines: 4,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: _bodyStyle.copyWith(
                                            color: color,
                                          ),
                                        ),
                                      ),
                                      if (hasAction)
                                        Align(
                                          alignment: Alignment.center,
                                          child: TextButton(
                                            onPressed: () {
                                              final action = widget.onAction!;
                                              _close();
                                              action();
                                            },
                                            style: TextButton.styleFrom(
                                              foregroundColor: color,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              minimumSize: const Size(0, 30),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: Text(
                                              widget.actionLabel!,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
