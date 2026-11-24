import 'dart:convert';

import '../util/term_utils.dart';

/// ---------------- 学籍信息（课表接口 xsxx + 成绩接口补充）----------------
class StudentInfo {
  final String xh; // 学号
  final String xm; // 姓名
  final String bjmc; // 班级
  final String zymc; // 专业
  final String jgmc; // 学院
  final String njmc; // 年级
  final String xb; // 性别（1 男 / 2 女）
  final String xnmc; // 当前学年，如 2025-2026

  const StudentInfo({
    this.xh = '',
    this.xm = '',
    this.bjmc = '',
    this.zymc = '',
    this.jgmc = '',
    this.njmc = '',
    this.xb = '',
    this.xnmc = '',
  });

  String get xbLabel => xb == '1' ? '男' : (xb == '2' ? '女' : '');

  StudentInfo merge(StudentInfo other) => StudentInfo(
        xh: other.xh.isNotEmpty ? other.xh : xh,
        xm: other.xm.isNotEmpty ? other.xm : xm,
        bjmc: other.bjmc.isNotEmpty ? other.bjmc : bjmc,
        zymc: other.zymc.isNotEmpty ? other.zymc : zymc,
        jgmc: other.jgmc.isNotEmpty ? other.jgmc : jgmc,
        njmc: other.njmc.isNotEmpty ? other.njmc : njmc,
        xb: other.xb.isNotEmpty ? other.xb : xb,
        xnmc: other.xnmc.isNotEmpty ? other.xnmc : xnmc,
      );

  factory StudentInfo.fromJson(Map<String, dynamic> json) => StudentInfo(
        xh: _s(json['XH'] ?? json['xh']),
        xm: _s(json['XM'] ?? json['xm']),
        bjmc: _s(json['BJMC'] ?? json['bjmc']),
        zymc: _s(json['ZYMC'] ?? json['zymc']),
        // 学院字段名在不同接口各异，尽量兼容
        jgmc: _s(json['JGMC'] ??
            json['jgmc'] ??
            json['JGSMC'] ??
            json['JSMC'] ??
            json['YXM'] ??
            json['YXMC'] ??
            json['JXBMCMC']),
        njmc: _s(json['NJMC'] ?? json['njmc'] ?? json['NJDM_ID'] ?? json['njdm_id']),
        xb: _s(json['XBM'] ?? json['xbm'] ?? json['XB'] ?? json['xb']),
        xnmc: _s(json['XNMC'] ?? json['xnmc']),
      );

  Map<String, dynamic> toJson() => {
        'xh': xh,
        'xm': xm,
        'bjmc': bjmc,
        'zymc': zymc,
        'jgmc': jgmc,
        'njmc': njmc,
        'xb': xb,
        'xnmc': xnmc,
      };
}

/// ---------------- 课表 ----------------
class CourseEntry {
  final String kcmc; // 课程名
  final String teacher; // 教师
  final String room; // 教室
  final int weekday; // 星期 1-7
  final int startSection; // 开始节次
  final int endSection; // 结束节次
  final String zcd; // 周次原文，如 "1-16周"
  final Set<int> weeks;

  const CourseEntry({
    required this.kcmc,
    this.teacher = '',
    this.room = '',
    this.weekday = 0,
    this.startSection = 0,
    this.endSection = 0,
    this.zcd = '',
    this.weeks = const {},
  });

  bool get isScheduled => weekday > 0 && startSection > 0;

  factory CourseEntry.fromKb(Map<String, dynamic> json) {
    final jcs = _s(json['jcs']);
    final (start, end) = TermUtils.parseSections(jcs.isEmpty ? '1' : jcs);
    return CourseEntry(
      kcmc: _s(json['kcmc']),
      teacher: _s(json['xm']),
      room: _s(json['cdmc']),
      weekday: int.tryParse(_s(json['xqj'])) ?? 0,
      startSection: start,
      endSection: end,
      zcd: _s(json['zcd']),
      weeks: TermUtils.parseWeeks(_s(json['zcd'])),
    );
  }

