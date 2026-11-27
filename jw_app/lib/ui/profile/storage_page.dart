import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/data_providers.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../../util/storage_usage.dart';
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
  const _Cat(this.name, this.bytes);
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
    final report = await computeStorageUsage();
    if (!mounted) return;
    setState(() {
      _cats = [for (final b in report.buckets) _Cat(b.name, b.bytes)];
      _total = report.total;
      _loading = false;
    });
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
    // 分类配色：沿用课程色板的深色字色，再补一个中性灰给第 9 类
    final palette = <Color>[
      for (final t in InkCourseTints.of(context)) t.$2,
      const Color(0xFF6B7280),
    ];
    final colors = [
      for (var i = 0; i < _cats.length; i++) palette[i % palette.length],
    ];
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
                      for (var i = 0; i < _cats.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: InkSpacing.xs - 1),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: colors[i],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: InkSpacing.s),
                              Expanded(
                                child: Text(
                                  _cats[i].name,
                                  style: context.tsBody,
                                ),
                              ),
                              Text(
                                '${_fmt(_cats[i].bytes)}'
                                '（${(_cats[i].bytes / (_total > 0 ? _total : 1) * 100).toStringAsFixed(1)}%）',
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
