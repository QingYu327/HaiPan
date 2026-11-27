import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/data_providers.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../../util/lesson_notifier.dart';
import '../../util/notify_target.dart';
import '../../util/term_utils.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ink_page.dart';

const _dayNames = ['', '一', '二', '三', '四', '五', '六', '日'];

/// 学校现行作息（按课表原文逐节固定，不做推算）：
/// 1 08:10~08:55 / 2 09:00~09:45 / 3 10:15~11:00 / 4 11:05~11:50
/// 5 14:30~15:15 / 6 15:20~16:05 / 7 16:30~17:15 / 8 17:20~18:05
/// 9 19:30~20:15 / 10 20:25~21:10
const _blockTimes = <int, (String, String)>{
  1: ('08:10', '08:55'),
  2: ('09:00', '09:45'),
  3: ('10:15', '11:00'),
  4: ('11:05', '11:50'),
  5: ('14:30', '15:15'),
  6: ('15:20', '16:05'),
  7: ('16:30', '17:15'),
  8: ('17:20', '18:05'),
  9: ('19:30', '20:15'),
  10: ('20:25', '21:10'),
};

String? _sectionStartTime(int section) => _blockTimes[section]?.$1;
String? _sectionEndTime(int section) => _blockTimes[section]?.$2;

/// 课程起止时间文本，如 "08:10-09:45"（按所在大节区间）
String _courseTime(CourseEntry c) {
  final s = _sectionStartTime(c.startSection);
  final e = _sectionEndTime(c.endSection);
  if (s == null && e == null) return '';
  if (s == null) return e!;
  if (e == null) return s;
  return '$s-$e';
}

