import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../api/jw_apis.dart';
import '../../providers/data_providers.dart';
import '../../providers/session_provider.dart';
import '../../theme/ink_tokens.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ink_page.dart';

class GradePage extends ConsumerWidget {
  const GradePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grades = ref.watch(gradesProvider);
    Future<void> refresh() => ref.read(gradesProvider.notifier).refresh();
    return InkPageScaffold(
      title: '成绩',
      actions: [
        const TermPickerButton(scope: 'grade'),
        const SizedBox(width: InkSpacing.xs),
      ],
      body: grades.when(
        loading: () => const InkLoadingView(message: '正在获取成绩…'),
        error: (e, _) => InkRefresh(
          fill: true,
          onRefresh: refresh,
          child: ref.read(sessionProvider).browsing
              ? const GuestEmptyView()
              : RetryLoadView(onRetry: refresh),
        ),
        data: (data) {
          final (list, summary) = data;
          if (list.isEmpty) {
            autoFallbackTerm(ref, 'grade');
            return InkRefresh(
              fill: true,
              onRefresh: refresh,
              child: const EmptyView('该学期暂无成绩'),
            );
          }
          resetAutoFallback('grade');
          return InkRefresh(
            onRefresh: refresh,
            child: ListView(
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                0,
                InkSpacing.xs,
                0,
                inkPagePadding(context).bottom,
              ),
              children: [
                _SummaryCard(summary: summary),
                const SizedBox(height: InkSpacing.m),
                _GradeAnalysisCard(grades: list),
                const SizedBox(height: InkSpacing.l),
                InkSectionHeader(
                  title: '课程明细',
                  trailing: Text(
                    '共 ${list.length} 门',
                    style: context.tsSecondary,
                  ),
                ),
                for (final g in list) _GradeCard(grade: g),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 绩点结果卡：主数字（学分绩点）突出，辅以加权平均与学分/门数。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final GradeSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final ink = context.ink;
    final onTint = cs.onPrimaryContainer;
    final secondaryOnTint = onTint.withValues(alpha: 0.68);

    return InkCard(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          InkSpacing.l + 2,
          InkSpacing.l,
          InkSpacing.l + 2,
          InkSpacing.m,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(InkRadius.card),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primaryContainer.withValues(alpha: 0.72),
              cs.primaryContainer.withValues(alpha: 0.20),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '学分绩点',
                        style: InkTextStyles.label.copyWith(
                          color: secondaryOnTint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary.gpa.toStringAsFixed(2),
                        style: context.tabular.copyWith(
                          fontSize: 38,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                          color: onTint,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '加权平均',
                      style: InkTextStyles.label.copyWith(
                        color: secondaryOnTint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.weightedAvg.toStringAsFixed(1),
                      style: context.tabular.copyWith(
                        fontSize: 24,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: onTint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: InkSpacing.m),
            Divider(
              height: InkStroke.hairline,
              thickness: InkStroke.hairline,
              color: ink.hairline,
            ),
            const SizedBox(height: InkSpacing.m),
            Row(
              children: [
                _Metric(
                  label: '获得学分',
                  value: summary.totalCredit.toStringAsFixed(1),
                  color: onTint,
                  labelColor: secondaryOnTint,
                ),
                Container(
                  width: InkStroke.hairline,
                  height: 26,
                  color: ink.hairline,
                ),
                _Metric(
                  label: '课程门数',
                  value: '${summary.courseCount}',
                  color: onTint,
                  labelColor: secondaryOnTint,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
    required this.labelColor,
  });

  final String label;
  final String value;
  final Color color;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: context.tabular.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: InkSpacing.xs + 2),
          Text(label, style: InkTextStyles.label.copyWith(color: labelColor)),
        ],
      ),
    );
  }
}

/// 分数分布直方图（<60 / 60-69 / 70-79 / 80-89 / 90+）。
class _GradeAnalysisCard extends StatelessWidget {
  const _GradeAnalysisCard({required this.grades});

  final List<Grade> grades;

  static const _labels = ['<60', '60-69', '70-79', '80-89', '90+'];

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final ink = context.ink;
    final counts = List<int>.filled(_labels.length, 0);
    for (final g in grades) {
      final v = double.tryParse(g.cj);
      if (v == null) continue;
      if (v < 60) {
        counts[0]++;
      } else if (v < 70) {
        counts[1]++;
      } else if (v < 80) {
        counts[2]++;
      } else if (v < 90) {
        counts[3]++;
      } else {
        counts[4]++;
      }
    }
    var maxV = 1;
    var sum = 0;
    for (final n in counts) {
      if (n > maxV) maxV = n;
      sum += n;
    }
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.chartBar, size: 18, color: cs.primary),
              const SizedBox(width: InkSpacing.s),
              Text('分数分布', style: context.tsBodyStrong),
              const Spacer(),
              Text('共 $sum 门', style: context.tsSecondary),
            ],
          ),
          const SizedBox(height: InkSpacing.m),
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < counts.length; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${counts[i]}',
                          style: InkTextStyles.micro.copyWith(
                            color: counts[i] > 0
                                ? cs.onSurfaceVariant
                                : ink.secondaryLabel,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: counts[i] == 0 ? 4 : 40 * counts[i] / maxV,
                          width: 20,
                          decoration: BoxDecoration(
                            color: i == 0 ? ink.danger : cs.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _labels[i],
                          style: InkTextStyles.micro.copyWith(
                            fontSize: 9.5,
                            color: ink.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeCard extends ConsumerWidget {
  const _GradeCard({required this.grade});

  final Grade grade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.scheme;
    final ink = context.ink;
    final cj = double.tryParse(grade.cj);
    // 及格线着色：>=90 绿 / 60-89 主色 / <60 朱砂 / 等级制（非数字）中性。
    final valueColor = cj == null
        ? cs.onSurface
        : cj >= 90
        ? ink.success
        : cj >= 60
        ? cs.primary
        : ink.danger;
    final meta = [
      if (grade.termLabel.isNotEmpty) grade.termLabel,
      if (grade.xf.isNotEmpty) '${grade.xf} 学分',
      if (grade.jd.isNotEmpty) '绩点 ${grade.jd}',
    ].join(' · ');
    final canDetail = grade.canQueryDetail;

    return InkCard(
      margin: const EdgeInsets.only(bottom: InkSpacing.s),
      padding: const EdgeInsets.symmetric(
        horizontal: InkSpacing.l,
        vertical: InkSpacing.m,
      ),
      onTap: canDetail ? () => _showDetail(context, ref) : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grade.kcmc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.tsBodyStrong,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(meta, style: context.tsSecondary),
                ],
              ],
            ),
          ),
          const SizedBox(width: InkSpacing.m),
          Text(
            grade.cj.isEmpty ? '—' : grade.cj,
            style: context.tabular.copyWith(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          if (canDetail) ...[
            const SizedBox(width: InkSpacing.xs),
            Icon(AppIcons.chevronRight, size: 18, color: ink.secondaryLabel),
          ],
        ],
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, WidgetRef ref) async {
    // 先弹出加载态弹窗，拿到数据后原位替换内容
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _GradeDetailDialog(grade: grade, ref: ref),
    );
  }
}

/// 成绩构成弹窗：加载中 → 成功展示分项 / 失败显示原因。
class _GradeDetailDialog extends StatefulWidget {
  const _GradeDetailDialog({required this.grade, required this.ref});

  final Grade grade;
  final WidgetRef ref;

  @override
  State<_GradeDetailDialog> createState() => _GradeDetailDialogState();
}

class _GradeDetailDialogState extends State<_GradeDetailDialog> {
  late Future<List<GradeComponent>> _future;

  @override
  void initState() {
    super.initState();
    // 先读本地缓存（成绩分项基本不变），没有缓存才走在线
    _future = widget.ref.read(gradeApiProvider).fetchDetails(widget.grade);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final ink = context.ink;
    return AlertDialog(
      title: Text(widget.grade.kcmc),
      content: FutureBuilder<List<GradeComponent>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 120,
              child: InkLoadingView(message: '正在获取成绩构成…'),
            );
          }
          if (snap.hasError) {
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.cloudOff,
                      size: 36,
                      color: ink.secondaryLabel,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '暂时无法获取成绩构成',
                      textAlign: TextAlign.center,
                      style: context.tsSecondary,
                    ),
                  ],
                ),
              ),
            );
          }
          final comps = snap.data ?? [];
          if (comps.isEmpty) {
            return SizedBox(
              height: 90,
              child: Center(
                child: Text('暂无成绩构成明细', style: context.tsSecondary),
              ),
            );
          }
          // 过滤掉"总评"分项（底部总评卡统一展示，避免重复）
          final detailItems = comps
              .where((c) => !c.name.contains('总评'))
              .toList();
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - v)),
                child: child,
              ),
            ),
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (detailItems.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: InkSpacing.s),
                    padding: const EdgeInsets.symmetric(
                      horizontal: InkSpacing.m,
                      vertical: InkSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: ink.groupedBackground,
                      borderRadius: BorderRadius.circular(InkRadius.control),
                      border: Border.all(
                        color: ink.hairline,
                        width: InkStroke.hairline,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 2),
                          child: Text('平时 / 期末', style: context.tsBodyStrong),
                        ),
                        Divider(
                          height: 12,
                          color: ink.hairline,
                          thickness: InkStroke.hairline,
                        ),
                        for (var i = 0; i < detailItems.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              top: i == 0 ? 2 : 6,
                              bottom: 2,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    detailItems[i].name,
                                    style: context.tsBodyStrong,
                                  ),
                                ),
                                if (detailItems[i].ratio.isNotEmpty)
                                  InkTag(text: '占比 ${detailItems[i].ratio}'),
                                const Spacer(),
                                Text(
                                  detailItems[i].score.isEmpty
                                      ? '—'
                                      : detailItems[i].score,
                                  style: context.tabular.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text('分', style: context.tsSecondary),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: InkSpacing.m,
                    vertical: InkSpacing.m,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(InkRadius.control),
                  ),
                  child: Row(
                    children: [
                      Text('总评', style: context.tsBodyStrong),
                      const Spacer(),
                      Text(
                        widget.grade.cj.isEmpty ? '—' : widget.grade.cj,
                        style: context.tabular.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('分', style: context.tsSecondary),
                    ],
                  ),
                ),
              ],
            ),
          ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
