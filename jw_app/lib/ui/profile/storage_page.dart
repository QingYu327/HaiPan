import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/data_providers.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_dialog.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

/// 存储占用页：饼状图展示各项占用 + 清除入口（二次确认）
class StoragePage extends ConsumerStatefulWidget {
  const StoragePage({super.key});

  @override
  ConsumerState<StoragePage> createState() => _StoragePageState();
}

class _Cat {
  final String name;
  final int bytes;
  final InkTone tone;
  const _Cat(this.name, this.bytes, this.tone);
}

class _StoragePageState extends ConsumerState<StoragePage> {
  List<_Cat> _cats = [];
  int _total = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    setState(() => _loading = true);
    int logBytes = 0;
    int cookieBytes = 0;
    int fileTotal = 0;

    // 应用私有目录：Android 直接扫描包目录，覆盖 files / cache /
    // shared_prefs / databases / no_backup 等全部落盘数据；
    // 其他平台逐个加入支持目录、文档目录、缓存目录与临时目录。
    final roots = <Directory>[];
    void addRoot(Directory? d) {
      if (d == null) return;
      final p = d.path;
      final sep = Platform.pathSeparator;
      if (roots.any((r) => p == r.path || p.startsWith('${r.path}$sep'))) {
        return;
      }
      roots.removeWhere((r) => r.path.startsWith('$p$sep'));
      roots.add(d);
    }

    try {
      final support = await getApplicationSupportDirectory();
      if (Platform.isAndroid || Platform.isIOS) addRoot(support.parent);
      addRoot(support);
    } catch (_) {}
    try {
      addRoot(await getApplicationDocumentsDirectory());
    } catch (_) {}
    try {
      addRoot(await getApplicationCacheDirectory());
    } catch (_) {}
    try {
      addRoot(await getTemporaryDirectory());
    } catch (_) {}

    for (final root in roots) {
      try {
        await for (final f in root.list(recursive: true, followLinks: false)) {
          if (f is! File) continue;
          int len;
          try {
            len = await f.length();
          } catch (_) {
            continue;
          }
          fileTotal += len;
          final name = f.path.split(Platform.pathSeparator).last;
          if (name.toLowerCase().endsWith('.log') ||
              name.startsWith('haipan-feedback-')) {
            logBytes += len;
          }
          if (name == 'cookies') cookieBytes += len;
        }
      } catch (_) {}
    }