class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  int _week = 1;
  int? _estimatedWeek;
  bool _weekInited = false;
  double _dragDx = 0; // 横向滑动累计位移，用于切周
  DateTime? _appliedSemStart; // 已应用的开学日，用于在设置变更后重算周数/日期
  bool _isCurrentTerm = true;
  int? _handledNotifyId; // 已消费的通知目标，避免重复弹详情

  @override
  Widget build(BuildContext context) {
    // 监听开学日等设置，变更后重新计算当前周与星期栏日期
    ref.watch(settingsProvider);
    final notify = ref.watch(notifyTargetProvider);
    final ttTerm = ref.watch(termProvider('timetable'));
    final examTerm = ref.watch(termProvider('exam'));
    _isCurrentTerm = ttTerm == TermUtils.currentTerm();
    // 考试数据就绪后即排考试提醒，不必先打开考试 tab；
    // 必须限定当前学期，否则考试页自动回退到上学期会清空/打乱本学期提醒
    final examList = ref.watch(examsProvider).valueOrNull;
    if (_isCurrentTerm &&
        examTerm == TermUtils.currentTerm() &&
        examList != null) {
      LessonNotifier.scheduleExams(examList);
    }
    final timetable = ref.watch(timetableProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: timetable.when(
          loading: () => const InkLoadingView(message: '正在获取课表…'),
          error: (e, _) => ref.read(sessionProvider).browsing
              ? const GuestEmptyView()
              : RetryLoadView(
                  onRetry: () => ref.read(timetableProvider.notifier).refresh(),
                ),
          data: (t) {
            // 首次或开学日变化时重算"估算当前周"，并据此校正当前显示周
            final semStart = ref.read(settingsProvider).semesterStart;
            if (!_weekInited || semStart != _appliedSemStart) {
              _weekInited = true;
              _appliedSemStart = semStart;
              final est = TermUtils.estimatedCurrentWeek(
                ref.read(termProvider('timetable')),
              );
              if (_estimatedWeek != est) {
                _estimatedWeek = est;
                _week = est ?? _week;
              }
            }
            // 依据当天课程排定时课提醒（内部按天/周去重）；
            // 浏览历史学期时不排，否则会把旧课程按"本学期第 N 周"排出错误提醒
            if (_isCurrentTerm) LessonNotifier.scheduleLessons(t);
            _maybeOpenNotify(t, notify);
            return _buildBody(t);
          },
        ),
      ),
    );
  }

  Widget _buildBody(Timetable t) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dragDx = 0,
      onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
      onHorizontalDragEnd: (_) {
        if (_dragDx.abs() < 48) return;
        // 向右滑 → 上一周；向左滑 → 下一周
        _setWeek(_dragDx > 0 ? _week - 1 : _week + 1);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              InkSpacing.l,
              InkSpacing.m,
              InkSpacing.s,
              InkSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(child: Text('课表', style: context.tsDisplay)),
                const TermPickerButton(scope: 'timetable'),
                const SizedBox(width: InkSpacing.xs),
              ],
            ),
          ),
          // "今日"只对当前学期有意义；浏览历史学期时不展示，避免误读
          if (_isCurrentTerm) const _TodayOverview(),
          _buildWeekBar(),
          Expanded(
            // 周切换：淡入 + 2% 上移，不做缩放回弹
            child: AnimatedSwitcher(
              duration: InkMotion.normal,
              switchInCurve: InkMotion.standard,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                final curved = CurvedAnimation(
                  parent: anim,
                  curve: InkMotion.standard,
                );
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.02),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
              child: t.courses.isEmpty && t.sjk.isEmpty
                  ? InkRefresh(
                      fill: true,
                      onRefresh: () =>
                          ref.read(timetableProvider.notifier).refresh(),
                      child: const EmptyView('该学期暂无课程'),
                    )
                  : KeyedSubtree(
                      key: ValueKey('week-$_week'),
                      child: _buildTimetable(t),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _setWeek(int w) {
    if (w == _week || w < 1 || w > 25) return;
    setState(() => _week = w);
  }

  /// 通知点击直达：定位到提醒对应的课程并弹出详情
  void _maybeOpenNotify(Timetable t, NotifyTarget? target) {
    if (target == null || !target.isLesson) return;
    if (target.id == _handledNotifyId) return;
    _handledNotifyId = target.id;
    CourseEntry? found;
    for (final c in t.courses) {
      if (target.name.isNotEmpty && c.kcmc != target.name) continue;
      if (target.weekday > 0 && c.weekday != target.weekday) continue;
      if (target.startSection > 0 && c.startSection != target.startSection) {
        continue;
      }
      found = c;
      break;
    }
    AppLog.w(
      '提醒诊断',
      '课表定位${found == null ? '未找到' : '成功：${found.kcmc}'}'
          '（${target.logText}）',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (target.week > 0 && _isCurrentTerm && target.week != _week) {
        setState(() => _week = target.week);
      }
      ref.read(notifyTargetProvider.notifier).state = null;
      if (found != null) showCourseDetail(context, found);
    });
  }

  Widget _buildWeekBar() {
    final cs = Theme.of(context).colorScheme;
    final isCurrent = _week == _estimatedWeek;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        InkSpacing.m,
        InkSpacing.xs,
        InkSpacing.m,
        InkSpacing.s,
      ),
      child: Row(
        children: [
          _iconButton(
            AppIcons.chevronLeft,
            _week > 1,
            () => _setWeek(_week - 1),
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: _pickWeek,
                child: AnimatedContainer(
                  duration: InkMotion.fast,
                  curve: InkMotion.standard,
                  padding: const EdgeInsets.symmetric(
                    horizontal: InkSpacing.m + 2,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? cs.primaryContainer
                        : context.ink.groupedBackground,
                    borderRadius: BorderRadius.circular(InkRadius.pill),
                    border: Border.all(
                      color: context.ink.hairline,
                      width: InkStroke.hairline,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: InkMotion.fast,
                    switchInCurve: InkMotion.standard,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.35),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Text(
                      isCurrent ? '第 $_week 周 · 本周' : '第 $_week 周',
                      key: ValueKey('wk-$_week-$isCurrent'),
                      style: InkTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? cs.onPrimaryContainer : cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_estimatedWeek != null && _week != _estimatedWeek)
            TextButton(
              onPressed: () => _setWeek(_estimatedWeek!),
              child: const Text('回本周'),
            ),
          const SizedBox(width: InkSpacing.xs),
          _iconButton(
            AppIcons.chevronRight,
            _week < 25,
            () => _setWeek(_week + 1),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, bool enabled, VoidCallback onTap) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon),
      visualDensity: VisualDensity.compact,
    );
  }

  void _pickWeek() {
    showInkSheet(
      context,
      title: '选择周次',
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 5,
        childAspectRatio: 1.8,
        children: [
          for (var w = 1; w <= 25; w++)
            Padding(
              padding: const EdgeInsets.all(InkSpacing.xs),
              child: ChoiceChip(
                label: Text('$w'),
                selected: w == _week,
                onSelected: (_) {
                  setState(() => _week = w);
                  Navigator.pop(context);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// 课表主体：星期表头吸顶，只让课程网格上下滚动。
  Widget _buildTimetable(Timetable t) {
    final term = ref.read(termProvider('timetable'));
    final termIsCurrent = term == TermUtils.currentTerm();

    // 本周有课的课程（按课程名分配固定颜色）
    // 无论当前学期还是历史学期，都按所选周次过滤，避免旧学期把所有课程堆到同一周。
    final courses = t.courses
        .where((c) => c.isScheduled)
        .where((c) => c.weeks.isEmpty || c.weeks.contains(_week))
        .toList();

    // 每个星期几对应的日期（仅当前学期按估算开学日计算，历史学期不显示）
    final weekStart = TermUtils.weekStartDate(term, _week);
    final now = DateTime.now();
    // 用"日历日"（仅年月日）计算今天相对本周一差几天，避免时间分量导致 ±1 偏差。
    final wsDay = weekStart == null
        ? null
        : DateTime(weekStart.year, weekStart.month, weekStart.day);
    final nowDay = DateTime(now.year, now.month, now.day);
    final todayCol = wsDay == null ? -1 : nowDay.difference(wsDay).inDays;
    final hasToday = termIsCurrent && todayCol >= 0 && todayCol < 7;

    final palette = InkCourseTints.of(context);
    final colorMap = <String, int>{};
    for (final c in courses) {
      colorMap.putIfAbsent(c.kcmc, () => colorMap.length % palette.length);
    }

    return Column(
      children: [
        // 星期表头固定在滚动区外，上下滑动课表时保持不动。
        _buildDayHeader(
          weekStart: weekStart,
          todayCol: todayCol,
          hasToday: hasToday,
        ),
        Expanded(
          child: InkRefresh(
            onRefresh: () => ref.read(timetableProvider.notifier).refresh(),
            successMessage: '课表已刷新',
            child: SingleChildScrollView(
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildGrid(
                    t,
                    courses: courses,
                    colorMap: colorMap,
                    palette: palette,
                    todayCol: todayCol,
                    hasToday: hasToday,
                  ),
                  if (t.sjk.isNotEmpty) ...[
                    InkSectionHeader(
                      title: '实践课程',
                      padding: const EdgeInsets.fromLTRB(
                        InkSpacing.l,
                        InkSpacing.l,
                        InkSpacing.l,
                        InkSpacing.s,
                      ),
                    ),
                    ...t.sjk.map(_buildSjkCard),
                  ],
                  SizedBox(height: inkPagePadding(context).bottom),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayHeader({
    required DateTime? weekStart,
    required int todayCol,
    required bool hasToday,
  }) {
    const leftW = 48.0;
    final dayW = (MediaQuery.sizeOf(context).width - leftW) / 7;
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        const SizedBox(width: leftW),
        for (var d = 1; d <= 7; d++)
          SizedBox(
            width: dayW,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: hasToday && (d - 1) == todayCol
                        ? cs.primary
                        : Colors.transparent,
                    child: Text(
                      _dayNames[d],
                      style: InkTextStyles.caption.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: hasToday && (d - 1) == todayCol
                            ? cs.onPrimary
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (weekStart != null) ...[
                    const SizedBox(height: 2),
                    _DayDateChip(
                      date: weekStart.add(Duration(days: d - 1)),
                      emphasized: hasToday && (d - 1) == todayCol,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGrid(
    Timetable t, {
    required List<CourseEntry> courses,
    required Map<String, int> colorMap,
    required List<(Color, Color)> palette,
    required int todayCol,
    required bool hasToday,
  }) {
    // 卡片高度与字号同步放大，二号字重/行距保证小格内仍可读。
    const rowH = 66.0;
    const leftW = 48.0;
    final gridH = t.maxSection * rowH;
    final dayW = (MediaQuery.sizeOf(context).width - leftW) / 7;

    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      height: gridH,
      child: Stack(
        children: [
          // 节次号 + 网格线
          Row(
            children: [
              SizedBox(
                width: leftW,
                child: Column(
                  children: [
                    // 逐节显示：节次号 + 该节的起止时间（与教务处课表一致）
                    for (var s = 1; s <= t.maxSection; s++)
                      SizedBox(
                        height: rowH,
                        // 作息只到 10 节；超出的行不显示时间标签
                        child: _blockTimes[s] == null
                            ? null
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$s',
                                    style: InkTextStyles.label.copyWith(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: context.ink.secondaryLabel,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _blockTimes[s]!.$1,
                                    style: InkTextStyles.micro.copyWith(
                                      fontSize: 10.5,
                                      color: context.ink.secondaryLabel,
                                    ),
                                  ),
                                  Text(
                                    _blockTimes[s]!.$2,
                                    style: InkTextStyles.micro.copyWith(
                                      fontSize: 10.5,
                                      color: context.ink.secondaryLabel,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    for (var s = 0; s < t.maxSection; s++)
                      Container(
                        height: rowH,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Theme.of(context).dividerTheme.color!,
                              width: InkStroke.hairline,
                            ),
                            right: s < 6
                                ? BorderSide(
                                    color: Theme.of(context)
                                        .dividerTheme
                                        .color!,
                                    width: InkStroke.hairline,
                                  )
                                : BorderSide.none,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // 今日列高亮（星期 + 日期吻合才高亮）
          if (hasToday)
            Positioned(
              left: leftW + dayW * todayCol,
              top: 0,
              width: dayW,
              height: gridH,
              child: IgnorePointer(
                child: Container(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: 0.25),
                ),
              ),
            ),
          // 课程卡片
          for (final c in courses)
            Positioned(
              left: leftW + dayW * (c.weekday - 1) + 2,
              top: (c.startSection - 1) * rowH + 2,
              width: dayW - 4,
              height: (c.endSection - c.startSection + 1) * rowH - 4,
              child: _CourseCard(
                course: c,
                color: palette[colorMap[c.kcmc] ?? 0],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSjkCard(CourseEntry c) {
    return InkCard(
      margin: const EdgeInsets.fromLTRB(
        InkSpacing.l,
        0,
        InkSpacing.l,
        InkSpacing.s + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.kcmc, style: context.tsBodyStrong),
          const SizedBox(height: InkSpacing.xs),
          Text(
            [
              if (c.teacher.isNotEmpty) c.teacher,
              if (c.room.isNotEmpty) c.room,
              if (c.zcd.isNotEmpty) c.zcd,
            ].join(' · '),
            style: context.tsCaption,
          ),
        ],
      ),
    );
  }
}

/// 课表星期栏下方的日期小标签，如 "9/1"；今天用主色强调
class _DayDateChip extends StatelessWidget {
  final DateTime date;
  final bool emphasized;
  const _DayDateChip({required this.date, required this.emphasized});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: emphasized
          ? BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Text(
        '${date.month}/${date.day}',
        style: InkTextStyles.micro.copyWith(
          fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
          color: emphasized ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final CourseEntry course;
  final (Color, Color) color;

  const _CourseCard({required this.course, required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.$1,
      borderRadius: BorderRadius.circular(InkRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(InkRadius.control),
        onTap: () => showCourseDetail(context, course),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 5, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course.kcmc,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: InkTextStyles.micro.copyWith(
                  fontSize: 11.5,
                  height: 1.18,
                  letterSpacing: -0.1,
                  fontWeight: FontWeight.w600,
                  color: color.$2,
                ),
              ),
              if (course.room.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    course.room,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: InkTextStyles.micro.copyWith(
                      fontSize: 10,
                      height: 1.1,
                      color: color.$2.withValues(alpha: 0.82),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 课程详情底部弹层（点击课程卡片或通知直达时复用）
void showCourseDetail(BuildContext context, CourseEntry course) {
  showInkSheet(
    context,
    title: course.kcmc,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow(
          context,
          AppIcons.teacher,
          course.teacher.isEmpty ? '—' : course.teacher,
        ),
        _detailRow(
          context,
          AppIcons.location,
          course.room.isEmpty ? '—' : course.room,
        ),
        _detailRow(
          context,
          AppIcons.week,
          course.zcd.isEmpty ? '—' : course.zcd,
        ),
        _detailRow(
          context,
          AppIcons.time,
          '星期${_dayNames[course.weekday]} 第${course.startSection}-${course.endSection}节'
          '${_courseTime(course).isEmpty ? '' : ' · ${_courseTime(course)}'}',
        ),
      ],
    ),
  );
}

Widget _detailRow(BuildContext context, IconData icon, String text) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 20, color: context.scheme.onSurfaceVariant),
        const SizedBox(width: InkSpacing.m),
        Expanded(child: Text(text, style: context.tsBody)),
      ],
    ),
  );
}

/// 今日概览聚合卡：今日课程 / 下节课倒计时 / 考试倒计时（点击展开）
class _TodayOverview extends ConsumerStatefulWidget {
  const _TodayOverview();

  @override
  ConsumerState<_TodayOverview> createState() => _TodayOverviewState();
}

class _TodayOverviewState extends ConsumerState<_TodayOverview> {
  bool _expanded = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 每 30 秒按系统时间重算一次，保证「上课中/还有 X 分钟下课」及时变化
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final timetable = ref.watch(timetableProvider);
    final exams = ref.watch(examsProvider);

    return timetable.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (t) {
        // 今日课程（按当前实际周期计算，始终反映“今天”）
        final now = DateTime.now();
        final week =
            TermUtils.estimatedCurrentWeek(
              ref.read(termProvider('timetable')),
            ) ??
            1;
        final today =
            t.courses
                .where(
                  (c) =>
                      c.isScheduled &&
                      c.weekday == now.weekday &&
                      c.weeks.contains(week),
                )
                .toList()
              ..sort((a, b) => a.startSection.compareTo(b.startSection));

        // 按系统时间区分三种状态：上课前（下节课倒计时）/ 上课中（距下课）/ 已下课
        CourseEntry? current;
        CourseEntry? next;
        final nowMin = now.hour * 60 + now.minute;
        for (final c in today) {
          final s = _startOf(c);
          final e = _endOf(c);
          if (s <= nowMin && nowMin < e) {
            // 同一时刻若有多门（极少见），取开始更晚的那门
            if (current == null || s > _startOf(current)) current = c;
          } else if (s > nowMin && (next == null || s < _startOf(next))) {
            next = c;
          }
        }

        // 最近一场未开始的考试（仅当前学期：考试页可能自动回退到上学期）
        Exam? nextExam;
        if (exams.hasValue &&
            ref.watch(termProvider('exam')) == TermUtils.currentTerm()) {
          DateTime? bestDt;
          for (final e in exams.value ?? const <Exam>[]) {
            final dt = e.startAt;
            if (dt != null &&
                dt.isAfter(now) &&
                (bestDt == null || dt.isBefore(bestDt))) {
              bestDt = dt;
              nextExam = e;
            }
          }
        }

        _todayNonEmpty = today.isNotEmpty; // 供摘要区分“课余”/“没课”
        final subtitle = _subtitle(now, current, next, nextExam);
        return InkCard(
          margin: const EdgeInsets.fromLTRB(
            InkSpacing.l,
            InkSpacing.s,
            InkSpacing.l,
            InkSpacing.xs,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(AppIcons.today, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${now.month}月${now.day}日 周${_dayNames[now.weekday]} · 第$week周',
                    style: InkTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (today.isNotEmpty)
                    Text('今日 ${today.length} 节', style: context.tsSecondary),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: InkMotion.fast,
                    curve: InkMotion.standard,
                    child: Icon(
                      AppIcons.expandMore,
                      size: 16,
                      color: context.ink.secondaryLabel,
                    ),
                  ),
                ],
              ),
              // 展开/收起用尺寸动画过渡，箭头同步旋转，避免内容突变。
              AnimatedSize(
                duration: InkMotion.normal,
                curve: InkMotion.emphasized,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: context.tsSecondary),
                    ],
                    if (_expanded) ...[
                      const SizedBox(height: 6),
                      const Divider(height: 1),
                      const SizedBox(height: 4),
                      if (today.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text('今天没课', style: context.tsCaption),
                        )
                      else
                        ...today.map(
                          (c) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 74,
                                  child: Text(
                                    _courseTime(c),
                                    style: InkTextStyles.label.copyWith(
                                      color: context.ink.secondaryLabel,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: InkSpacing.m),
                                Expanded(
                                  child: Text(
                                    c.kcmc,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: InkTextStyles.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (c.room.isNotEmpty) ...[
                                  const SizedBox(width: InkSpacing.m),
                                  Text(c.room, style: context.tsSecondary),
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (nextExam != null) ...[
                        const Divider(height: 1),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              AppIcons.examEvent,
                              size: 15,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '考试 ${nextExam.kcmc}（${_fmtDate(nextExam.kssj)}）',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.tsCaption,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 摘要：上课中（距下课）/ 下节课倒计时 / 已下课 / 没课 + 距考试天数
  String? _subtitle(
    DateTime now,
    CourseEntry? current,
    CourseEntry? next,
    Exam? nextExam,
  ) {
    final nowMin = now.hour * 60 + now.minute;
    String s;
    if (current != null) {
      final remain = _endOf(current) - nowMin;
      final left = remain <= 1 ? '即将下课' : '还有 $remain 分钟下课';
      final room = current.room.isEmpty ? '' : ' · ${current.room}';
      s = '正在上 ${current.kcmc}$room · $left';
    } else if (next != null) {
      final hm = _sectionStartTime(next.startSection) ?? '';
      final inMin = _startOf(next) - nowMin;
      s = '下节课 $hm ${next.kcmc} · ${_inText(inMin)}';
    } else if (_todayNonEmpty) {
      s = '今日课程已结束';
    } else {
      s = '今天没课';
    }
    if (nextExam != null) {
      final dt = nextExam.startAt;
      if (dt != null) {
        final days = dt
            .difference(DateTime(now.year, now.month, now.day))
            .inDays;
        s += ' · 距考试 $days 天';
      }
    }
    return s;
  }

  /// 距开始时间的可读文案（超过 1 小时拆成小时 + 分钟）
  String _inText(int minutes) {
    if (minutes <= 0) return '即将开始';
    if (minutes < 60) return '$minutes 分钟后';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h 小时后' : '$h 小时 $m 分钟后';
  }

  // 供 _subtitle 识别“今日是否曾排课”的标记（在 build 中按需赋）
  bool _todayNonEmpty = true;

  int _startOf(CourseEntry c) {
    final hm = _sectionStartTime(c.startSection);
    if (hm == null) return 0;
    final p = hm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  int _endOf(CourseEntry c) {
    final hm = _sectionEndTime(c.endSection);
    if (hm == null) return _startOf(c);
    final p = hm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  String _fmtDate(String raw) {
    final dt = parseJwDateTime(raw);
    return dt == null ? raw : '${dt.month}月${dt.day}日';
  }
}
