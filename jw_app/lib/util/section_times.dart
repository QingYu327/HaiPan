/// 节次作息时间。
///
/// 默认值按教务处课表原文逐节设置；用户可在「设置 → 课程时间」中修改。
/// 修改后同时作用于课表时间栏、上课提醒与桌面小组件。
class SectionTime {
  final int section;
  final int startMinutes; // 距 00:00 的分钟数；-1 表示未设置
  final int endMinutes;

  const SectionTime(this.section, this.startMinutes, this.endMinutes);

  bool get isSet => startMinutes >= 0 && endMinutes > startMinutes;

  String get startLabel => formatMinutes(startMinutes);
  String get endLabel => formatMinutes(endMinutes);

  SectionTime copyWith({int? startMinutes, int? endMinutes}) => SectionTime(
        section,
        startMinutes ?? this.startMinutes,
        endMinutes ?? this.endMinutes,
      );
}

String formatMinutes(int minutes) {
  if (minutes < 0) return '--:--';
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// 11、12 节暂无官方作息，默认留空，用户可自行补充。
const List<SectionTime> kDefaultSectionTimes = [
  SectionTime(1, 8 * 60 + 10, 8 * 60 + 55),
  SectionTime(2, 9 * 60 + 0, 9 * 60 + 45),
  SectionTime(3, 10 * 60 + 15, 11 * 60 + 0),
  SectionTime(4, 11 * 60 + 5, 11 * 60 + 50),
  SectionTime(5, 14 * 60 + 30, 15 * 60 + 15),
  SectionTime(6, 15 * 60 + 20, 16 * 60 + 5),
  SectionTime(7, 16 * 60 + 30, 17 * 60 + 15),
  SectionTime(8, 17 * 60 + 20, 18 * 60 + 5),
  SectionTime(9, 19 * 60 + 30, 20 * 60 + 15),
  SectionTime(10, 20 * 60 + 25, 21 * 60 + 10),
  SectionTime(11, -1, -1),
  SectionTime(12, -1, -1),
];

/// 全局作息表（与设置加载/保存同步）。
class SectionTimes {
  SectionTimes._();

  static List<SectionTime> _current = kDefaultSectionTimes;

  static List<SectionTime> get current => _current;

  static void apply(List<SectionTime> times) {
    _current = List.unmodifiable(times);
  }

  static void reset() => _current = kDefaultSectionTimes;

  static SectionTime? of(int section) {
    for (final t in _current) {
      if (t.section == section) return t;
    }
    return null;
  }

  static int? startMinutesOf(int section) {
    final t = of(section);
    return (t != null && t.isSet) ? t.startMinutes : null;
  }

  static int? endMinutesOf(int section) {
    final t = of(section);
    return (t != null && t.isSet) ? t.endMinutes : null;
  }

  /// 紧凑存储：`1=08:10-08:55;2=...;11=;`
  static String encode(List<SectionTime> times) {
    final sorted = [...times]..sort((a, b) => a.section.compareTo(b.section));
    return sorted
        .map((t) => t.isSet
            ? '${t.section}=${t.startLabel}-${t.endLabel}'
            : '${t.section}=')
        .join(';');
  }

  static List<SectionTime> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return kDefaultSectionTimes;
    final map = <int, SectionTime>{
      for (final t in kDefaultSectionTimes) t.section: t,
    };
    for (final token in raw.split(';')) {
      final parts = token.split('=');
      if (parts.length != 2) continue;
      final section = int.tryParse(parts[0].trim());
      if (section == null || section < 1 || section > 20) continue;
      final value = parts[1].trim();
      if (value.isEmpty) {
        map[section] = SectionTime(section, -1, -1);
        continue;
      }
      final range = value.split('-');
      if (range.length != 2) continue;
      final start = _parseHm(range[0]);
      final end = _parseHm(range[1]);
      if (start == null || end == null || end <= start) continue;
      map[section] = SectionTime(section, start, end);
    }
    final list = map.values.toList()..sort((a, b) => a.section.compareTo(b.section));
    return list;
  }

  static int? _parseHm(String v) {
    final p = v.trim().split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return h * 60 + m;
  }
}
