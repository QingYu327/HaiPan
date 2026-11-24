import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/data_providers.dart';
import '../../providers/session_provider.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../../util/lesson_notifier.dart';
import '../../util/notify_target.dart';
import '../../util/term_utils.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ink_page.dart';

class ExamPage extends ConsumerStatefulWidget {
  const ExamPage({super.key});

  @override
  ConsumerState<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends ConsumerState<ExamPage> {
  int? _handledNotifyId; // 已消费的通知目标，避免重复弹详情

  @override
  Widget build(BuildContext context) {
    final exams = ref.watch(examsProvider);
    final notify = ref.watch(notifyTargetProvider);
    Future<void> refresh() => ref.read(examsProvider.notifier).refresh();
    return InkPageScaffold(
      title: '考试',
      actions: [
        const TermPickerButton(scope: 'exam'),
        const SizedBox(width: InkSpacing.xs),
      ],
      body: exams.when(
        loading: () => const InkLoadingView(message: '正在获取考试安排…'),
        error: (e, _) => InkRefresh(
          fill: true,
          onRefresh: refresh,
          child: ref.read(sessionProvider).browsing
              ? const GuestEmptyView()
              : RetryLoadView(onRetry: refresh),
        ),
        data: (list) {
          // 依据今天的考试排定时提醒（内部判空/时间）；
          // 仅当前学期生效，避免自动回退学期时清掉本学期提醒
          if (ref.watch(termProvider('exam')) == TermUtils.currentTerm()) {
            LessonNotifier.scheduleExams(list);
          }
          _maybeOpenNotify(list, notify);
          if (list.isEmpty) {
            autoFallbackTerm(ref, 'exam');
            return InkRefresh(
              fill: true,
              onRefresh: refresh,
              child: const EmptyView('该学期暂无考试安排'),
            );
          }
          resetAutoFallback('exam');
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
                InkSectionHeader(
                  title: '考试安排',
                  trailing: Text(
                    '共 ${list.length} 场',
                    style: context.tsSecondary,
                  ),
                ),
                for (final e in list)
                  _ExamCard(
                    exam: e,
                    onTap: () => showExamDetail(context, e),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 通知点击直达：定位到提醒对应的考试并弹出详情
  void _maybeOpenNotify(List<Exam> list, NotifyTarget? target) {
    if (target == null || !target.isExam) return;
    if (target.id == _handledNotifyId) return;
    _handledNotifyId = target.id;
    Exam? found;
    for (final e in list) {
      if (target.name.isNotEmpty && e.kcmc != target.name) continue;
      if (target.time.isNotEmpty && e.kssj != target.time) continue;
      found = e;
      break;
    }
    // 同名但时间字段格式不同（如只差括号）时放宽到课程名
    if (found == null && target.name.isNotEmpty) {
      for (final e in list) {
        if (e.kcmc == target.name) {
          found = e;
          break;
        }
      }
    }
    AppLog.w(
      '提醒诊断',
      '考试定位${found == null ? '未找到' : '成功：${found.kcmc}'}'
      '（${target.logText}）',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(notifyTargetProvider.notifier).state = null;
      if (found != null) showExamDetail(context, found);
    });
  }
}

/// 考试详情底部弹层（点击考试卡或通知直达时复用）
void showExamDetail(BuildContext context, Exam exam) {
  final days = exam.daysLeft;
  final badge = days == null
      ? '时间未公布'
      : days < 0
          ? '已结束'
          : days == 0
              ? '今天'
              : '$days 天后';
  showInkSheet(
    context,
    title: exam.kcmc,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow(context, AppIcons.time,
            exam.kssj.isEmpty ? '—' : exam.kssj),
        if (exam.ksmc.isNotEmpty)
          _detailRow(context, AppIcons.verified, exam.ksmc),
        if (exam.cdmc.isNotEmpty || exam.cdxqmc.isNotEmpty)
          _detailRow(
            context,
            AppIcons.location,
            [exam.cdxqmc, exam.cdmc].where((s) => s.isNotEmpty).join(' · '),
          ),
        if (exam.jxdd.isNotEmpty)
          _detailRow(context, AppIcons.seat, exam.jxdd),
        if (exam.ksfs.isNotEmpty)
          _detailRow(context, AppIcons.method, exam.ksfs),
        _detailRow(context, AppIcons.hourglass, badge),
      ],
    ),
  );
}

Widget _detailRow(BuildContext context, IconData icon, String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: context.scheme.onSurfaceVariant),
        const SizedBox(width: InkSpacing.m),
        Expanded(child: Text(text, style: context.tsBody)),
      ],
    ),
  );
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam, this.onTap});

  final Exam exam;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final days = exam.daysLeft;
    final rows = <Widget>[
      if (exam.kssj.isNotEmpty)
        _infoRow(context, AppIcons.time, '考试时间', exam.kssj),
      if (exam.cdmc.isNotEmpty || exam.cdxqmc.isNotEmpty)
        _infoRow(
          context,
          AppIcons.location,
          '考试地点',
          [exam.cdxqmc, exam.cdmc].where((s) => s.isNotEmpty).join(' · '),
        ),
      if (exam.ksmc.isNotEmpty)
        _infoRow(context, AppIcons.verified, '考试类型', exam.ksmc),
      if (exam.ksfs.isNotEmpty)
        _infoRow(context, AppIcons.method, '考试方式', exam.ksfs),
    ];

    final ended = days != null && days < 0;

    return InkCard(
      margin: const EdgeInsets.only(bottom: InkSpacing.m),
      onTap: onTap,
      child: Opacity(
        // 已结束的考试整卡置灰，弱化视觉优先级
        opacity: ended ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    exam.kcmc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.tsBodyStrong,
                  ),
                ),
                const SizedBox(width: InkSpacing.s),
                _CountdownBadge(days: days),
              ],
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: InkSpacing.m),
              ...rows,
            ],
          ],
        ),
      ),
    );
  }

  /// 标签小字 + 加粗值：时间/地点/类型共用，保证多行值对齐。
  Widget _infoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: context.scheme.primary),
          ),
          const SizedBox(width: InkSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.tsCaption),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: context.tsBodyStrong.copyWith(
                    color: context.scheme.onSurface,
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

/// 剩余天数：数字放大 + 语义色胶囊，今天/临近更醒目。
class _CountdownBadge extends StatelessWidget {
  const _CountdownBadge({required this.days});

  final int? days;

  @override
  Widget build(BuildContext context) {
    final color = inkToneColor(context, _tone);
    if (days == null || days! < 0) {
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
          days == null ? '未公布' : '已结束',
          style: InkTextStyles.label.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final today = days == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(InkRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            today ? '今天' : '$days',
            style: TextStyle(
              fontSize: today ? 18 : 24,
              height: 1,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (!today) ...[
            const SizedBox(width: 2),
            Text(
              '天后',
              style: InkTextStyles.label.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  InkTone get _tone {
    if (days == null || days! < 0) return InkTone.neutral;
    if (days == 0) return InkTone.danger;
    if (days! <= 7) return InkTone.warning;
    return InkTone.info;
  }
}
