import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';
import '../../providers/data_providers.dart';
import '../../theme/ink_tokens.dart';
import '../widgets/common.dart';
import '../widgets/ink_page.dart';

/// 通识教育拓展课学分统计：按子分类（KCGSMC）汇总已修学分，
/// 每个分类的最低要求可在页面内单独调整并持久化。
class GeCreditPage extends ConsumerStatefulWidget {
  const GeCreditPage({super.key});

  @override
  ConsumerState<GeCreditPage> createState() => _GeCreditPageState();
}

class _GeCreditPageState extends ConsumerState<GeCreditPage> {
  static const _prefsKey = 'ge_min_credits';
  static const double _defaultMin = 2.0;

  /// 分类名 → 最低学分要求（本地配置，默认 2.0）
  Map<String, double> _mins = {};

  @override
  void initState() {
    super.initState();
    _loadMins();
  }

  Future<void> _loadMins() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = <String, double>{
        for (final e in m.entries)
          if (e.value is num) e.key: (e.value as num).toDouble(),
      };
      if (mounted) setState(() => _mins = parsed);
    } catch (_) {
      // 配置损坏则按默认值处理
    }
  }

  Future<void> _saveMin(String category, double value) async {
    setState(() => _mins = {..._mins, category: value});
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, jsonEncode(_mins));
    } catch (_) {}
  }

  double _minOf(String category) => _mins[category] ?? _defaultMin;

  /// 是否为通识教育拓展课。
  /// 唯一可靠标识是 KCLBMC=「通识教育拓展课」：
  /// 「通识教育课」（大学英语、体育等）和专业课（如专业导论）也带 KCGSMC，
  /// 不能仅凭子分类或关键词判断，否则会把非拓展课混进统计。
  /// 个别在修课程类别字段为空，仅在类别为空时按子分类名精确兜底。
  static bool _isGe(AcademicCourse c) {
    final lb = c.kclbmc.trim();
    if (lb.isNotEmpty) return lb.contains('通识教育拓展');
    final gs = c.kcgsmc.trim();
    if (gs.isEmpty) return false;
    return _categories.any(gs.contains);
  }

  /// 通识拓展课的七个固定分类（顺序即展示顺序）
  static const List<String> _categories = [
    '人文艺术类',
    '大数据及信息技术类',
    '外语拓展类',
    '科研与创新教育类',
    '科技文明与海洋科学类',
    '农业发展与生态文明类',
    '道德法律与经济管理类',
  ];

  /// 按课程标识中的关键词兜底归类
  static const Map<String, List<String>> _keywords = {
    '人文艺术类': ['人文', '艺术'],
    '大数据及信息技术类': ['大数据', '信息技术', '计算机'],
    '外语拓展类': ['外语'],
    '科研与创新教育类': ['科研', '创新'],
    '科技文明与海洋科学类': ['科技文明', '海洋科学', '科技', '海洋'],
    '农业发展与生态文明类': ['农业', '生态文明', '生态'],
    '道德法律与经济管理类': ['道德', '法律', '经济', '管理'],
  };

  /// 优先按子分类（KCGSMC）精确归类，其次用课程名关键词兜底。
  /// 不能用 KCLBMC 参与关键词匹配：拓展课该字段统一是「通识教育拓展课」，
  /// 参与匹配反而会把「管理」「信息技术」等误当成类别依据。
  static String _categoryOf(AcademicCourse c) {
    final gs = c.kcgsmc;
    for (final name in _categories) {
      if (gs.contains(name)) return name;
    }
    if (gs.contains('信息技术')) return '大数据及信息技术类';
    for (final e in _keywords.entries) {
      for (final k in e.value) {
        if (c.kcmc.contains(k)) return e.key;
      }
    }
    return '其他';
  }

  /// 学业接口对部分在修通识课仍标记为「未修」，
  /// 用本学期课表的课程名把对应记录校正为「在修」，避免在修学分与计数缺失。
  static AcademicCourse _syncInProgress(
    AcademicCourse c,
    Set<String> currentNames,
  ) {
    if (c.status != CourseStatus.planned) return c;
    if (!currentNames.contains(c.kcmc.trim())) return c;
    return AcademicCourse(
      kcmc: c.kcmc,
      cj: c.cj,
      jd: c.jd,
      xf: c.xf,
      kclbmc: c.kclbmc,
      kcgsmc: c.kcgsmc,
      kcXzmc: c.kcXzmc,
      xnmc: c.xnmc,
      xqmmc: c.xqmmc,
      xdz: '1',
      status: CourseStatus.inProgress,
    );
  }

  @override
  Widget build(BuildContext context) {
    final academic = ref.watch(academicProvider);
    // 必须用"当前学期"课表校正，不能用课表页当前选中的历史学期
    final timetable = ref.watch(currentTimetableProvider).valueOrNull;
    final currentNames = <String>{
      for (final c in timetable?.courses ?? const <CourseEntry>[]) c.kcmc.trim(),
      for (final c in timetable?.sjk ?? const <CourseEntry>[]) c.kcmc.trim(),
    }..remove('');
    Future<void> refresh() => ref.read(academicProvider.notifier).refresh();
    return InkPageScaffold(
      showBack: true,
      title: '通识拓展学分',
      body: academic.when(
        loading: () => loadingView,
        error: (e, _) => InkRefresh(
          fill: true,
          onRefresh: refresh,
          child: ErrorView(error: e, onRetry: refresh),
        ),
        data: (d) {
          final courses = <AcademicCourse>[
            for (final cat in d.categories)
              for (final c in cat.courses)
                if (_isGe(c)) _syncInProgress(c, currentNames),
          ];
          if (courses.isEmpty) {
            return InkRefresh(
              fill: true,
              onRefresh: refresh,
              child: const EmptyView('暂无通识教育拓展课记录'),
            );
          }
          final groups = <String, List<AcademicCourse>>{
            for (final name in _categories) name: <AcademicCourse>[],
          };
          final others = <AcademicCourse>[];
          for (final c in courses) {
            final key = _categoryOf(c);
            if (groups.containsKey(key)) {
              groups[key]!.add(c);
            } else {
              others.add(c);
            }
          }
          // 七个固定分类始终展示，未归类的课程追加在最后
          final cats = <MapEntry<String, List<AcademicCourse>>>[
            for (final name in _categories) MapEntry(name, groups[name]!),
            if (others.isNotEmpty) MapEntry('其他', others),
          ];
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
                _SummaryCard(
                  entries: [
                    for (final e in cats)
                      (
                        name: e.key,
                        earned: _earned(e.value),
                        inProgress: _inProgress(e.value),
                        min: _minOf(e.key),
                      ),
                  ],
                ),
                const InkSectionHeader(title: '分类明细'),
                for (final e in cats)
                  _CategoryCard(
                    name: e.key,
                    courses: e.value,
                    min: _minOf(e.key),
                    onEditMin: () => _editMin(e.key),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: InkSpacing.xl,
                    vertical: InkSpacing.s,
                  ),
                  child: Text(
                    '分类依据教务系统中的课程标识自动归类，'
                    '最低学分按学校对各专业通识拓展分类的要求手动设置。',
                    style: context.tsCaption,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 调整某个分类的最低学分要求
  Future<void> _editMin(String name) async {
    var value = _minOf(name);
    final saved = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('最低学分要求'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: context.tsSecondary),
              const SizedBox(height: InkSpacing.m),
              Row(
                children: [
                  Text(value.toStringAsFixed(1), style: context.tsBodyStrong),
                  Expanded(
                    child: Slider(
                      value: value,
                      min: 0,
                      max: 10,
                      divisions: 20,
                      label: value.toStringAsFixed(1),
                      onChanged: (v) =>
                          setLocal(() => value = (v * 2).round() / 2),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, value),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != null) await _saveMin(name, saved);
  }

  double _earned(List<AcademicCourse> list) =>
      list.where((c) => c.passed).fold(0.0, (s, c) => s + c.xf);

  double _inProgress(List<AcademicCourse> list) => list
      .where((c) => c.status == CourseStatus.inProgress)
      .fold(0.0, (s, c) => s + c.xf);
}

String _fmt(double v) => v.toStringAsFixed(1);

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.entries});

  final List<({String name, double earned, double inProgress, double min})>
      entries;

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final ink = context.ink;
    final earned = entries.fold(0.0, (s, e) => s + e.earned);
    final require = entries.fold(0.0, (s, e) => s + e.min);
    final passed = entries.where((e) => e.earned + 0.001 >= e.min).length;
    final progress =
        require <= 0 ? 1.0 : (earned / require).clamp(0.0, 1.0);
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('通识拓展学分', style: context.tsBodyStrong),
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
            '已修 ${_fmt(earned)} / 要求 ${_fmt(require)} 学分',
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
              InkStat('${entries.length}', '分类'),
              InkStat('$passed', '已达标', tone: InkTone.success),
              InkStat(
                '${entries.length - passed}',
                '待补齐',
                tone: entries.length - passed > 0
                    ? InkTone.warning
                    : InkTone.neutral,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.name,
    required this.courses,
    required this.min,
    required this.onEditMin,
  });

  final String name;
  final List<AcademicCourse> courses;
  final double min;
  final VoidCallback onEditMin;

  double get _earned =>
      courses.where((c) => c.passed).fold(0.0, (s, c) => s + c.xf);

  double get _inProgress =>
      courses.where((c) => c.status == CourseStatus.inProgress).fold(
            0.0,
            (s, c) => s + c.xf,
          );

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final ink = context.ink;
    final earned = _earned;
    final passed = earned + 0.001 >= min;
    final rate = min <= 0 ? 1.0 : (earned / min).clamp(0.0, 1.0);
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
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.tsBodyStrong,
                ),
              ),
              const SizedBox(width: InkSpacing.s),
              InkTag(
                text: passed ? '已达标' : '还差 ${_fmt(min - earned)}',
                tone: passed ? InkTone.success : InkTone.warning,
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: InkSpacing.s, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: rate,
                    minHeight: 4,
                    backgroundColor: ink.groupedBackground,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '已修 ${_fmt(earned)} / 最低 ${_fmt(min)} 学分'
                      '${_inProgress > 0 ? ' · 在修 ${_fmt(_inProgress)}' : ''}',
                      style: context.tsCaption,
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onEditMin,
                      child: Text(
                        '调整要求',
                        style: InkTextStyles.label.copyWith(color: cs.primary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          children: [
            for (var i = 0; i < courses.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: InkStroke.hairline,
                  color: ink.hairline,
                ),
              _CourseRow(course: courses[i]),
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
      CourseStatus.done => course.failed
          ? ('未通过', InkTone.danger)
          : ('已修', InkTone.success),
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
