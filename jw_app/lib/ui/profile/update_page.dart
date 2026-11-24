import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/update_api.dart';
import '../../api/usage_api.dart';
import '../../providers/data_providers.dart';
import '../../theme/ink_tokens.dart';
import '../../util/apk_installer.dart';
import '../../util/app_log.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

/// 检查更新独立页：显示更新日志，提供下载安装按钮；装机后自动清除安装包
class UpdatePage extends ConsumerStatefulWidget {
  const UpdatePage({super.key});

  @override
  ConsumerState<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends ConsumerState<UpdatePage> {
  bool _done = false;
  String? _error;
  (String, String, String, String)? _result;

  bool _downloading = false;
  double _progress = 0;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // 更新黑名单用户：直接视为无更新
    try {
      final gates = await ref.read(featureGatesProvider.future);
      if (gates[UsageTracker.gateUpdateBlock] == true) {
        AppLog.d('更新', '当前学号被列入更新黑名单，屏蔽更新');
        if (mounted) {
          setState(() {
            _done = true;
            _result = null;
          });
        }
        return;
      }
    } catch (_) {
      // 门控查询失败不阻塞正常检查
    }
    final api = ref.read(updateApiProvider);
    try {
      final r = await api.checkLatest();
      if (!mounted) return;
      AppLog.d('更新', r.$1.isEmpty ? '检查更新：已是最新 v$appVersion' : '检查更新：发现新版 v${r.$1}');
      setState(() {
        _done = true;
        _result = r;
      });
    } catch (e) {
      if (!mounted) return;
      AppLog.e('更新', '检查更新失败：$e');
      setState(() {
        _done = true;
        _error = '$e';
      });
    }
  }

  Future<void> _download() async {
    final r = _result;
    if (r == null || _downloading) return;
    final (version, _, _, downloadUrl) = r;
    if (downloadUrl.isEmpty) {
      showInkToast(context, '未找到 APK 下载链接', error: true);
      return;
    }
    final token = CancelToken();
    setState(() {
      _downloading = true;
      _progress = 0;
      _cancelToken = token;
    });
    AppLog.d('更新', '开始下载 v$version（镜像优先，失败回退直连）');
    try {
      final candidates = [defaultGhMirror + downloadUrl, downloadUrl];
      for (final u in candidates) {
        try {
          setState(() => _progress = 0);
          await ApkInstaller.downloadAndInstall(
              u, '海畔_update_v$version.apk',
              onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          }, cancelToken: token);
          return; // 下载成功且已拉起系统安装
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) {
            AppLog.d('更新', '下载已取消');
            if (mounted) showInkToast(context, '已取消下载');
            return;
          }
          AppLog.w('更新', '$u 下载失败：${e.message}');
        } catch (e) {
          AppLog.w('更新', '$u 下载失败：$e');
        }
      }
      AppLog.e('更新', '全部下载源失败');
      if (mounted) showInkToast(context, '下载失败，请检查网络后重试', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _cancelToken = null;
        });
      }
    }
  }

  /// 取消进行中的下载
  void _cancelDownload() {
    ApkInstaller.cancel(_cancelToken);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final ink = context.ink;

    Widget content;
    Widget? bottom;

    if (!_done) {
      content = const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    } else if (_error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: InkSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.cloudOff, size: 42, color: ink.secondaryLabel),
              const SizedBox(height: InkSpacing.m),
              Text('检查失败', style: context.tsBodyStrong),
              const SizedBox(height: InkSpacing.xs),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: context.tsCaption,
              ),
              const SizedBox(height: InkSpacing.l),
              FilledButton.tonalIcon(
                onPressed: _retry,
                icon: const Icon(AppIcons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    } else {
      final r = _result;
      if (r == null || r.$1.isEmpty) {
        content = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.success, size: 52, color: cs.primary),
              const SizedBox(height: InkSpacing.m),
              Text('当前已是最新版本', style: context.tsBodyStrong),
              const SizedBox(height: InkSpacing.xs),
              Text('v$appVersion', style: context.tsSecondary),
            ],
          ),
        );
      } else if (r.$1 == appVersion) {
        content = _VersionNotes(
          icon: AppIcons.success,
          iconTone: InkTone.success,
          title: '当前已是最新版本',
          versionText: 'v$appVersion',
          notes: r.$2,
        );
        bottom = SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: null, // 已是最新，置灰
            icon: const Icon(AppIcons.success, size: 18),
            label: const Text('已是最新版'),
          ),
        );
      } else {
        final (version, notes, _, downloadUrl) = r;
        content = _VersionNotes(
          icon: AppIcons.update,
          iconTone: InkTone.info,
          title: '发现新版本',
          versionText: 'v$appVersion → v$version',
          notes: notes,
        );
        bottom = _downloading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _WaveProgressBar(
                    progress: _progress.clamp(0.0, 1.0).toDouble(),
                    color: cs.primary,
                  ),
                  const SizedBox(height: InkSpacing.s),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _progress > 0
                              ? '正在下载 ${(_progress * 100).toStringAsFixed(0)}%'
                              : '准备下载…',
                          style: context.tsCaption,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _cancelDownload,
                        icon: const Icon(AppIcons.stop, size: 18),
                        label: const Text('取消下载'),
                      ),
                    ],
                  ),
                ],
              )
            : SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: downloadUrl.isEmpty ? null : _download,
                  icon: const Icon(AppIcons.download),
                  label: const Text('下载并安装'),
                ),
              );
      }
    }

    return InkPageScaffold(
      showBack: true,
      title: '检查更新',
      body: content,
      bottom: bottom,
    );
  }

  void _retry() {
    setState(() {
      _done = false;
      _error = null;
      _result = null;
    });
    _check();
  }
}

