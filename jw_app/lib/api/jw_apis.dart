import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../util/app_log.dart';
import '../util/local_cache.dart';
import '../util/term_utils.dart';
import 'jw_client.dart';

/// 课表：POST /kbcx/xskbcx_cxXsgrkb.html → 结构化 JSON（kbList / sjkList / xsxx）
class TimetableApi {
  final JwClient client;
  TimetableApi(this.client);

  Future<Timetable> fetch(Term term) async {
    final resp = await client.postData('/kbcx/xskbcx_cxXsgrkb.html', {
      'xnm': term.xnm,
      'xqm': term.xqm,
      'kzlx': 'ck',
      'nd': DateTime.now().millisecondsSinceEpoch,
    }, referer: '/kbcx/xskbcx_cxXsgrkbIndex.html?gnmkdm=N2151&layout=default');
    final data = tryDecode(resp.data);
    if (data is! Map) {
      throw Exception('课表数据格式异常');
    }
    final kbList = (data['kbList'] as List? ?? [])
        .map((e) => CourseEntry.fromKb(Map<String, dynamic>.from(e)))
        .where((c) => c.kcmc.isNotEmpty)
        .toList();
    final sjkList = (data['sjkList'] as List? ?? [])
        .map((e) => CourseEntry.fromSjk(Map<String, dynamic>.from(e)))
        .where((c) => c.kcmc.isNotEmpty)
        .toList();
    final student = data['xsxx'] is Map
        ? StudentInfo.fromJson(Map<String, dynamic>.from(data['xsxx']))
        : const StudentInfo();

    var maxSection = 12;
    for (final c in kbList) {
      if (c.endSection > maxSection) maxSection = c.endSection;
    }
    return Timetable(
      courses: kbList,
      sjk: sjkList,
      student: student,
      maxSection: maxSection,
    );
  }
}

/// 成绩：POST /cjcx/cjcx_cxDgXscj.html?doType=query → jqGrid JSON
class GradeApi {
  final JwClient client;
  GradeApi(this.client);

  Future<List<Grade>> fetch(Term term) async {
    final resp = await client.postData(
      '/cjcx/cjcx_cxDgXscj.html?doType=query',
      {
        'xnm': term.xnm,
        'xqm': term.xqm,
        'zd_fzdm': 'N305005-xs',
        '_search': 'false',
        'nd': DateTime.now().millisecondsSinceEpoch,
        'queryModel.showCount': '300',
        'queryModel.currentPage': '1',
        'queryModel.sortName': '',
        'queryModel.sortOrder': 'asc',
        'time': '0',
      },
      referer: '/cjcx/cjcx_cxDgXscj.html?gnmkdm=N305005&layout=default',
    );
    final data = tryDecode(resp.data);
    final items = data is Map ? (data['items'] as List? ?? []) : [];
    return items
        .map((e) => Grade.fromJson(Map<String, dynamic>.from(e)))
        .where((g) => g.kcmc.isNotEmpty)
        .toList();
  }