    // 离线缓存：SharedPreferences 中 cache_ 键的字符串长度
    int cacheBytes = 0;
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys()) {
        if (k.startsWith('cache_')) {
          cacheBytes += (p.getString(k)?.length ?? 0);
        }
      }
    } catch (_) {}
    // 缓存值存放在 shared_prefs 文件内，已计入 fileTotal，避免重复累加
    cacheBytes = cacheBytes.clamp(0, (fileTotal - logBytes - cookieBytes).clamp(0, 1 << 40));

    final otherBytes =
        (fileTotal - logBytes - cookieBytes - cacheBytes).clamp(0, 1 << 40);
    final list = <_Cat>[
      if (logBytes > 0) _Cat('日志', logBytes, InkTone.info),
      if (cacheBytes > 0) _Cat('离线缓存', cacheBytes, InkTone.success),
      if (cookieBytes > 0) _Cat('会话', cookieBytes, InkTone.warning),
      if (otherBytes > 0) _Cat('其他文件', otherBytes, InkTone.danger),
    ];
    final total = list.fold<int>(0, (s, c) => s + c.bytes);
    if (mounted) {
      setState(() {
        _cats = list;
        _total = total;
        _loading = false;
      });
    }
  }

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  /// 圆环中心：不足 1 MB 时精确到 KB，避免小体积显示成 0
  String _ringLabel(int b) {
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _confirm(String title, String msg, Future<void> Function() act,
      String doneMsg) async {
    final ok = await showInkDialog(
      context,
      title: title,
      message: msg,
      confirmText: '清除',
      danger: true,
    );
    if (!ok) return;
    await act();
    AppLog.d('存储', '$title：$doneMsg');
    if (mounted) {
      showInkToast(context, doneMsg);
      _compute();
    }
  }

  Future<void> _clearLogs() => _confirm('清除日志', '确定清空所有运行日志吗？',
      AppLog.clear, '已清空日志');

  Future<void> _clearCaches() async {
    final p = await SharedPreferences.getInstance();
    final keys = p.getKeys().where((k) => k.startsWith('cache_')).toList();
    await _confirm(
        '清除离线缓存',
        '将清除课表/成绩/考试等本地缓存（共 ${keys.length} 项），确定吗？',
        () async {
      for (final k in keys) {
        await p.remove(k);
      }
      ref.invalidate(timetableProvider);
      ref.invalidate(gradesProvider);
      ref.invalidate(examsProvider);
      ref.invalidate(academicProvider);
    }, '已清除离线缓存（${keys.length} 项）');
  }

  @override
  Widget build(BuildContext context) {
    final colors = [for (final c in _cats) inkToneColor(context, c.tone)];
    return InkPageScaffold(
      showBack: true,
      title: '本地占用',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(
                top: InkSpacing.xs,
                bottom: InkSpacing.l,
              ),
              children: [
                InkCard(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 180,
                        width: 180,
                        child: _PieChart(
                          cats: _cats,
                          total: _total,
                          colors: colors,
                          label: _ringLabel(_total),
                        ),
                      ),
                      const SizedBox(height: InkSpacing.m),
                      Text('共 ${_fmt(_total)}', style: context.tsSecondary),
                      const SizedBox(height: InkSpacing.m),
                      for (final c in _cats)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: InkSpacing.xs - 1),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: inkToneColor(context, c.tone),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: InkSpacing.s),
                              Expanded(
                                child: Text(c.name, style: context.tsBody),
                              ),
                              Text(
                                '${_fmt(c.bytes)}'
                                '（${(c.bytes / (_total > 0 ? _total : 1) * 100).toStringAsFixed(1)}%）',
                                style: context.tsSecondary,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: InkSpacing.m),
                // 清除入口
                InkCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      InkSettingTile(
                        title: '清除日志',
                        icon: AppIcons.delete,
                        iconTone: InkTone.danger,
                        titleTone: InkTone.danger,
                        onTap: _clearLogs,
                      ),
                      InkSettingTile(
                        title: '清除离线缓存（课表/成绩/考试）',
                        icon: AppIcons.cleaning,
                        iconTone: InkTone.danger,
                        titleTone: InkTone.danger,
                        onTap: _clearCaches,
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// 简单饼状图（使用 CustomPainter，无第三方依赖）
class _PieChart extends StatelessWidget {
  final List<_Cat> cats;
  final int total;
  final List<Color> colors;
  final String label;
  const _PieChart({
    required this.cats,
    required this.total,
    required this.colors,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiePainter(
        cats: cats,
        total: total,
        colors: colors,
        label: label,
        emptyColor: context.ink.hairline,
        labelStyle: context.tsBodyStrong,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<_Cat> cats;
  final int total;
  final List<Color> colors;
  final String label;
  final Color emptyColor;
  final TextStyle labelStyle;
  _PiePainter({
    required this.cats,
    required this.total,
    required this.colors,
    required this.label,
    required this.emptyColor,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.34;
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (total <= 0) {
      final p = Paint()
        ..color = emptyColor
        ..strokeWidth = 14
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(rect.center, rect.width / 2, p);
    } else {
      final p = Paint()
        ..strokeWidth = 14
        ..style = PaintingStyle.stroke;
      var start = -3.14159265 / 2;
      for (var i = 0; i < cats.length; i++) {
        final c = cats[i];
        final sweep = 2 * 3.14159265 * c.bytes / total;
        p.color = colors[i];
        canvas.drawArc(rect, start, sweep, false, p);
        start += sweep;
      }
    }
    // 中心文字：不足 1 MB 时按 KB 显示
    final tp = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: rect.width);
    tp.paint(canvas,
        Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.total != total ||
      old.label != label ||
      old.cats != cats ||
      old.colors != colors;
}
