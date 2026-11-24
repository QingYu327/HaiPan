/// 学期 / 周次 / 节次 解析工具
/// 学期码约定（来自接口移交包实测）：xqm=3 第一学期(秋)，xqm=12 第二学期(春)
library;

class Term {
  final String xnm; // 学年，如 2025
  final String xqm; // 学期码：3 / 12

  const Term(this.xnm, this.xqm);

  /// 显示名：2025-2026学年 第一学期
  String get label {
    final y = int.parse(xnm);
    final sem = xqm == '3' ? '第一学期' : '第二学期';
    return '$y-${y + 1}学年 $sem';
  }

  String get shortLabel {
    final y = int.parse(xnm);
    final sem = xqm == '3' ? '上' : '下';
    return '$y-$sem';
  }

  @override
  bool operator ==(Object other) => other is Term && other.xnm == xnm && other.xqm == xqm;

  @override
  int get hashCode => Object.hash(xnm, xqm);

  Map<String, dynamic> toJson() => {'xnm': xnm, 'xqm': xqm};

  factory Term.fromJson(Map<String, dynamic> json) => Term(json['xnm'] as String, json['xqm'] as String);
}

class TermUtils {
  TermUtils._();

  /// 按当前日期推断默认学期：
  /// 8月~次年1月 → 秋季学期(3)；2月~7月 → 春季学期(12)
  static Term currentTerm() {
    final now = DateTime.now();
    if (now.month >= 8) {
      return Term(now.year.toString(), '3');
    } else if (now.month <= 1) {
      return Term((now.year - 1).toString(), '3');
    }
    return Term((now.year - 1).toString(), '12');
  }

  /// 可选学年列表（降序），入学年份起
  static List<String> availableYears({int earliest = 2020}) {
    final now = DateTime.now();
    final last = now.month >= 8 ? now.year : now.year - 1;
    return [for (var y = last; y >= earliest; y--) y.toString()];
  }

  /// 可选学期列表（降序，不晚于当前学期）
  static List<Term> availableTerms({int earliest = 2020}) {
    final cur = currentTerm();
    final terms = <Term>[];
    for (final y in availableYears(earliest: earliest)) {
      final yi = int.parse(y);
      final has12 = !(yi == int.parse(cur.xnm) && cur.xqm == '3');
      if (has12) terms.add(Term(y, '12'));
      terms.add(Term(y, '3'));
    }
    return terms;
  }

  /// 用户自定义的当前学期开学日（设置里可改，用于校准周数）
  static DateTime? semesterStartOverride;

  /// 某学期第 [week] 周的周一日期（用于课表星期栏显示日期对照），
  /// 非当前学期或开学日未知时返回 null
  static DateTime? weekStartDate(Term term, int week) {
    if (term != currentTerm()) return null;
    final y = int.parse(term.xnm);
    final start = semesterStartOverride ??
        (term.xqm == '3' ? DateTime(y, 9, 1) : DateTime(y + 1, 3, 1));
    return start.add(Duration(days: (week - 1) * 7));
  }

  /// 按学期开学日估算当前周次（仅当前学期有效，超出范围返回 null）
  static int? estimatedCurrentWeek(Term term) {
    if (term != currentTerm()) return null;
    final y = int.parse(term.xnm);
    // 秋季 9 月 1 日 / 春季 3 月 1 日开学（近似）；用户可自定义
    final start = semesterStartOverride ??
        (term.xqm == '3' ? DateTime(y, 9, 1) : DateTime(y + 1, 3, 1));
    final w = DateTime.now().difference(start).inDays ~/ 7 + 1;
    return (w >= 1 && w <= 25) ? w : null;
  }

  /// 解析正方 zcd 周次字符串，如 "1-16周"、"1,3,5周"、"1-8周(单)"、"1-15周(双)"
  /// 单/双仅作用于所在的逗号分段，如 "10-12周(双),13周" → 10,12,13
  static Set<int> parseWeeks(String raw) {
    final weeks = <int>{};
    if (raw.isEmpty) return weeks;
    for (final part in raw.split(',')) {
      var s = part.replaceAll('周', '').trim();
      if (s.isEmpty) continue;
      final oddOnly = s.contains('单');
      final evenOnly = s.contains('双');
      if (oddOnly) s = s.replaceAll(RegExp(r'\(单\)|（单）'), '');
      if (evenOnly) s = s.replaceAll(RegExp(r'\(双\)|（双）'), '');
      final seg = <int>{};
      final m = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(s);
      if (m != null) {
        final a = int.parse(m.group(1)!);
        final b = int.parse(m.group(2)!);
        for (var i = a; i <= b; i++) {
          seg.add(i);
        }
      } else {
        final m2 = RegExp(r'(\d+)').firstMatch(s);
        if (m2 != null) seg.add(int.parse(m2.group(1)!));
      }
      if (oddOnly) seg.removeWhere((w) => w % 2 == 0);
      if (evenOnly) seg.removeWhere((w) => w % 2 == 1);
      weeks.addAll(seg);
    }
    return weeks;
  }

  /// 解析节次字符串，如 "3-4节"、"第5-6节"、"2"，返回 (开始节, 结束节)
  static (int, int) parseSections(String raw) {
    final m = RegExp(r'(\d+)\s*-\s*(\d+)').firstMatch(raw);
    if (m != null) {
      return (int.parse(m.group(1)!), int.parse(m.group(2)!));
    }
    final m2 = RegExp(r'(\d+)').firstMatch(raw);
    if (m2 != null) {
      final n = int.parse(m2.group(1)!);
      return (n, n);
    }
    return (1, 2);
  }
}