  /// 成绩构成（平时/期末/总评分项）：POST /cjcx/cjcx_cxCjxqGjh.html 弹窗页
  /// 参数与 web 端 ckCjxqLink 一致（jxb_id/xnm/xqm/xh_id/kcmc），
  /// 正方 $.showDialog 以 POST 表单加载弹窗内容。
  ///
  /// 成绩发布后分项基本不再变化，因此先读本地缓存秒开；
  /// [force] 为 true 时才强制在线刷新。
  Future<List<GradeComponent>> fetchDetails(
    Grade grade, {
    bool force = false,
  }) async {
    final key =
        'cache_grade_detail_${grade.xnm}_${grade.xqm}_${grade.jxbId}';
    if (!force) {
      final cached = await _readDetailCache(key);
      if (cached != null) {
        AppLog.d('成绩', '分项明细命中缓存：${grade.kcmc}');
        return cached;
      }
    }
    final resp = await client.postData(
      // 实抓确认：必带 gnmkdm=N305005，否则服务端返回 911
      '/cjcx/cjcx_cxCjxqGjh.html?gnmkdm=N305005',
      {
        'jxb_id': grade.jxbId,
        'xnm': grade.xnm,
        'xqm': grade.xqm,
        'xh_id': grade.xhId,
        'kcmc': grade.kcmc,
      },
      referer: '/cjcx/cjcx_cxDgXscj.html?gnmkdm=N305005&layout=default',
    );
    final html = resp.data is String ? resp.data as String : '${resp.data}';

    // 兜底 1：部分版本返回 jqGrid JSON
    final json = tryDecode(html);
    if (json is Map) {
      final items = json['items'] as List? ?? [];
      final comps = <GradeComponent>[];
      for (final e in items) {
        final m = Map<String, dynamic>.from(e);
        final name = _s(m['cjfxmc'] ?? m['cjfxbzmc'] ?? m['xm'] ?? m['mc']);
        if (name.isEmpty) continue;
        comps.add(
          GradeComponent(
            name: name,
            score: _s(m['xdfscj'] ?? m['cj'] ?? m['fs']),
            ratio: _s(m['bl'] ?? m['fz'] ?? m['jdblb']),
          ),
        );
      }
      if (comps.isNotEmpty) {
        await _writeDetailCache(key, comps);
        return comps;
      }
    }

    // 兜底 2：解析弹窗 HTML 表格行
    final comps = _parseDetailHtml(html);
    if (comps.isNotEmpty) await _writeDetailCache(key, comps);
    return comps;
  }

  Future<List<GradeComponent>?> _readDetailCache(String key) async {
    final raw = await LocalCache.read(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return GradeComponent(
              name: '${m['n'] ?? ''}',
              ratio: '${m['r'] ?? ''}',
              score: '${m['s'] ?? ''}',
            );
          })
          .where((c) => c.name.isNotEmpty)
          .toList();
      return list.isEmpty ? null : list;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDetailCache(
    String key,
    List<GradeComponent> comps,
  ) async {
    try {
      await LocalCache.write(
        key,
        jsonEncode([
          for (final c in comps) {'n': c.name, 'r': c.ratio, 's': c.score},
        ]),
      );
    } catch (_) {
      // 缓存失败不影响展示
    }
  }

  /// 解析成绩详情弹窗 HTML。实抓格式为整行文本，如：
  ///   【平时】40%90
  ///   【期末】60%72
  /// 兼容列式（多个 <td>：名称/比例/分数）与整行单列两种结构。
  List<GradeComponent> _parseDetailHtml(String html) {
    final comps = <GradeComponent>[];
    // 整行格式：【分项名】比例%分数
    final wholeRe = RegExp(r'【([^】]+)】\s*(\d+(?:\.\d+)?)%\s*(\d+(?:\.\d+)?)');

    for (final rowM in RegExp(r'<tr[^>]*>([\s\S]*?)</tr>').allMatches(html)) {
      final cells = <String>[];
      for (final cM in RegExp(
        r'<t[dh][^>]*>([\s\S]*?)</t[dh]>',
      ).allMatches(rowM.group(1)!)) {
        final text = cM
            .group(1)!
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll(RegExp(r'&nbsp;?'), ' ')
            .trim();
        if (text.isNotEmpty) cells.add(text);
      }
      if (cells.isEmpty) continue;
      final line = cells.join(' ');

      // 先试整行【】格式
      final wm = wholeRe.firstMatch(line);
      if (wm != null) {
        final name = wm.group(1)!.trim();
        if (name.isEmpty ||
            name.contains('分项') ||
            name.contains('名称') ||
            name.contains('项目')) {
          continue;
        }
        comps.add(
          GradeComponent(
            name: name,
            ratio: '${wm.group(2)}%',
            score: wm.group(3)!,
          ),
        );
        continue;
      }
      // 回退：列式解析（名称在前，含 % 判比例、可转数字判分数），兼容列序差异
      final name0 = cells[0];
      if (name0.contains('分项') ||
          name0.contains('名称') ||
          name0.contains('项目')) {
        continue;
      }
      if (cells.length < 2) continue;
      var score = '';
      var ratio = '';
      for (final c in cells.skip(1)) {
        if (c.contains('%') && ratio.isEmpty) {
          ratio = c;
        } else if (double.tryParse(c.replaceAll('%', '')) != null &&
            score.isEmpty &&
            !c.contains('%')) {
          score = c;
        }
      }
      if (score.isEmpty && ratio.isEmpty) continue;
      // 名称单元格可能带比例（如"平时成绩(30%)"）
      final pct = RegExp(r'[（(](\d+(?:\.\d+)?)%[)）]').firstMatch(name0);
      if (pct != null && ratio.isEmpty) ratio = '${pct.group(1)}%';
      final name = name0
          .replaceAll(RegExp(r'[（(]\d+(?:\.\d+)?%[)）]'), '')
          .replaceAll('【', '')
          .replaceAll('】', '')
          .trim();
      if (name.isEmpty) continue;
      comps.add(GradeComponent(name: name, ratio: ratio, score: score));
    }
    return comps;
  }
}

