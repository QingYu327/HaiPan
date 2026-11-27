import '../util/term_utils.dart';
import 'models.dart';

/// 情侣课表同步的课程：只包含课名、时间、地点、周次。
class CoupleCourse {
  final String name;
  final int weekday;
  final int startSection;
  final int endSection;
  final String room;
  final Set<int> weeks;

  const CoupleCourse({
    required this.name,
    required this.weekday,
    required this.startSection,
    required this.endSection,
    this.room = '',
    this.weeks = const {},
  });

  bool activeInWeek(int week) => weeks.isEmpty || weeks.contains(week);

  factory CoupleCourse.fromJson(Map<String, dynamic> json) => CoupleCourse(
        name: '${json['n'] ?? json['kcmc'] ?? ''}'.trim(),
        weekday: _int(json['w'] ?? json['weekday']),
        startSection: _int(json['s'] ?? json['startSection']),
        endSection: _int(json['e'] ?? json['endSection']),
        room: '${json['r'] ?? json['room'] ?? ''}'.trim(),
        weeks: {
          for (final x in (json['k'] as List? ?? const []))
            if (_int(x) > 0) _int(x),
        },
      );

  Map<String, dynamic> toJson() => {
        'n': name,
        'w': weekday,
        's': startSection,
        'e': endSection,
        'r': room,
        'k': weeks.toList()..sort(),
      };

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
}

class CoupleStatus {
  final bool paired;
  final int myUpdatedAt;
  final int partnerUpdatedAt;

  const CoupleStatus({
    required this.paired,
    this.myUpdatedAt = 0,
    this.partnerUpdatedAt = 0,
  });

  bool get partnerStale {
    if (partnerUpdatedAt <= 0) return true;
    final at = DateTime.fromMillisecondsSinceEpoch(partnerUpdatedAt);
    return DateTime.now().difference(at) > const Duration(days: 7);
  }

  bool get mineStale {
    if (myUpdatedAt <= 0) return true;
    final at = DateTime.fromMillisecondsSinceEpoch(myUpdatedAt);
    return DateTime.now().difference(at) > const Duration(days: 7);
  }
}

class CouplePartner {
  final List<CoupleCourse> courses;
  final int updatedAt;

  const CouplePartner({this.courses = const [], this.updatedAt = 0});
}

class CoupleException implements Exception {
  final String code;
  final String message;
  const CoupleException(this.code, this.message);

  @override
  String toString() => message;
}

/// 课表 → 同步快照（过滤实践课与无效节次）
List<CoupleCourse> coupleCoursesOf(List<CourseEntry> courses) {
  final out = <CoupleCourse>[];
  for (final c in courses) {
    final name = c.kcmc.trim();
    if (name.isEmpty || c.weekday < 1 || c.startSection < 1) continue;
    if (c.endSection < c.startSection) continue;
    out.add(CoupleCourse(
      name: name,
      weekday: c.weekday,
      startSection: c.startSection,
      endSection: c.endSection,
      room: c.room.trim(),
      weeks: c.weeks,
    ));
  }
  return out;
}

/// 12 节制的空闲节次（仅用于展示共同空闲）
List<(int, int)> freeSections(
  List<CoupleCourse> a,
  List<CoupleCourse> b,
  int weekday,
  int week, {
  int maxSection = 12,
}) {
  final busy = List<bool>.filled(maxSection + 1, false);
  for (final c in [...a, ...b]) {
    if (c.weekday != weekday || !c.activeInWeek(week)) continue;
    for (var i = c.startSection; i <= c.endSection; i++) {
      if (i >= 1 && i <= maxSection) busy[i] = true;
    }
  }
  final out = <(int, int)>[];
  int? start;
  for (var i = 1; i <= maxSection; i++) {
    if (!busy[i] && start == null) start = i;
    if (busy[i] && start != null) {
      out.add((start, i - 1));
      start = null;
    }
  }
  if (start != null) out.add((start, maxSection));
  return out;
}

String coupleWeekLabel(int week) => '第 $week 周';

/// 当天星期（1-7），用于页面默认选中
int todayWeekday() => DateTime.now().weekday;

/// 当前学期估算周次，失败时回退第 1 周
int coupleCurrentWeek(Term term) {
  final w = TermUtils.estimatedCurrentWeek(term);
  return (w == null || w < 1) ? 1 : w;
}
