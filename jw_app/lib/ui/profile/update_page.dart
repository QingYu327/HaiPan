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
              : _ReleaseNotes(notes: notes),
        ),
      ],
    );
  }
}

/// 轻量 Markdown 渲染：标题 / 列表 / 引用 / 代码块 / 行内加粗与代码，
/// 不引入额外依赖，风格跟随水墨主题。
class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final base = context.tsCaption.copyWith(height: 1.65);
    final blocks = <Widget>[];
    final code = <String>[];
    var inCode = false;

    void flushCode() {
      if (code.isEmpty) return;
      blocks.add(Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: InkSpacing.s),
        padding: const EdgeInsets.all(InkSpacing.m),
        decoration: BoxDecoration(
          color: context.ink.cardFill,
          borderRadius: BorderRadius.circular(InkRadius.control),
          border: Border.all(color: context.ink.hairline),
        ),
        child: Text(
          code.join('\n'),
          style: base.copyWith(
            fontFamily: 'monospace',
            height: 1.5,
            color: context.ink.secondaryLabel,
          ),
        ),
      ));
      code.clear();
    }

    for (final raw in notes.split('\n')) {
      final line = raw.trimRight();
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          inCode = false;
          flushCode();
        } else {
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        code.add(line);
        continue;
      }
      final text = line.trim();
      if (text.isEmpty) {
        if (blocks.isNotEmpty) {
          blocks.add(const SizedBox(height: InkSpacing.s));
        }
        continue;
      }
      if (RegExp(r'^-{3,}$').hasMatch(text)) {
        blocks.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: InkSpacing.s),
          child: Divider(height: 1, color: context.ink.hairline),
        ));
        continue;
      }
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(text);
      if (heading != null) {
        final level = heading.group(1)!.length;
        blocks.add(Padding(
          padding: EdgeInsets.only(
            top: blocks.isEmpty ? 0 : InkSpacing.s,
            bottom: 4,
          ),
          child: _inline(
            context,
            heading.group(2)!,
            context.tsBodyStrong.copyWith(
              fontSize: level <= 2 ? 17 : 15,
            ),
            base,
          ),
        ));
        continue;
      }
      final bullet = RegExp(r'^([-*+])\s+(.*)$').firstMatch(text);
      if (bullet != null) {
        blocks.add(_NoteRow(
          marker: '•',
          child: _inline(context, bullet.group(2)!, base, base),
        ));
        continue;
      }
      final number = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(text);
      if (number != null) {
        blocks.add(_NoteRow(
          marker: '${number.group(1)}.',
          child: _inline(context, number.group(2)!, base, base),
        ));
        continue;
      }
      if (text.startsWith('>')) {
        blocks.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(
            InkSpacing.m,
            InkSpacing.s,
            InkSpacing.m,
            InkSpacing.s,
          ),
          decoration: BoxDecoration(
            color: context.ink.cardFill,
            border: Border(
              left: BorderSide(color: context.scheme.primary, width: 2.5),
            ),
            borderRadius: BorderRadius.circular(InkRadius.control),
          ),
          child: _inline(
            context,
            text.replaceFirst(RegExp(r'^>\s?'), ''),
            base.copyWith(color: context.ink.secondaryLabel),
            base,
          ),
        ));
        continue;
      }
      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: _inline(context, text, base, base),
      ));
    }
    flushCode();

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      ),
    );
  }

  /// 行内样式：**加粗**、`代码`、[链接](url)（链接仅显示文字，点击交给系统浏览器有风险，故不跳转）。
  Widget _inline(
    BuildContext context,
    String text,
    TextStyle style,
    TextStyle base,
  ) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\([^)]+\))');
    var index = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > index) {
        spans.add(TextSpan(text: text.substring(index, m.start)));
      }
      final token = m.group(0)!;
      if (token.startsWith('**')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(
            fontFamily: 'monospace',
            color: context.ink.secondaryLabel,
          ),
        ));
      } else {
        final label = RegExp(r'^\[([^\]]+)\]').firstMatch(token)?.group(1);
        spans.add(TextSpan(
          text: label ?? token,
          style: TextStyle(color: context.scheme.primary),
        ));
      }
      index = m.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.marker, required this.child});

  final String marker;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              marker,
              style: context.tsCaption.copyWith(height: 1.65),
            ),
          ),
          Expanded(child: child),
        ],
      ),
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