String _s(dynamic v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  return v.toString();
}

/// 正方空教室查询的周次/节次编码：位掩码，第 n 项 = 2^(n-1)。
/// 传 "9,10" 这类逗号列表会被服务端判为非法并返回"错误提示" HTML。
String _bitmask(List<int> nums) => nums
    .where((n) => n > 0)
    .fold<int>(0, (s, n) => s | (1 << (n - 1)))
    .toString();

/// 考试安排：POST /kwgl/kscx_cxXsksxxIndex.html?doType=query&gnmkdm=N358105
class ExamApi {
  final JwClient client;
  ExamApi(this.client);

  Future<List<Exam>> fetch(Term term) async {
    final resp = await client.postData(
      '/kwgl/kscx_cxXsksxxIndex.html?doType=query&gnmkdm=N358105',
      {
        'xnm': term.xnm,
        'xqm': term.xqm,
        'ksmcdmb_id': '',
        'kch': '',
        'kc': '',
        'ksrq': '',
        'kkbm_id': '',
        '_search': 'false',
        'nd': DateTime.now().millisecondsSinceEpoch,
        'queryModel.showCount': '1000',
        'queryModel.currentPage': '1',
        'queryModel.sortName': ' ',
        'queryModel.sortOrder': 'asc',
        'time': '0',
      },
      referer: '/kwgl/kscx_cxXsksxxIndex.html?gnmkdm=N358105&layout=default',
    );
    final data = tryDecode(resp.data);
    final items = data is Map ? (data['items'] as List? ?? []) : [];
    return items
        .map((e) => Exam.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.kcmc.isNotEmpty)
        .toList();
  }
}

/// 学业情况：xfyqjd_id 为动态值，须先 GET 页面提取
class AcademicApi {
  final JwClient client;
  AcademicApi(this.client);

