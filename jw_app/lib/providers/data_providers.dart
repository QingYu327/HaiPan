import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jw_apis.dart';
import '../api/usage_api.dart';
import '../models/models.dart';
import '../util/app_log.dart';
import '../util/campus_tunnel.dart';
import '../util/home_widget.dart';
import '../util/local_cache.dart';
import '../util/refresh_gate.dart';
import '../util/term_utils.dart';
import 'session_provider.dart';

/// 各页面独立学期（课表/成绩/考试/学业互不影响），
/// scope：timetable / grade / exam / academic
final termProvider = StateProvider.family<Term, String>(
  (ref, scope) => TermUtils.currentTerm(),
);

/// 入学年份：按学号前 4 位判定（如 20241xxx → 2024），
/// 用于屏蔽入学前的学期选项；解析失败时回退到较宽松的 2020
final enrollmentYearProvider = Provider<int>((ref) {
  final xh = ref.watch(sessionProvider).student.xh;
  final y = xh.length >= 4 ? int.tryParse(xh.substring(0, 4)) : null;
  return (y != null && y >= 2000 && y <= 2100) ? y : 2020;
});

/// 课表：磁盘缓存优先秒开，随后后台静默刷新
final timetableProvider = AsyncNotifierProvider<TimetableNotifier, Timetable>(
  TimetableNotifier.new,
);

class TimetableNotifier extends AsyncNotifier<Timetable> {
  String? _key;

  static String keyOf(Term term) => 'cache_timetable_${term.xnm}_${term.xqm}';

