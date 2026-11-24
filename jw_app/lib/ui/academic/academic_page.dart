import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/data_providers.dart';
import '../../providers/session_provider.dart';
import '../../theme/ink_page_transition.dart';
import '../../theme/ink_tokens.dart';
import '../rank/rank_page.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ink_page.dart';

class AcademicPage extends ConsumerWidget {
  const AcademicPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final academic = ref.watch(academicProvider);
    Future<void> refresh() => ref.read(academicProvider.notifier).refresh();
    return InkPageScaffold(
      title: '学业',
      actions: [
        IconButton(
          tooltip: '绩点排名',
          icon: const Icon(AppIcons.leaderboard),
          onPressed: () => Navigator.push(
            context,
            InkPageRoute(builder: (_) => const RankPage()),
          ),
        ),
        const SizedBox(width: InkSpacing.xs),
      ],
      body: academic.when(
        loading: () => const InkLoadingView(message: '正在汇总学业数据…'),
        error: (e, _) => InkRefresh(
          fill: true,
          onRefresh: refresh,
          child: ref.read(sessionProvider).browsing
              ? const GuestEmptyView()
              : RetryLoadView(onRetry: refresh),
        ),
        data: (d) {
          if (d.categories.isEmpty && d.overview.categories.isEmpty) {
            return InkRefresh(
              fill: true,
              onRefresh: refresh,
              child: const EmptyView('暂无学业数据'),
            );
          }
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
                _ProgressCard(overview: d.overview),
                _WarnBanner(overview: d.overview),
                if (d.categories.isNotEmpty) ...[
                  InkSectionHeader(
                    title: '课程明细',
                    trailing: Text(
                      '共 ${d.categories.length} 类',
                      style: context.tsSecondary,
                    ),
                  ),
                  for (final c in d.categories) _CategoryCard(category: c),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.overview});

  final AcademicOverview overview;

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final ink = context.ink;
    final progress = overview.progress;
    final gpa = overview.gpa;
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('修读进度', style: context.tsBodyStrong),
              const Spacer(),
              Text(
                '${(progress * 100).toStringAsFixed(1)}%',
                style: context.tabular.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: InkSpacing.m),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: ink.groupedBackground,
            ),
          ),
          const SizedBox(height: InkSpacing.m),
          Text(
            '已修 ${_fmt(overview.earnedCredit)} / '
            '${_fmt(overview.requireCredit)} 学分'
            '${gpa != null ? '　· GPA ${gpa.toStringAsFixed(2)}' : ''}',
            style: context.tsCaption,
          ),
          const SizedBox(height: InkSpacing.m),
          Divider(
            height: 1,
            thickness: InkStroke.hairline,
            color: ink.hairline,
          ),
          const SizedBox(height: InkSpacing.m),
          InkStatsRow(
            valueSize: 17,
            stats: [
              InkStat('${overview.planCourses}', '计划课程'),
              InkStat('${overview.passed}', '通过', tone: InkTone.success),
              InkStat('${overview.failed}', '未通过', tone: InkTone.danger),
              InkStat('${overview.notStarted}', '未修'),
              InkStat('${overview.inProgress}', '在读', tone: InkTone.info),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(1);
}

/// 挂科预警 / 修读学分缺口提示（无预警时隐藏）。
class _WarnBanner extends StatelessWidget {
  const _WarnBanner({required this.overview});

  final AcademicOverview overview;

  @override
  Widget build(BuildContext context) {
    final msgs = <String>[];
    if (overview.failed > 0) msgs.add('有 ${overview.failed} 门课程未通过');
    final gap = overview.requireCredit - overview.earnedCredit;
    if (gap > 0.001) msgs.add('距最低修读要求还差 ${gap.toStringAsFixed(1)} 学分');
    if (msgs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: InkSpacing.m),
      child: InkBanner(
        message: msgs.join('；'),
        tone: InkTone.warning,
        icon: AppIcons.warningAmber,
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category});

  final AcademicCategory category;

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final ink = context.ink;
    final rate = category.totalCredit > 0
        ? (category.earnedCredit / category.totalCredit).clamp(0.0, 1.0)
        : 0.0;
    return InkCard(
      margin: const EdgeInsets.only(bottom: InkSpacing.m),
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: InkSpacing.l,
            vertical: 2,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            InkSpacing.l,
            0,
            InkSpacing.l,
            InkSpacing.m,
          ),
          iconColor: ink.secondaryLabel,
          collapsedIconColor: ink.secondaryLabel,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tsBodyStrong,
                ),
              ),
              const SizedBox(width: InkSpacing.s),
              Text(
                '已修 ${category.earnedCredit.toStringAsFixed(1)} 学分',
                style: InkTextStyles.label.copyWith(color: cs.primary),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: InkSpacing.s, bottom: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 4,
                backgroundColor: ink.groupedBackground,
              ),
            ),
          ),
          children: [
            for (var i = 0; i < category.courses.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: InkStroke.hairline,
                  color: ink.hairline,
                ),
              _CourseRow(course: category.courses[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course});

  final AcademicCourse course;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final (statusText, tone) = switch (course.status) {
      CourseStatus.done => ('已修', InkTone.success),
      CourseStatus.inProgress => ('在修', InkTone.warning),
      CourseStatus.planned => ('未修', InkTone.neutral),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: InkSpacing.s + 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.kcmc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tsBody,
                ),
                if (course.status == CourseStatus.done && course.cj.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '成绩 ${course.cj} · 绩点 ${course.jd}',
                      style: context.tsSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: InkSpacing.s),
          Text(
            '${course.xf.toStringAsFixed(1)} 学分',
            style: InkTextStyles.label.copyWith(color: ink.secondaryLabel),
          ),
          const SizedBox(width: InkSpacing.s),
          InkTag(text: statusText, tone: tone),
        ],
      ),
    );
  }
}