  /// 返回按课程类别分组的修读情况 + 页面权威修读总览（修读进度准确值）
  Future<({List<AcademicCategory> categories, AcademicOverview overview})>
  fetch(String xhId, Term term) async {
    final pageResp = await client.getHtml(
      '/xsxy/xsxyqk_cxXsxyqkIndex.html',
      query: {'echarts': '1', 'gnmkdm': 'N105515', 'layout': 'default'},
    );
    final html = pageResp.data as String;

    // 页面里每个"学分要求计划" tab 对应一个 30+ 位大写十六进制 id
    final ids = <String>{};
    for (final m in RegExp(r'[0-9A-F]{30,40}').allMatches(html)) {
      ids.add(m.group(0)!);
    }

    final all = <AcademicCourse>[];
    // 收集原始行（含 XDZT/成绩/学年学期），调试级日志用于核查修读状态判定
    final rawRows = <Map<String, dynamic>>[];

    Future<bool> query(String id, {required bool fk}) async {
      // 并发下不能用 all.length 判断本次是否拿到数据（其他 worker 会同时追加），
      // 改为统计本次响应实际新增的课程数。
      var added = 0;
      final body = <String, dynamic>{
        'fromXh_id': '',
        'xfyqjd_id': id,
        'xh_id': xhId,
      };
      if (fk) {
        // 方案外/其他课程查询需要成绩录入学年学期参数
        body
          ..['cjlrxn'] = term.xnm
          ..['cjlrxq'] = term.xqm
          ..['bkcjlrxn'] = term.xnm
          ..['bkcjlrxq'] = term.xqm
          ..['xscjcxkz'] = '0'
          ..['cjcxkzzt'] = '0'
          ..['cjztkz'] = '0'
          ..['cjzt'] = '';
      }
      final path = fk
          ? '/xsxy/xsxyqk_cxJxzxjhxfyqFKcxx.html?gnmkdm=N105515'
          : '/xsxy/xsxyqk_cxJxzxjhxfyqKcxx.html?gnmkdm=N105515';
      try {
        final resp = await client.postData(
          path,
          body,
          referer:
              '/xsxy/xsxyqk_cxXsxyqkIndex.html?gnmkdm=N105515&layout=default',
        );
        final data = tryDecode(resp.data);
        if (data is List) {
          for (final e in data) {
            final m = Map<String, dynamic>.from(e);
            final c = AcademicCourse.fromJson(m);
            if (c.kcmc.isNotEmpty) {
              all.add(c);
              added++;
            }
            if (rawRows.length < 400) rawRows.add(m);
          }
        }
        return added > 0;
      } catch (_) {
        return false; // 单次失败返回 false，由上层重试
      }
    }

    // 3 路有界并发 + 失败串行重试：
    // 高延迟公网下单次往返可达 3s，10+ 个计划串行会拖到几十秒；
    // 但全并发会被服务端偶发丢弃整组计划，因此只开 3 路，空结果再逐个重试。
    final queue = <String>[...ids, 'qtkcxfyq'];
    var cursor = 0;

    Future<void> fetchOne(String id) async {
      var got = false;
      for (var a = 0; a < 3 && !got; a++) {
        got = await query(id, fk: false);
        if (!got) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
      // 计划内查询为空时再尝试“方案外/其他课程”接口；qtkcxfyq 本身无此分支
      if (!got && id != 'qtkcxfyq') {
        for (var a = 0; a < 3 && !got; a++) {
          got = await query(id, fk: true);
          if (!got) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
      }
      if (!got) AppLog.w('学业', '计划 $id 查询无数据');
    }

    Future<void> worker(int lane) async {
      // 错开起步，避免几个请求在同一时刻集中打到教务
      if (lane > 0) {
        await Future<void>.delayed(Duration(milliseconds: 120 * lane));
      }
      while (cursor < queue.length) {
        final id = queue[cursor++];
        await fetchOne(id);
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker(i)]);

    // 去重（不同计划可能返回相同课程）。
    // key 需带上类别/通识子类/学期/状态/学分/成绩：仅用课程名会把
    // 不同类别下的同名课程（如 大学英语）误合并，导致学分漏计。
    final seen = <String>{};
    final unique = <AcademicCourse>[];
    for (final c in all) {
      final key =
          '${c.kcmc}|${c.kclbmc}|${c.kcgsmc}|'
          '${c.xnmc}|${c.xqmmc}|${c.xdz}|${c.xf}|${c.cj}';
      if (seen.add(key)) unique.add(c);
    }

    // 修读状态判定（2026-09 接口实证）：
    // 未修/在读课程的 XNMC/XQMMC 字段为空，无法用当前学期匹配；唯一权威区分是 XDZT：
    //   XDZT=4（且有成绩）→ 已修；XDZT=1（本学期课程）→ 在读；XDZT=3（后续课程）→ 未修
    CourseStatus infer(AcademicCourse c) {
      if (c.cj.trim().isNotEmpty || c.xdz == '4') {
        return CourseStatus.done; // 已修
      }
      if (c.xdz == '1') return CourseStatus.inProgress; // 在读
      return CourseStatus.planned; // 未修（含 XDZT=3）
    }

    // 按课程类别分组（已应用修正后的修读状态）
    final grouped = <String, List<AcademicCourse>>{};
    var sample = 0;
    for (final c in unique) {
      final key = c.kclbmc.isEmpty ? '其他' : c.kclbmc;
      final status = infer(c);
      final fixed = AcademicCourse(
        kcmc: c.kcmc,
        cj: c.cj,
        jd: c.jd,
        xf: c.xf,
        kclbmc: c.kclbmc,
        kcgsmc: c.kcgsmc,
        kcXzmc: c.kcXzmc,
        xnmc: c.xnmc,
        xqmmc: c.xqmmc,
        xdz: c.xdz,
        status: status,
      );
      (grouped[key] ??= []).add(fixed);
      // 采样记录原始字段便于核查未修/在读是否反序
      if (AppLog.debugDetail && sample < 12) {
        AppLog.d(
          '学业',
          '${c.kcmc} CJ=${c.cj.isEmpty ? '-' : c.cj} XDZT=${c.xdz} 判定=${status.name}',
        );
        sample++;
      }
    }
    // 汇总各原始字段组合的分布，便于快速判断判定口径是否正确
    if (AppLog.debugDetail && rawRows.isNotEmpty) {
      final combo = <String, int>{};
      String s(Object? v) => '${v ?? ''}'.trim();
      for (final m in rawRows) {
        final k =
            'XN=${s(m['XNMC'])},XQ=${s(m['XQMMC'])},XDZT=${s(m['XDZT'])},'
            'CJ=${s(m['CJ']).isEmpty ? '无' : '有'}';
        combo[k] = (combo[k] ?? 0) + 1;
      }
      AppLog.d('学业', '计划数=${unique.length} 原始字段分布 ${combo.length} 种：');
      final rows = combo.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in rows.take(30)) {
        AppLog.d('学业', '  ${e.key} x${e.value}');
      }
    }
    final categories =
        grouped.entries
            .map((e) => AcademicCategory(name: e.key, courses: e.value))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    final fallback = _fallbackOverview(categories);
    // 进度口径：统一用"学分完成情况"页的 最低修读学分(分母) 与 已获得学分(分子)
    // （即 已获得/最低修读；用户确认以此为准，如 100.5/156≈64.4%）
    double? minCredit, earnedCr;
    try {
      final cResp = await client.getHtml(
        '/xkcx/xkmdcx_cxXkxfhtkqkIndex.html',
        query: {'gnmkdm': 'N255076', 'layout': 'default'},
      );
      final cHtml = cResp.data is String ? (cResp.data as String) : '';
      final cTxt = cHtml
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final mM = RegExp(r'最低修读要求学分是\s*([\d.]+)').firstMatch(cTxt);
      final mE = RegExp(r'您已获得\s*([\d.]+)\s*学分').firstMatch(cTxt);
      if (mM != null && mE != null) {
        final mc = double.tryParse(mM.group(1)!);
        final ec = double.tryParse(mE.group(1)!);
        if (mc != null && ec != null && mc > 0) {
          minCredit = mc;
          earnedCr = ec;
        }
      }
    } catch (_) {
      // 学分页拉取失败则回退既有口径
    }

    final credits = (minCredit != null && earnedCr != null)
        ? <AcademicCategoryStat>[
            AcademicCategoryStat(
              name: '修读学分',
              requireCredit: minCredit,
              earnedCredit: earnedCr,
              totalCourse: fallback.planCourses,
              passedCourse: fallback.passed,
            ),
          ]
        : fallback.categories;

    final overview = AcademicOverview(
      gpa: fallback.gpa,
      planCourses: fallback.planCourses,
      passed: fallback.passed,
      failed: fallback.failed,
      notStarted: fallback.notStarted,
      inProgress: fallback.inProgress,
      categories: credits,
    );
    return (categories: categories, overview: overview);
  }

  /// 接口课程统计兜底：不依赖页面文本，保证修读进度/分类有值
  AcademicOverview _fallbackOverview(List<AcademicCategory> cats) {
    var jdSum = 0.0, xfSum = 0.0;
    var passed = 0, failed = 0, inProg = 0, planned = 0;
    final stats = <AcademicCategoryStat>[];
    for (final cat in cats) {
      var req = 0.0, earn = 0.0;
      var total = 0, pg = 0;
      for (final c in cat.courses) {
        req += c.xf;
        total++;
        if (c.status == CourseStatus.done && c.cj.isNotEmpty) {
          if (c.passed) {
            earn += c.xf;
            pg++;
            passed++;
          } else {
            failed++;
          }
          // 绩点仍按全部有绩点课程计入（不及格同样是 0 绩点）
          final jd = double.tryParse(c.jd);
          if (jd != null && c.xf > 0) {
            jdSum += jd * c.xf;
            xfSum += c.xf;
          }
        } else if (c.status == CourseStatus.inProgress) {
          inProg++;
        } else {
          planned++;
        }
      }
      if (cat.courses.isNotEmpty) {
        stats.add(
          AcademicCategoryStat(
            name: cat.name,
            requireCredit: req,
            earnedCredit: earn,
            totalCourse: total,
            passedCourse: pg,
          ),
        );
      }
    }
    final planCourses = stats.fold(0, (s, c) => s + c.totalCourse);
    return AcademicOverview(
      gpa: xfSum > 0 ? (jdSum / xfSum) : null,
      planCourses: planCourses,
      passed: passed,
      failed: failed,
      notStarted: planned,
      inProgress: inProg,
      categories: stats,
    );
  }
}

/// 绩点排名：查询条件（学年学期/成绩性质/统计范围）运行时从页面解析
class RankApi {
  final JwClient client;
  RankApi(this.client);