/// 版本信息 + 更新日志卡
class _VersionNotes extends StatelessWidget {
  const _VersionNotes({
    required this.icon,
    required this.iconTone,
    required this.title,
    required this.versionText,
    required this.notes,
  });

  final IconData icon;
  final InkTone iconTone;
  final String title;
  final String versionText;
  final String notes;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(
        top: InkSpacing.xs,
        bottom: InkSpacing.l,
      ),
      children: [
        InkCard(
          child: Row(
            children: [
              InkIconBadge(icon: icon, tone: iconTone),
              const SizedBox(width: InkSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.tsBodyStrong),
                    const SizedBox(height: 3),
                    Text(versionText, style: context.tsSecondary),
                  ],
                ),
              ),
            ],
          ),
        ),
        const InkSectionHeader(title: '更新日志'),
        InkCard(
          child: notes.isEmpty
              ? Text('暂无更新说明', style: context.tsSecondary)
              : SelectableText(
                  '$notes\n',
                  style: context.tsCaption.copyWith(height: 1.6),
                ),
        ),
      ],
    );
  }
}

/// 谷歌商店风格的不规则波浪下载进度条（流动动效）
class _WaveProgressBar extends StatefulWidget {
  final double progress; // 0..1
  final Color color;
  const _WaveProgressBar({required this.progress, required this.color});

  @override
  State<_WaveProgressBar> createState() => _WaveProgressBarState();
}

class _WaveProgressBarState extends State<_WaveProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => CustomPaint(
        size: const Size(double.infinity, 16),
        painter: _WavePainter(
          progress: widget.progress.clamp(0.0, 1.0).toDouble(),
          phase: _ctrl.value * 40,
          color: widget.color,
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double progress;
  final double phase;
  final Color color;

  _WavePainter({
    required this.progress,
    required this.phase,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final mid = h / 2;
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h), Radius.circular(h / 2));
    canvas.save();
    canvas.clipRRect(rect);
    final fill = w * progress;
    if (fill <= 0) {
      canvas.restore();
      return;
    }
    // 波浪填充（半透明）
    final wavePaint = Paint()..color = color.withValues(alpha: 0.35);
    final fillPath = Path()
      ..moveTo(0, h)
      ..lineTo(0, mid);
    for (double x = 0; x <= fill; x += 2) {
      fillPath.lineTo(x, mid + 3.2 * _WavePainter.sin((x - phase) * 0.12));
    }
    fillPath
      ..lineTo(fill, h)
      ..close();
    canvas.drawPath(fillPath, wavePaint);
    // 顶部浪线（实色）
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final linePath = Path();
    var first = true;
    for (double x = 0; x <= fill; x += 3) {
      final y = mid + 3.0 * _WavePainter.sin((x - phase) * 0.12);
      if (first) {
        linePath.moveTo(x, y);
        first = false;
      } else {
        linePath.lineTo(x, y);
      }
    }
    canvas.drawPath(linePath, linePaint);
    canvas.restore();
  }

  static double sin(double v) => math.sin(v);

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.phase != phase;
}