  /// 实践课（无固定节次）行。
  /// 正方 sjkList 字段与 kbList 不同：教师是 jsxm、周次是 qsjsz、地点是 jxdd，
  /// 原先按 xm/zcd/cdmc 取值导致实践课卡片只剩课程名。
  factory CourseEntry.fromSjk(Map<String, dynamic> json) {
    final zcd = _s(json['qsjsz'] ?? json['zcd'] ?? json['sksj']);
    return CourseEntry(
      kcmc: _s(json['kcmc']),
      teacher: _s(json['jsxm'] ?? json['xm']),
      room: _s(json['jxdd'] ?? json['cdmc']),
      zcd: zcd,
      weeks: TermUtils.parseWeeks(zcd),
    );
  }

  Map<String, dynamic> toJson() => {
        'kcmc': kcmc,
        'teacher': teacher,
        'room': room,
        'weekday': weekday,
        'startSection': startSection,
        'endSection': endSection,
        'zcd': zcd,
        'weeks': weeks.toList(),
      };

  factory CourseEntry.fromJson(Map<String, dynamic> json) => CourseEntry(
        kcmc: _s(json['kcmc']),
        teacher: _s(json['teacher']),
        room: _s(json['room']),
        weekday: (json['weekday'] as num?)?.toInt() ?? 0,
        startSection: (json['startSection'] as num?)?.toInt() ?? 0,
        endSection: (json['endSection'] as num?)?.toInt() ?? 0,
        zcd: _s(json['zcd']),
        weeks: {...((json['weeks'] as List?)?.cast<int>() ?? const <int>[])},
      );
}

class Timetable {
  final List<CourseEntry> courses;
  final List<CourseEntry> sjk; // 实践课（无固定节次）
  final StudentInfo student;
  final int maxSection; // 最大节次（决定网格行数）

  const Timetable({
    required this.courses,
    required this.sjk,
    required this.student,
    this.maxSection = 12,
  });