  /// 返回页面可选的全部筛选条件与默认值
  Future<RankPageMeta> fetchPageMeta() async {
    final resp = await client.getHtml(
      '/cjpmtj/cjpmtj_cxPjxfjdpmcxIndex.html',
      query: {'gnmkdm': 'N309106', 'layout': 'default'},
    );
    final html = resp.data as String;

    // 学年学期下拉（value 形如 202512，显示 2025-2026-2）
    final options = <RankOption>[];
    final optRe = RegExp(r'<option\s+value="([^"]+)"[^>]*>([\s\S]*?)</option>');
    for (final m in optRe.allMatches(html)) {
      final v = m.group(1)!.trim();
      final text = m
          .group(2)!
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&nbsp;', ' ')
          .trim();
      if (v.isEmpty) continue;
      if (options.every((o) => o.value != v)) {
        options.add(RankOption(value: v, label: text));
      }
    }
    // 若页面 option 用单标签 (<option value="x">t</option> 也适用上面)；
    // 兜底：过滤掉"全部"占位
    options.removeWhere((o) => o.label == '全部' && o.value.isEmpty);

    // 去除实体字符（&nbsp; 等），统一空格
    String clean(String s) => s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // radio 组：解析 value + 显示文本 + checked
    (List<RankOption>, String) parseRadios(
      String name,
      String fallbackValue,
      String fallbackLabel,
    ) {
      final opts = <RankOption>[];
      final inputRe = RegExp(
        '<input[^>]*name=([\'"])$name'
        r'\1[^>]*>',
      );
      for (final m in inputRe.allMatches(html)) {
        final tag = m.group(0)!;
        final value =
            RegExp(r'''value=(["'])(.*?)\1''').firstMatch(tag)?.group(2) ?? '';
        if (value.isEmpty) continue;
        // 显示文本：input 所在 <label> 的其余内容，或紧跟其后的纯文本
        var label = '';
        final after = html.substring(m.end);
        final closeLabel = after.indexOf('</label>');
        if (closeLabel >= 0 && closeLabel < 200) {
          label = clean(after.substring(0, closeLabel));
        }
        if (label.isEmpty) {
          // 文本可能在 label 前半段（<label>文字<input/></label>）
          final before = html.substring(0, m.start);
          final openLabel = before.lastIndexOf('<label');
          if (openLabel >= 0 && m.start - openLabel < 200) {
            label = clean(before.substring(openLabel));
          }
        }
        if (label.isEmpty) label = clean(value);
        opts.add(RankOption(value: value, label: label));
      }
      var def = fallbackValue;
      for (final t in inputRe.allMatches(html)) {
        if (t.group(0)!.contains('checked')) {
          final v = RegExp(r'''value=(["'])(.*?)\1''')
              .firstMatch(t.group(0)!)
              ?.group(2);
          if (v != null && v.isNotEmpty) def = v;
        }
      }
      if (opts.isEmpty) {
        opts.add(RankOption(value: fallbackValue, label: fallbackLabel));
      }
      return (opts, def);
    }

    final (cjxzmOpts, defCjxzm) = parseRadios('cjxzm', 'zdz', '最大值');
    final (tjfwOpts, defTjfw) = parseRadios('tjfw', 'bj', '班级');

    return RankPageMeta(
      xnqOptions: options,
      cjxzmOptions: cjxzmOpts,
      tjfwOptions: tjfwOpts,
      defCjxzm: defCjxzm,
      defTjfw: defTjfw,
    );
  }