  @override
  Future<Timetable> build() async {
    final term = ref.watch(termProvider('timetable'));
    final key = keyOf(term);
    _key = key;
    final cached = await LocalCache.read(key);
    if (cached != null) {
      try {
        final t = Timetable.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        );
        AppLog.d('缓存', '课表 ${term.shortLabel} 缓存秒开 ${t.courses.length} 门');
        unawaited(_refreshIfStale(term, key));
        return t;
      } catch (_) {
        // 缓存损坏则走在线
      }
    }
    return _fetch(term, key);
  }

  Future<Timetable> _fetch(Term term, String key) async {
    final t = await ref.read(timetableApiProvider).fetch(term);
    await LocalCache.write(key, jsonEncode(t.toJson()));
    AppLog.d('课表', '${term.shortLabel} 在线拉取成功 ${t.courses.length} 门');
    return t;
  }

  /// 后台静默刷新：成功才替换页面数据，失败保留缓存
  Future<void> _silentRefresh(Term term, String key) async {
    try {
      // 自动刷新走闸门，避免与其它页面的自动刷新同时抢占公网通道
      final t = await RefreshGate.instance.run(() => _fetch(term, key));
      if (_key == key) state = AsyncValue.data(t);
    } catch (e) {
      AppLog.e('课表', '${term.shortLabel} 后台刷新失败：$e');
    }
  }

  /// 缓存仍新鲜时不打网络：避免每次进页面都并发抢占公网通道
  Future<void> _refreshIfStale(Term term, String key) async {
    if (await LocalCache.isFresh(key)) return;
    await _silentRefresh(term, key);
  }

  /// 下拉刷新 / 重试：强制走在线
  Future<void> refresh() async {
    final term = ref.read(termProvider('timetable'));
    final key = keyOf(term);
    _key = key;
    try {
      final t = await _fetch(term, key);
      state = AsyncValue.data(t);
    } catch (e, st) {
      if (state.value == null) state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

/// 当前学期课表（不随课表页的学期选择变化），用于通识/学业等跨页校正。
/// 优先复用课表页已加载的数据；若课表页停在其他学期，则直接读本学期待缓存。
final currentTimetableProvider = FutureProvider<Timetable?>((ref) async {
  final current = TermUtils.currentTerm();
  final selected = ref.watch(termProvider('timetable'));
  final tt = ref.watch(timetableProvider);
  if (selected == current) return tt.valueOrNull;
  final raw = await LocalCache.read(TimetableNotifier.keyOf(current));
  if (raw == null || raw.isEmpty) return null;
  try {
    return Timetable.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
});

/// 成绩 + 汇总：缓存优先，进入页面后后台刷新
final gradesProvider =
    AsyncNotifierProvider<GradesNotifier, (List<Grade>, GradeSummary)>(
      GradesNotifier.new,
    );

class GradesNotifier extends AsyncNotifier<(List<Grade>, GradeSummary)> {
  String? _key;

  static String keyOf(Term term) => 'cache_grade_${term.xnm}_${term.xqm}';

  @override
  Future<(List<Grade>, GradeSummary)> build() async {
    final term = ref.watch(termProvider('grade'));
    final key = keyOf(term);
    _key = key;
    final cached = await LocalCache.read(key);
    if (cached != null) {
      try {
        final list = (jsonDecode(cached) as List)
            .map((e) => Grade.fromJson(e as Map<String, dynamic>))
            .toList();
        AppLog.d('缓存', '成绩 ${term.shortLabel} 缓存秒开 ${list.length} 条');
        unawaited(_refreshIfStale(term, key));
        return (list, GradeSummary.of(list));
      } catch (_) {}
    }
    return _fetch(term, key);
  }

  Future<(List<Grade>, GradeSummary)> _fetch(Term term, String key) async {
    final list = await ref.read(gradeApiProvider).fetch(term);
    await LocalCache.write(key, jsonEncode([for (final g in list) g.toJson()]));
    AppLog.d('成绩', '${term.shortLabel} 在线拉取成功 ${list.length} 条');
    return (list, GradeSummary.of(list));
  }

  Future<void> _silentRefresh(Term term, String key) async {
    try {
      final d = await RefreshGate.instance.run(() => _fetch(term, key));
      if (_key == key) state = AsyncValue.data(d);
    } catch (e) {
      AppLog.e('成绩', '${term.shortLabel} 后台刷新失败：$e');
    }
  }

  /// 缓存仍新鲜时不打网络（手动下拉刷新不受限）
  Future<void> _refreshIfStale(Term term, String key) async {
    if (await LocalCache.isFresh(key)) return;
    await _silentRefresh(term, key);
  }

  Future<void> refresh() async {
    final term = ref.read(termProvider('grade'));
    final key = keyOf(term);
    _key = key;
    try {
      final d = await _fetch(term, key);
      state = AsyncValue.data(d);
      // 手动刷新承担"全部重新拉取"：顺带让成绩分项明细缓存失效
      await LocalCache.removeWhere(
        (k) => k.startsWith('cache_grade_detail_'),
      );
    } catch (e, st) {
      if (state.value == null) state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

/// 考试安排：缓存优先，进入页面后后台刷新
final examsProvider = AsyncNotifierProvider<ExamsNotifier, List<Exam>>(
  ExamsNotifier.new,
);

class ExamsNotifier extends AsyncNotifier<List<Exam>> {
  String? _key;

  static String keyOf(Term term) => 'cache_exam_${term.xnm}_${term.xqm}';

  @override
  Future<List<Exam>> build() async {
    final term = ref.watch(termProvider('exam'));
    final key = keyOf(term);
    _key = key;
    final cached = await LocalCache.read(key);
    if (cached != null) {
      try {
        final list =
            (jsonDecode(cached) as List)
                .map((e) => Exam.fromJson(e as Map<String, dynamic>))
                .toList()
              ..sort((a, b) => a.kssj.compareTo(b.kssj));
        AppLog.d('缓存', '考试 ${term.shortLabel} 缓存秒开 ${list.length} 场');
        unawaited(_refreshIfStale(term, key));
        return list;
      } catch (_) {}
    }
    return _fetch(term, key);
  }

  Future<List<Exam>> _fetch(Term term, String key) async {
    final list = await ref.read(examApiProvider).fetch(term);
    list.sort((a, b) => a.kssj.compareTo(b.kssj));
    await LocalCache.write(key, jsonEncode([for (final e in list) e.toJson()]));
    AppLog.d('考试', '${term.shortLabel} 在线拉取成功 ${list.length} 场');
    return list;
  }

  Future<void> _silentRefresh(Term term, String key) async {
    try {
      final list = await RefreshGate.instance.run(() => _fetch(term, key));
      if (_key == key) state = AsyncValue.data(list);
    } catch (e) {
      AppLog.e('考试', '${term.shortLabel} 后台刷新失败：$e');
    }
  }

  /// 缓存仍新鲜时不打网络（手动下拉刷新不受限）
  Future<void> _refreshIfStale(Term term, String key) async {
    if (await LocalCache.isFresh(key)) return;
    await _silentRefresh(term, key);
  }

  Future<void> refresh() async {
    final term = ref.read(termProvider('exam'));
    final key = keyOf(term);
    _key = key;
    try {
      final list = await _fetch(term, key);
      state = AsyncValue.data(list);
    } catch (e, st) {
      if (state.value == null) state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}

/// 学业数据：课程分类 + 修读总览
typedef AcademicData = ({
  List<AcademicCategory> categories,
  AcademicOverview overview,
});

/// 学业情况：磁盘缓存优先秒开（进入页面不卡加载），成功后后台静默刷新
final academicProvider =
    NotifierProvider<AcademicNotifier, AsyncValue<AcademicData>>(
      AcademicNotifier.new,
    );

class AcademicNotifier extends Notifier<AsyncValue<AcademicData>> {
  String? _activeKey; // 防止旧学期的慢请求覆盖新数据

  @override
  AsyncValue<AcademicData> build() {
    final term = ref.watch(termProvider('academic'));
    final xh = ref.watch(sessionProvider).student.xh;
    // 后台跑缓存优先 + 在线刷新（不阻塞 build）
    _load(term, xh);
    return const AsyncValue.loading();
  }

  String _cacheKey(Term term) => 'cache_academic_v2_${term.xnm}_${term.xqm}';

  /// 已有关键路径：读磁盘缓存即时展示，缓存过期才后台拉取更新
  Future<void> _load(Term term, String xh, {bool force = false}) async {
    final key = _cacheKey(term);
    _activeKey = key;
    // 1) 磁盘缓存优先（秒开，数据即当前正确口径）
    var hasCache = false;
    try {
      final cached = await LocalCache.read(key);
      if (cached != null) {
        hasCache = true;
        AppLog.d('缓存', '学业 ${term.shortLabel} 命中本地缓存');
        state = AsyncValue.data(
          _academicDecode(jsonDecode(cached) as Map<String, dynamic>),
        );
      }
    } catch (_) {
      // 缓存损坏则忽略，走在线拉取
    }
    // 2) 缓存仍新鲜则跳过自动刷新（手动下拉/重试始终强制在线）
    // 学业需串行/多路拉取全部计划，公网高延迟下成本最高；口径变化很慢，
    // 因此自动刷新窗口放宽到 30 分钟，手动刷新仍立即走在线。
    if (!force &&
        hasCache &&
        await LocalCache.isFresh(key, const Duration(minutes: 30))) {
      return;
    }
    // 自动刷新走闸门（学业是多计划请求，最久，排到前两位即可）
    if (force) {
      await _refreshOnline(term, xh, key);
    } else {
      await RefreshGate.instance.run(() => _refreshOnline(term, xh, key));
    }
  }

  Future<void> _refreshOnline(Term term, String xh, String key) async {
    try {
      final d = await ref.read(academicApiProvider).fetch(xh, term);
      await LocalCache.write(key, _academicEncode(d));
      AppLog.d('学业', '${term.shortLabel} 在线刷新成功 ${d.overview.planCourses} 门');
      if (state.value == null || _activeKey == key) {
        state = AsyncValue.data(d);
      }
    } catch (e) {
      AppLog.e('学业', '${term.shortLabel} 在线刷新失败：$e');
      if (state.value == null) {
        state = AsyncValue.error(e, StackTrace.current);
      }
    }
  }

  /// 手动刷新（下拉 / 重试按钮）：强制走在线
  Future<void> refresh() async {
    final term = ref.read(termProvider('academic'));
    final xh = ref.read(sessionProvider).student.xh;
    await _load(term, xh, force: true);
  }
}

String _str(Object? v) => v?.toString() ?? '';

String _academicEncode(
  ({List<AcademicCategory> categories, AcademicOverview overview}) d,
) {
  return jsonEncode({
    'categories': [
      for (final c in d.categories)
        {
          'name': c.name,
          'courses': [
            for (final o in c.courses)
              {
                'kcmc': o.kcmc,
                'cj': o.cj,
                'jd': o.jd,
                'xf': o.xf,
                'kclbmc': o.kclbmc,
                'kcgsmc': o.kcgsmc,
                'kcXzmc': o.kcXzmc,
                'xnmc': o.xnmc,
                'xqmmc': o.xqmmc,
                'status': o.status.name,
              },
          ],
        },
    ],
    'overview': {
      'gpa': d.overview.gpa,
      'planCourses': d.overview.planCourses,
      'passed': d.overview.passed,
      'failed': d.overview.failed,
      'notStarted': d.overview.notStarted,
      'inProgress': d.overview.inProgress,
      'stats': [
        for (final s in d.overview.categories)
          {
            'name': s.name,
            'requireCredit': s.requireCredit,
            'earnedCredit': s.earnedCredit,
            'totalCourse': s.totalCourse,
            'passedCourse': s.passedCourse,
          },
      ],
    },
  });
}

({List<AcademicCategory> categories, AcademicOverview overview})
_academicDecode(Map<String, dynamic> json) {
  final cats = (json['categories'] as List? ?? [])
      .map(
        (c) => AcademicCategory(
          name: _str(c['name']),
          courses: ((c['courses'] as List?) ?? [])
              .map(
                (o) => AcademicCourse(
                  kcmc: _str(o['kcmc']),
                  cj: _str(o['cj']),
                  jd: _str(o['jd']),
                  xf: (o['xf'] as num?)?.toDouble() ?? 0,
                  kclbmc: _str(o['kclbmc']),
                  kcgsmc: _str(o['kcgsmc']),
                  kcXzmc: _str(o['kcXzmc']),
                  xnmc: _str(o['xnmc']),
                  xqmmc: _str(o['xqmmc']),
                  status: CourseStatus.values.firstWhere(
                    (v) => v.name == o['status'],
                    orElse: () => CourseStatus.planned,
                  ),
                ),
              )
              .toList(),
        ),
      )
      .toList();
  final ov = json['overview'] as Map<String, dynamic>? ?? {};
  final stats = (ov['stats'] as List? ?? [])
      .map(
        (s) => AcademicCategoryStat(
          name: _str(s['name']),
          requireCredit: (s['requireCredit'] as num?)?.toDouble() ?? 0,
          earnedCredit: (s['earnedCredit'] as num?)?.toDouble() ?? 0,
          totalCourse: (s['totalCourse'] as num?)?.toInt() ?? 0,
          passedCourse: (s['passedCourse'] as num?)?.toInt() ?? 0,
        ),
      )
      .toList();
  final overview = AcademicOverview(
    gpa: (ov['gpa'] as num?)?.toDouble(),
    planCourses: (ov['planCourses'] as num?)?.toInt() ?? 0,
    passed: (ov['passed'] as num?)?.toInt() ?? 0,
    failed: (ov['failed'] as num?)?.toInt() ?? 0,
    notStarted: (ov['notStarted'] as num?)?.toInt() ?? 0,
    inProgress: (ov['inProgress'] as num?)?.toInt() ?? 0,
    categories: stats,
  );
  return (categories: cats, overview: overview);
}

/// 排名页元信息（学年学期选项 + 成绩性质/统计范围筛选条件）
/// 筛选选项本地缓存：进页面先出表单，查询结果仍必须在线拉取。
final rankMetaProvider = FutureProvider<RankPageMeta>((ref) async {
  const key = 'cache_rank_meta_v1';
  final cached = await LocalCache.read(key);
  if (cached != null) {
    try {
      final m = jsonDecode(cached) as Map<String, dynamic>;
      List<RankOption> opts(Object? raw) => [
        for (final e in (raw as List? ?? const []))
          RankOption(
            value: '${(e as Map)['value'] ?? ''}',
            label: '${e['label'] ?? ''}',
          ),
      ];
      return RankPageMeta(
        xnqOptions: opts(m['xnq']),
        cjxzmOptions: opts(m['cjxzm']),
        tjfwOptions: opts(m['tjfw']),
        defCjxzm: '${m['defCjxzm'] ?? ''}',
        defTjfw: '${m['defTjfw'] ?? ''}',
      );
    } catch (_) {
      // 缓存损坏则走在线
    }
  }
  final meta = await ref.read(rankApiProvider).fetchPageMeta();
  await LocalCache.write(
    key,
    jsonEncode({
      'xnq': [
        for (final o in meta.xnqOptions) {'value': o.value, 'label': o.label},
      ],
      'cjxzm': [
        for (final o in meta.cjxzmOptions) {'value': o.value, 'label': o.label},
      ],
      'tjfw': [
        for (final o in meta.tjfwOptions) {'value': o.value, 'label': o.label},
      ],
      'defCjxzm': meta.defCjxzm,
      'defTjfw': meta.defTjfw,
    }),
  );
  return meta;
});

/// 排名查询（family：(起始学期, 终止学期, 成绩性质, 统计范围)）
final rankResultProvider = FutureProvider.autoDispose
    .family<RankResult, (String, String, String, String)>((ref, q) {
      return ref
          .watch(rankApiProvider)
          .query(qsXnxq: q.$1, zzXnxq: q.$2, cjxzm: q.$3, tjfw: q.$4);
    });

/// 云端风控：当前登录学号在全部受控功能上的授权（调试/统计/更新）。
/// 返回 `Map<feature, allowed>`；开发者本人恒放行。
final featureGatesProvider = FutureProvider.autoDispose<Map<String, bool>>((
  ref,
) {
  final xh = ref.watch(sessionProvider).student.xh;
  return UsageTracker.fetchGates(xh);
});

/// APP 整体准入：仅在公网通道下校验名单，校园网直连不拦截。
/// 未登录/游客不在此拦截；开发者恒放行；离线回退上次成功结果。
final appAccessProvider = FutureProvider.autoDispose<bool>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session.status != SessionStatus.loggedIn) return true;
  // 校园网直连（未启用公网通道）不做名单校验
  if (!ref.watch(campusTunnelProvider).isPublicNetwork) {
    AppLog.d('准入', '校园网直连，跳过公网准入校验');
    return true;
  }
  final xh = session.student.xh.trim().isEmpty
      ? session.savedUsername.trim()
      : session.student.xh.trim();
  if (xh.isEmpty) return false; // 已登录却拿不到学号：默认拒绝

  // 秒开：命中上次结果立即放行，同时在后台复核并刷新缓存。
  // 冷启动不再等网络，避免公网入口下卡 5s；权限变化在下次启动生效。
  final cached = await UsageTracker.cachedAppAllowed(xh);
  if (cached != null) {
    AppLog.d('准入', '使用缓存结果 ${cached ? '通过' : '拒绝'}');
    unawaited(UsageTracker.fetchGates(xh).catchError((_) => <String, bool>{}));
    return cached;
  }

  // 首次使用（无缓存）必须在线校验，超时按拒绝处理
  final sw = Stopwatch()..start();
  try {
    final gates = await UsageTracker.fetchGates(xh)
        .timeout(const Duration(seconds: 6));
    AppLog.d('准入', '在线校验 ${sw.elapsedMilliseconds}ms');
    return gates[UsageTracker.gateApp] ?? false;
  } catch (_) {
    AppLog.w('准入', '在线校验失败 ${sw.elapsedMilliseconds}ms，按拒绝处理');
    return false;
  }
});

/// 桌面小组件数据同步：课表与考试都就绪后写入快照并通知原生刷新。
/// 由首页常驻监听，登录后即使不打开课表/考试页也能更新小组件。
final homeWidgetSyncProvider = Provider<void>((ref) {
  final timetable = ref.watch(timetableProvider).valueOrNull;
  final exams = ref.watch(examsProvider).valueOrNull;
  if (timetable == null || exams == null) return;
  unawaited(HomeWidgetSync.update(timetable, exams));
});
