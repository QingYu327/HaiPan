import 'dart:async';
import 'dart:ui' show lerpDouble;

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

class _DownloadIslandNoticeState extends State<_DownloadIslandNotice> {
  final ValueNotifier<UpdateDownloadState> _state =
      UpdateDownloader.instance.state;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onState);
    _onState();
  }

  void _onState() {
    final st = _state.value;
    if (st.status == UpdateDownloadStatus.running) {
      _hideTimer?.cancel();
      _hideTimer = null;
      return;
    }
    _hideTimer ??= Timer(const Duration(milliseconds: 1800), () {
      InkNotice.removeDownloadIsland();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _state.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 2,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: ValueListenableBuilder<UpdateDownloadState>(
            valueListenable: _state,
            builder: (context, st, _) {
              final running = st.status == UpdateDownloadStatus.running;
              final success = st.status == UpdateDownloadStatus.success;
              final pct = st.total > 0
                  ? (st.progress * 100).toStringAsFixed(0)
                  : null;
              final text = switch (st.status) {
                UpdateDownloadStatus.running =>
                  pct == null ? '正在连接下载…' : '正在下载 $pct%',
                UpdateDownloadStatus.success => '下载完成',
                UpdateDownloadStatus.failed => '下载失败',
                UpdateDownloadStatus.idle => '下载已取消',
              };
              final accent = success
                  ? InkColors.successDark
                  : st.status == UpdateDownloadStatus.failed
                      ? InkColors.dangerDark
                      : InkColors.infoDark;

              return Container(
                constraints: BoxConstraints(
                  minWidth: 168,
                  maxWidth:
                      MediaQuery.sizeOf(context).width - InkSpacing.xxl * 2,
                ),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xF5101A20),
                  borderRadius: BorderRadius.circular(24),
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
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            success
                                ? AppIcons.success
                                : st.status == UpdateDownloadStatus.failed
                                    ? AppIcons.error
                                    : AppIcons.download,
                            size: 15,
                            color: accent,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              text,
                              maxLines: 1,
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
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: running
                            ? (st.total > 0 ? st.progress : null)
                            : 1,
                        minHeight: 2.5,
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        color: accent,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
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
void showInkToast(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  showInkNotice(
    context,
    message,
    tone: error ? InkTone.danger : InkTone.info,
  );
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
    final collapsedH =
        (scaler.scale(13) * 2.4 + 12).clamp(38.0, 50.0).toDouble();

    final tp = _measure(widget.message, maxW - 80, _collapsedStyle,
        textScaler: scaler);
    final collapsedW =
        (collapsedH + 16 + 8 + tp.width + 26).clamp(collapsedH, maxW).toDouble();
    final expandedW = (collapsedW < 300 ? 300.0 : collapsedW)
        .clamp(collapsedH, maxW)
        .toDouble();

    final bodyTp = _measure(widget.message, expandedW - 32, _bodyStyle,
        maxLines: 4, textScaler: scaler);
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
                    style: (Theme.of(context).textTheme.bodyMedium ??
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
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
                                            color: color),
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
                                                color: Colors.white
                                                    .withValues(alpha: 0.62),
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
                                          style:
                                              _bodyStyle.copyWith(color: color),
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
                                                      horizontal: 10),
                                              minimumSize:
                                                  const Size(0, 30),
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