  Future<RankResult> query({
    required String qsXnxq,
    required String zzXnxq,
    required String cjxzm,
    required String tjfw,
  }) async {
    final resp = await client.postData(
      '/cjpmtj/cjpmtj_cxPjxfjdpmcxIndex.html?doType=query',
      {
        'qsXnxq': qsXnxq,
        'zzXnxq': zzXnxq,
        'cjxzm': cjxzm,
        'tjfw': tjfw,
        'queryModel.showCount': '5000',
        'queryModel.currentPage': '1',
      },
      referer:
          '/cjpmtj/cjpmtj_cxPjxfjdpmcxIndex.html?gnmkdm=N309106&layout=default',
    );
    final data = tryDecode(resp.data);
    if (data is! Map) throw Exception('排名数据格式异常');
    final items = (data['items'] as List? ?? [])
        .map((e) => RankItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final total = int.tryParse('${data['totalCount']}') ?? items.length;
    return RankResult(items: items, totalCount: total);
  }
}

// ---- Riverpod providers ----
final timetableApiProvider = Provider<TimetableApi>(
  (ref) => TimetableApi(ref.watch(jwClientProvider)),
);

final gradeApiProvider = Provider<GradeApi>(
  (ref) => GradeApi(ref.watch(jwClientProvider)),
);

final examApiProvider = Provider<ExamApi>(
  (ref) => ExamApi(ref.watch(jwClientProvider)),
);

final academicApiProvider = Provider<AcademicApi>(
  (ref) => AcademicApi(ref.watch(jwClientProvider)),
);

final rankApiProvider = Provider<RankApi>(
  (ref) => RankApi(ref.watch(jwClientProvider)),
);

/// 空教室查询（POST /cdjy/cdjy_cxKxcdlb.html?doType=query&gnmkdm=N2155）
class EmptyRoomApi {
  final JwClient client;
  EmptyRoomApi(this.client);