  factory Timetable.fromJson(Map<String, dynamic> json) {
    final courses = (json['courses'] as List)
        .map((e) => CourseEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final sjk = (json['sjk'] as List? ?? [])
        .map((e) => CourseEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    var max = 12;
    for (final c in courses) {
      if (c.endSection > max) max = c.endSection;
    }
    return Timetable(
      courses: courses,
      sjk: sjk,
      student: StudentInfo.fromJson(json['student'] as Map<String, dynamic>),
      maxSection: max,
    );
  }

  Map<String, dynamic> toJson() => {
        'courses': courses.map((e) => e.toJson()).toList(),
        'sjk': sjk.map((e) => e.toJson()).toList(),
        'student': student.toJson(),
      };
}

/// ---------------- 成绩 ----------------
class Grade {
  final String kcmc; // 课程名
  final String cj; // 成绩（可能是数字或"良好"等级）
  final String xf; // 学分
  final String jd; // 绩点
  final String xnmc; // 学年 如 2025-2026
  final String xqmmc; // 学期 如 第一学期
  final String jxbId; // 教学班 id（查成绩构成用）
  final String xhId; // 学生 id（加密串，查成绩构成用）
  final String xnm; // 学年码 2025
  final String xqm; // 学期码 3/12
  final String kcxzmc; // 课程性质（必修/选修）
  final String kclbmc; // 课程类别

  const Grade({
    required this.kcmc,
    this.cj = '',
    this.xf = '',
    this.jd = '',
    this.xnmc = '',
    this.xqmmc = '',
    this.jxbId = '',
    this.xhId = '',
    this.xnm = '',
    this.xqm = '',
    this.kcxzmc = '',
    this.kclbmc = '',
  });

  double? get jdNum => double.tryParse(jd);
  double? get xfNum => double.tryParse(xf);
  double? get cjNum => double.tryParse(cj);

  /// 是否可查成绩构成（需要教学班 id）
  bool get canQueryDetail => jxbId.isNotEmpty && xnm.isNotEmpty;

  /// 是否通过：数值成绩 ≥60，或"合格/优秀"等等级；缺考/不及格等一律不算
  bool get isPassed {
    final t = cj.trim();
    if (t.isEmpty) return false;
    for (final w in const ['不合格', '不及格', '未通过', '缺考', '旷考', '作弊', '缓考']) {
      if (t.contains(w)) return false;
    }
    final n = double.tryParse(t);
    return n == null || n >= 60;
  }

  /// 学期可读描述：服务器可能只回 "1"/"2"，这里统一成"第1/第2学期"
  String get termLabel {
    if (xqmmc.isNotEmpty) {
      final n = int.tryParse(xqmmc);
      if (n != null) return '第$n学期';
      return xqmmc;
    }
    final n = int.tryParse(xqm);
    if (n == 3) return '第一学期';
    if (n == 12) return '第二学期';
    return '';
  }

  factory Grade.fromJson(Map<String, dynamic> json) => Grade(
        kcmc: _s(json['kcmc']),
        cj: _s(json['cj']),
        xf: _s(json['xf']),
        jd: _s(json['jd']),
        xnmc: _s(json['xnmc']),
        xqmmc: _s(json['xqmmc']),
        jxbId: _s(json['jxb_id']),
        xhId: _s(json['xh_id']),
        xnm: _s(json['xnm']),
        xqm: _s(json['xqm']),
        kcxzmc: _s(json['kcxzmc']),
        kclbmc: _s(json['kclbmc']),
      );

  Map<String, dynamic> toJson() => {
        'kcmc': kcmc,
        'cj': cj,
        'xf': xf,
        'jd': jd,
        'xnmc': xnmc,
        'xqmmc': xqmmc,
        'jxb_id': jxbId,
        'xh_id': xhId,
        'xnm': xnm,
        'xqm': xqm,
        'kcxzmc': kcxzmc,
        'kclbmc': kclbmc,
      };
}

/// 成绩构成项（如 平时 30% → 84.05）
class GradeComponent {
  final String name; // 分项名（平时/期末/总评…）
  final String ratio; // 比例（30%），可为空
  final String score; // 分数

  const GradeComponent({required this.name, this.ratio = '', this.score = ''});
}

class GradeSummary {
  final double gpa; // 学分绩点（Σ绩点×学分 / Σ学分）
  final double weightedAvg; // 加权平均分
  final double totalCredit; // 已获得学分（只统计通过课程）
  final int courseCount;

  const GradeSummary({
    required this.gpa,
    required this.weightedAvg,
    required this.totalCredit,
    required this.courseCount,
  });

  factory GradeSummary.of(List<Grade> grades) {
    var jdSum = 0.0;
    var cjSum = 0.0;
    var xfSum = 0.0;
    var earned = 0.0;
    var count = 0;
    for (final g in grades) {
      final jd = g.jdNum;
      final xf = g.xfNum ?? 0;
      if (jd != null && xf > 0) {
        jdSum += jd * xf;
        xfSum += xf;
        count++;
      }
      final cj = g.cjNum;
      if (cj != null && xf > 0) cjSum += cj * xf;
      // "获得学分"只统计通过的课程，避免不及格课程被计入
      if (g.isPassed && xf > 0) earned += xf;
    }
    return GradeSummary(
      gpa: xfSum > 0 ? jdSum / xfSum : 0,
      weightedAvg: xfSum > 0 ? cjSum / xfSum : 0,
      totalCredit: earned,
      courseCount: count,
    );
  }
}

/// 解析教务时间字符串（如 `2026-12-30(10:10-12:10)`、`2026-12-30 10:10`），
/// 失败返回 null。不能用 DateTime.tryParse：带括号/波浪线/时段时会直接失败。
DateTime? parseJwDateTime(String raw) {
  final d = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(raw);
  if (d == null) return null;
  final t = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(raw);
  return DateTime(
    int.parse(d.group(1)!),
    int.parse(d.group(2)!),
    int.parse(d.group(3)!),
    t == null ? 8 : int.parse(t.group(1)!),
    t == null ? 0 : int.parse(t.group(2)!),
  );
}

/// ---------------- 考试安排 ----------------
class Exam {
  final String kcmc; // 课程名
  final String kssj; // 考试时间
  final String cdmc; // 地点
  final String cdxqmc; // 校区
  final String ksmc; // 考试名称
  final String ksfs; // 考试方式
  final String jxdd; // 就座地点

  const Exam({
    required this.kcmc,
    this.kssj = '',
    this.cdmc = '',
    this.cdxqmc = '',
    this.ksmc = '',
    this.ksfs = '',
    this.jxdd = '',
  });

  /// 考试开始时间（带场次），解析失败返回 null
  DateTime? get startAt => parseJwDateTime(kssj);

  /// 距考试天数（按时间字符串里的日期估算），失败返回 null
  int? get daysLeft {
    final date = startAt;
    if (date == null) return null;
    final today = DateTime.now();
    return DateTime(date.year, date.month, date.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  factory Exam.fromJson(Map<String, dynamic> json) => Exam(
        kcmc: _s(json['kcmc']),
        kssj: _s(json['kssj']),
        cdmc: _s(json['cdmc']),
        cdxqmc: _s(json['cdxqmc']),
        ksmc: _s(json['ksmc']),
        ksfs: _s(json['ksfs']),
        jxdd: _s(json['jxdd']),
      );

  Map<String, dynamic> toJson() => {
        'kcmc': kcmc,
        'kssj': kssj,
        'cdmc': cdmc,
        'cdxqmc': cdxqmc,
        'ksmc': ksmc,
        'ksfs': ksfs,
        'jxdd': jxdd,
      };
}

/// ---------------- 学业情况 ----------------
enum CourseStatus { planned, inProgress, done }

class AcademicCourse {
  final String kcmc;
  final String cj; // 成绩
  final String jd; // 绩点
  final double xf; // 学分
  final String kclbmc; // 课程类别（分组用）
  final String kcgsmc; // 通识拓展子分类：人文艺术类 / 科技文明与海洋科学类 …
  final String kcXzmc; // 课程性质：必修/任选
  final String xnmc; // 学年
  final String xqmmc; // 学期
  final String xdz; // 修读状态原始值（1在读 / 3未修 / 4已修，本系统实证）
  final CourseStatus status;

  const AcademicCourse({
    required this.kcmc,
    this.cj = '',
    this.jd = '',
    this.xf = 0,
    this.kclbmc = '',
    this.kcgsmc = '',
    this.kcXzmc = '',
    this.xnmc = '',
    this.xqmmc = '',
    this.xdz = '',
    this.status = CourseStatus.planned,
  });

  factory AcademicCourse.fromJson(Map<String, dynamic> json) {
    final xdz = _s(json['XDZT']);
    final hasCj = _s(json['CJ']).trim().isNotEmpty;
    // 真实接口实证（2026 抓取）：未修/在读课程 XNMC/XQMMC 为空，只能用 XDZT 区分：
    // XDZT=4 + 有成绩 → 已修；XDZT=1（本学期）→ 在读；XDZT=3（后续）→ 未修
    final CourseStatus status;
    if (hasCj || xdz == '4') {
      status = CourseStatus.done; // 已修
    } else if (xdz == '1') {
      status = CourseStatus.inProgress; // 在读
    } else {
      status = CourseStatus.planned; // 未修
    }
    return AcademicCourse(
      kcmc: _s(json['KCMC']),
      cj: _s(json['CJ']),
      jd: _s(json['JD']),
      xf: double.tryParse(_s(json['XF'])) ?? 0,
      kclbmc: _s(json['KCLBMC']),
      kcgsmc: _s(json['KCGSMC']),
      kcXzmc: _s(json['KCXZMC']),
      xnmc: _s(json['XNMC']),
      xqmmc: _s(json['XQMMC']),
      xdz: xdz,
      status: status,
    );
  }

  /// 是否通过：已修 + 有效成绩（≥60 或合格/优秀等等级）
  bool get passed {
    if (status != CourseStatus.done || cj.trim().isEmpty) return false;
    final t = cj.trim();
    for (final w in const ['不合格', '不及格', '未通过', '缺考', '旷考', '作弊', '缓考']) {
      if (t.contains(w)) return false;
    }
    final n = double.tryParse(t);
    return n == null || n >= 60;
  }

  /// 已修但未通过（不及格/缺考等）
  bool get failed =>
      status == CourseStatus.done && cj.trim().isNotEmpty && !passed;
}

class AcademicCategory {
  final String name; // 课程类别名
  final List<AcademicCourse> courses;

  const AcademicCategory({required this.name, required this.courses});

  double get earnedCredit =>
      courses.where((c) => c.passed).fold(0, (s, c) => s + c.xf);

  double get totalCredit => courses.fold(0, (s, c) => s + c.xf);
}

/// 单类课程修读统计（学院口径，来自页面：要求/获得/共/通过）
class AcademicCategoryStat {
  final String name; // 分类名，如 思想政治理论课—必修
  final double requireCredit;
  final double earnedCredit;
  final int totalCourse;
  final int passedCourse;

  const AcademicCategoryStat({
    required this.name,
    required this.requireCredit,
    required this.earnedCredit,
    required this.totalCourse,
    required this.passedCourse,
  });
}

/// 修读总体情况（页面顶部权威数据）
class AcademicOverview {
  final double? gpa; // 平均学分绩点
  final int planCourses; // 计划总课程
  final int passed; // 通过
  final int failed; // 未通过
  final int notStarted; // 未修
  final int inProgress; // 在读
  final List<AcademicCategoryStat> categories; // 各分类统计

  const AcademicOverview({
    this.gpa,
    this.planCourses = 0,
    this.passed = 0,
    this.failed = 0,
    this.notStarted = 0,
    this.inProgress = 0,
    this.categories = const [],
  });

  double get requireCredit =>
      categories.fold(0, (s, c) => s + c.requireCredit);

  double get earnedCredit =>
      categories.fold(0, (s, c) => s + c.earnedCredit);

  double get progress => requireCredit > 0
      ? (earnedCredit / requireCredit).clamp(0.0, 1.0)
      : 0;
}

/// ---------------- 绩点排名 ----------------
/// 排名筛选下拉选项（成绩性质 / 统计范围）
class RankOption {
  final String value; // 提交值，如 zdz / bj
  final String label; // 显示名，如 总评成绩 / 班级

  const RankOption({required this.value, required this.label});
}

/// 排名页元信息：起止学年学期选项 + 统计范围/成绩性质筛选条件
class RankPageMeta {
  final List<RankOption> xnqOptions; // 学年学期（value 形如 202512 / 显示 2025-2026-2）
  final List<RankOption> cjxzmOptions; // 成绩性质：正考/最大值/首次通过
  final List<RankOption> tjfwOptions; // 统计范围：年级专业/班级
  final String defCjxzm;
  final String defTjfw;

  const RankPageMeta({
    required this.xnqOptions,
    required this.cjxzmOptions,
    required this.tjfwOptions,
    required this.defCjxzm,
    required this.defTjfw,
  });
}

class RankItem {
  final String xh;
  final String xm;
  final String pjxfjd; // 平均学分绩点
  final String pm; // 名次
  final String zymc;
  final String bj;

  const RankItem({
    this.xh = '',
    this.xm = '',
    this.pjxfjd = '',
    this.pm = '',
    this.zymc = '',
    this.bj = '',
  });

  factory RankItem.fromJson(Map<String, dynamic> json) => RankItem(
        xh: _s(json['xh']),
        xm: _s(json['xm']),
        pjxfjd: _s(json['pjxfjd']),
        pm: _s(json['pm']),
        zymc: _s(json['zymc']),
        bj: _s(json['bj']),
      );
}

class RankResult {
  final List<RankItem> items;
  final int totalCount;

  const RankResult({required this.items, required this.totalCount});
}

String _s(dynamic v) {
  if (v == null) return '';
  if (v is String) return v.trim();
  return v.toString();
}

/// 通用：jqGrid / 普通接口响应统一转 Map/List
dynamic tryDecode(dynamic data) {
  if (data is Map || data is List) return data;
  if (data is String) {
    final t = data.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('{') || t.startsWith('[')) {
      try {
        return jsonDecode(t);
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}
