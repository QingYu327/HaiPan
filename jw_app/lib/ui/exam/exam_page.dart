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
            successMessage: '考试安排已刷新，共 ${list.length} 场',
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
    final ended = days != null && days < 0;
    final place =
        [exam.cdxqmc, exam.cdmc].where((s) => s.isNotEmpty).join(' · ');
    final tag = exam.ksfs.isNotEmpty
        ? exam.ksfs
        : (exam.ksmc.isNotEmpty ? exam.ksmc : '');

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
                  child: Wrap(
                    spacing: InkSpacing.xs,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        exam.kcmc,
                        style: context.tsBodyStrong.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (tag.isNotEmpty) _tag(context, tag),
                    ],
                  ),
                ),
                const SizedBox(width: InkSpacing.s),
                _CountdownBadge(days: days),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              exam.kssj.isEmpty ? '时间待公布' : exam.kssj,
              style: TextStyle(
                fontSize: 15,
                height: 1.25,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: context.scheme.onSurface,
              ),
            ),
            if (place.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: InkSpacing.m,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: context.scheme.surfaceContainerHighest
                      .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(InkRadius.control),
                ),
                child: Row(
                  children: [
                    Icon(
                      AppIcons.location,
                      size: 16,
                      color: context.scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tsBody.copyWith(
                          fontSize: 13.5,
                          color: context.scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 考试形式小标签（闭卷 / 开卷 / 机考…）
  Widget _tag(BuildContext context, String text) {
    final c = context.scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: InkTextStyles.label.copyWith(
          fontSize: 11,
          color: c,
          fontWeight: FontWeight.w600,
        ),
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
    final text = days == null
        ? '未公布'
        : days! < 0
            ? '已结束'
            : days == 0
                ? '今天'
                : '还有 $days 天';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(InkRadius.pill),
      ),
      child: Text(
        text,
        style: InkTextStyles.label.copyWith(
          fontSize: 12.5,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  InkTone get _tone {
    if (days == null || days! < 0) return InkTone.neutral;
    if (days == 0) return InkTone.danger;
    return InkTone.warning;
  }
}