  /// 查询空闲教室。周次/星期/节次均支持多选（逗号分隔提交）。
  /// [weeks] 周次、[weekdays] 星期(1-7)、[jcds] 节次(1-10)。
  /// [categoryId] 场地类别(默认01多媒体)、[building] 楼号、[xqhId] 校区。
  ///
  /// 【分页】原实现固定 showCount=20 且不翻页，导致无论筛选条件都只有 20 个；
  /// 现按 jqGrid 的 records/total 自动翻页拉全（每页 100，上限 10 页），并按场地
  /// 编号去重，从根本上解决"最多 20 个 / 条件扩大后只返回前 20 个而误判无数据"。
  Future<List<EmptyRoom>> query({
    required List<int> weeks,
    required List<int> weekdays,
    required List<int> jcds,
    String categoryId = '01',
    String building = '',
    String name = '',
    String xqhId = '1',
    int maxPages = 10, // 至多 1000 间，避免过量请求
    Duration budget = const Duration(seconds: 25), // 整次查询的总时间上限
  }) async {
    final t = TermUtils.currentTerm();
    const perPage = 100;
    final pageCap = maxPages.clamp(1, 10);
    final deadline = DateTime.now().add(budget);
    final collected = <String, EmptyRoom>{};
    var page = 1;
    while (page <= pageCap && DateTime.now().isBefore(deadline)) {
      final before = collected.length;
      final resp = await client.postData(
        '/cdjy/cdjy_cxKxcdlb.html?doType=query&gnmkdm=N2155',
        {
          'xqh_id': xqhId,
          'xnm': t.xnm,
          'xqm': t.xqm,
          'cdlb_id': categoryId,
          'cdejlb_id': '',
          'qszws': '',
          'jszws': '',
          'cdmc': name,
          'lh': building,
          'jyfs': '0',
          'cdjylx': '',
          'sfbhkc': '',
          'zcd': _bitmask(weeks),
          'xqj': weekdays.join(','),
          'jcd': _bitmask(jcds),
          '_search': 'false',
          'nd': DateTime.now().millisecondsSinceEpoch.toString(),
          'queryModel.showCount': '$perPage',
          'queryModel.currentPage': '$page',
          'queryModel.sortName': 'cdbh',
          'queryModel.sortOrder': 'asc',
          'time': '0',
        },
        referer: '/cdjy/cdjy_cxKxcdlb.html?gnmkdm=N2155&layout=default',
      );
      final data = tryDecode(resp.data);
      if (data is! Map) break;
      final items = data['items'] as List? ?? [];
      if (items.isEmpty) break;
      for (final e in items) {
        final r = EmptyRoom.fromJson(Map<String, dynamic>.from(e as Map));
        if (r.cdmc.isEmpty || r.cdbh.isEmpty) continue;
        collected[r.cdbh] = r;
      }
      // jqGrid 元信息：达到记录总数 / 页数即停；无进展也停（防死循环）
      // 实抓该接口回的是 totalResult(行数) + totalPage(页数)，不含 records/total
      final records = int.tryParse(
        '${data['records'] ?? data['totalResult'] ?? ''}',
      );
      final total = int.tryParse('${data['total'] ?? data['totalPage'] ?? ''}');
      if (records != null && collected.length >= records) break;
      if (total != null && page >= total) break;
      if (collected.length == before) break;
      page++;
    }
    return collected.values.toList();
  }
}

/// 空闲教室
class EmptyRoom {
  final String cdmc; // 教室名
  final String cdbh; // 场地编号
  final String cdlbmc; // 场地类别
  final String jxlmc; // 教学楼名
  final String zws; // 座位数
  final String xqmc; // 校区
  final String bz; // 备注
  final String sybm; // 使用部门
  final String sfkjy; // 是否可借（是/否）
  const EmptyRoom({
    required this.cdmc,
    required this.cdbh,
    required this.cdlbmc,
    required this.jxlmc,
    required this.zws,
    required this.xqmc,
    required this.bz,
    required this.sybm,
    required this.sfkjy,
  });

  /// 是否判定为真正可用：可借，且无占用部门/备注
  bool get available {
    if (sfkjy == '是') return true;
    if (sfkjy == '否') return false;
    // 未明确可借时，依据是否有使用部门/备注占用判断
    return sybm.trim().isEmpty && bz.trim().isEmpty;
  }

  factory EmptyRoom.fromJson(Map<String, dynamic> j) => EmptyRoom(
    cdmc: '${j['cdmc'] ?? ''}',
    cdbh: '${j['cdbh'] ?? ''}',
    cdlbmc: '${j['cdlbmc'] ?? ''}',
    jxlmc: '${j['jxlmc'] ?? ''}',
    zws: '${j['zws'] ?? ''}',
    xqmc: '${j['xqmc'] ?? ''}',
    bz: '${j['bz'] ?? ''}',
    sybm: '${j['sybm'] ?? j['sybmmc'] ?? j['sydxmc'] ?? ''}',
    sfkjy: '${j['sfkjy'] ?? ''}',
  );

  /// 序列化为 Map（用于收藏持久化）
  Map<String, String> toMap() => {
    'cdmc': cdmc,
    'cdbh': cdbh,
    'cdlbmc': cdlbmc,
    'jxlmc': jxlmc,
    'zws': zws,
    'xqmc': xqmc,
    'bz': bz,
    'sybm': sybm,
    'sfkjy': sfkjy,
  };

  static EmptyRoom fromMap(Map<String, dynamic> m) => EmptyRoom(
    cdmc: '${m['cdmc'] ?? ''}',
    cdbh: '${m['cdbh'] ?? ''}',
    cdlbmc: '${m['cdlbmc'] ?? ''}',
    jxlmc: '${m['jxlmc'] ?? ''}',
    zws: '${m['zws'] ?? ''}',
    xqmc: '${m['xqmc'] ?? ''}',
    bz: '${m['bz'] ?? ''}',
    sybm: '${m['sybm'] ?? ''}',
    sfkjy: '${m['sfkjy'] ?? ''}',
  );
}

final emptyRoomApiProvider = Provider<EmptyRoomApi>(
  (ref) => EmptyRoomApi(ref.watch(jwClientProvider)),
);
