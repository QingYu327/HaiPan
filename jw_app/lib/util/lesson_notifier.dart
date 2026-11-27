import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'app_log.dart';
import 'local_cache.dart';
import 'section_times.dart';
import 'term_utils.dart';

/// 本地系统通知：上课前 N 分钟 + 考试提醒（离线可用）。
/// 通过原生 Kotlin 通知通道（AlarmManager + Notification）实现，
/// 不引入第三方插件，避免破坏本机构建约束（compileSdk/NDK 固定）。
class LessonNotifier {
  LessonNotifier._();

  static const MethodChannel _ch = MethodChannel('cn.gdou.xiuhong/notify');

  /// 上课提醒覆盖未来多少天（覆盖至少四周，App 不常打开也不会漏提醒）
  static const int _scheduleDays = 28;
  static const int _maxLessons = 500;

  static String? _lastLessonsKey;
  static String? _lastExamsKey;
  static Timetable? _lastTimetable;
  static List<Exam>? _lastExams;

  /// 是否有有效登录态（退出登录后置 false，避免游客/旧账号继续排提醒）
  static const String _kSessionActive = 'notify.session_active';
  static bool _sessionActive = false;

  // 提醒配置（由 SettingsController 同步；默认：上课/考试均开，提前 10 分钟）
  static bool lessonEnabled = true;
  static bool examEnabled = true;
  static int remindMinutes = 10;
  static int examRemindMinutes = 30;

  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      // 若启动流程已先置为 true（会话恢复完成），不要用旧的持久化值覆盖
      if (!_sessionActive) {
        _sessionActive = p.getBool(_kSessionActive) ?? false;
      }
    } catch (_) {
      // 读取失败按未登录处理，登录成功后会重新置位
    }
    if (!kIsWeb && Platform.isAndroid) {
      // 请求通知权限；渠道与闹钟由原生侧创建/恢复
      try {
        await _ch.invokeMethod('requestPerm');
      } catch (_) {
        // 权限请求失败不阻塞
      }
    }
  }

  /// 登录态变化：退出登录时取消并清空全部提醒，防止旧账号提醒继续弹出
  static Future<void> setSessionActive(bool active) async {
    _sessionActive = active;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kSessionActive, active);
    } catch (_) {
      // 持久化失败不影响本次运行
    }
    if (!active) {
      _lastLessonsKey = null;
      _lastExamsKey = null;
      _lastTimetable = null;
      _lastExams = null;
      await cancelAll();
    }
  }

  /// 清空原生侧全部已排提醒（不改变登录态标记）
  static Future<void> cancelAll() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('cancelAll');
    } catch (e) {
      AppLog.w('提醒', '清空提醒失败：$e');
    }
  }

  /// 节次 → 上课时间 (时, 分)，按用户设置的作息表读取
  static (int, int)? _sectionStart(int section) {
    final t = SectionTimes.of(section);
    if (t == null || !t.isSet) return null;
    return (t.startMinutes ~/ 60, t.startMinutes % 60);
  }

  static String _hhmm(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  /// 请求通知权限（Android 13+ 通知）；不涉及精确闹钟权限
  static Future<void> requestPerm() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _ch.invokeMethod('requestPerm');
      } catch (_) {
        // 权限请求失败不阻塞
      }
    }
  }

  /// 一次性权限引导：通知 → 精确闹钟 → 电池优化 →（MIUI）自启动。
  /// 返回各权限最终状态（notifications / exact / battery）；非 Android 返回空。
  static Future<Map<String, bool>> requestAllPerms() async {
    if (kIsWeb || !Platform.isAndroid) return const {};
    try {
      final r = await _ch
          .invokeMethod<Map<dynamic, dynamic>>('requestAllPerms')
          // 用户可能停在系统设置页很久，超时后按未完成处理
          .timeout(const Duration(minutes: 3), onTimeout: () => null);
      if (r == null) return const {};
      return {
        for (final e in r.entries) '${e.key}': e.value == true,
      };
    } catch (_) {
      return const {};
    }
  }

  /// 发送一条即时测试通知（最新通知通道，无需依赖精确闹钟）
  static Future<void> triggerTest() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _ch.invokeMethod('testNotify');
      } catch (_) {
        // 通知发送失败不阻塞
      }
    }
  }

  /// 打开系统「应用通知设置」，用于通道被关闭时手动恢复
  static Future<void> openNotificationSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _ch.invokeMethod('openNotifySettings');
      } catch (_) {
        // 系统设置不可用时忽略
      }
    }
  }

  /// 打开「精确闹钟」授权页（Android 12+ 未授权时提醒可能延迟）
  static Future<void> requestExactAlarm() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _ch.invokeMethod('requestExactAlarm');
      } catch (_) {
        // 系统设置不可用时忽略
      }
    }
  }

  /// 打开「电池优化白名单」授权页（国产 ROM 后台限制可能导致提醒不触发）
  static Future<void> requestBatteryOpt() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _ch.invokeMethod('requestBatteryOpt');
      } catch (_) {
        // 系统设置不可用时忽略
      }
    }
  }

  /// 打开 ROM 的「自启动」管理页（MIUI 可用，其他 ROM 回退到应用详情）
  static Future<void> openAutoStart() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _ch.invokeMethod('openAutoStart');
      } catch (_) {
        // 系统设置不可用时忽略
      }
    }
  }

  /// 60 秒后走「闹钟 → 广播 → 通知」完整链路自测一次
  static Future<void> triggerAlarmTest() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _ch.invokeMethod('testAlarm');
      } catch (_) {
        // 排程失败不阻塞
      }
    }
  }

  /// 读取系统侧提醒状态：通知权限、精确闹钟、已排条数与最近触发时间
  static Future<
      ({
        bool enabled,
        bool exact,
        int pending,
        int? nextAt,
        int? lastAt,
        String lastTitle,
        bool batteryRestricted,
        int channelImportance,
        String lastError,
      })> status() async {
    if (kIsWeb || !Platform.isAndroid) {
      return (
        enabled: false,
        exact: false,
        pending: 0,
        nextAt: null,
        lastAt: null,
        lastTitle: '',
        batteryRestricted: false,
        channelImportance: -1,
        lastError: '',
      );
    }
    try {
      final r = await _ch.invokeMethod('notifyStatus');
      if (r is Map) {
        final next = (r['nextAt'] as num?)?.toInt() ?? 0;
        final last = (r['lastAt'] as num?)?.toInt() ?? 0;
        return (
          enabled: r['enabled'] == true,
          exact: r['exact'] == true,
          pending: (r['pending'] as num?)?.toInt() ?? 0,
          nextAt: next > 0 ? next : null,
          lastAt: last > 0 ? last : null,
          lastTitle: '${r['lastTitle'] ?? ''}',
          batteryRestricted: r['batteryRestricted'] == true,
          channelImportance: (r['channelImportance'] as num?)?.toInt() ?? -1,
          lastError: '${r['lastError'] ?? ''}',
        );
      }
    } catch (e) {
      AppLog.w('提醒', '读取提醒状态失败：$e');
    }
    return (
      enabled: false,
      exact: false,
      pending: 0,
      nextAt: null,
      lastAt: null,
      lastTitle: '',
      batteryRestricted: false,
      channelImportance: -1,
      lastError: '',
    );
  }

  /// 输出一条提醒诊断（权限/闹钟/已排/下一次/最近触发），便于排查漏提醒。
  static Future<void> diagnose(String reason) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final s = await status();
    final last = s.lastAt == null
        ? '无'
        : '${_fmtMs(s.lastAt!)} ${s.lastTitle}';
    AppLog.w(
      '提醒诊断',
      '$reason：通知${s.enabled ? '开' : '关'} · '
          '精确闹钟${s.exact ? '有' : '无'} · '
          '电池优化${s.batteryRestricted ? '未白名单' : '已白名单'} · '
          '渠道重要度${s.channelImportance} · 已排${s.pending}条 · '
          '下次${s.nextAt == null ? '无' : _fmtMs(s.nextAt!)} · 最近触发$last'
          '${s.lastError.isEmpty ? '' : ' · 上次异常${s.lastError}'}',
    );
  }

  static String _fmtMs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return '今天$hm';
    if (day == today.add(const Duration(days: 1))) return '明天$hm';
    return '${d.month}/${d.day} $hm';
  }

  /// 临时诊断：把未来 24 小时内会触发的提醒逐条写日志，
  /// 方便核对某节课是否真的排上了（下课后可直接看运行日志）。
  static void _logUpcoming(String tag, List<Map<String, Object>> items) {
    final now = DateTime.now();
    final limit = now.add(const Duration(hours: 24));
    final soon = <Map<String, Object>>[];
    for (final it in items) {
      final at = DateTime.fromMillisecondsSinceEpoch(
        (it['at'] as num).toInt(),
      );
      if (at.isBefore(now) || at.isAfter(limit)) continue;
      soon.add(it);
    }
    soon.sort((a, b) => (a['at'] as num).compareTo(b['at'] as num));
    for (final it in soon.take(8)) {
      final at = DateTime.fromMillisecondsSinceEpoch(
        (it['at'] as num).toInt(),
      );
      AppLog.w(
        '提醒诊断',
        '$tag 将在 ${_fmtMs(at.millisecondsSinceEpoch)} 触发：'
            '${it['title']}（${it['body']}）',
      );
    }
    if (soon.isEmpty) AppLog.w('提醒诊断', '$tag：未来 24 小时没有待触发提醒');
  }

  /// 冷启动按缓存课表/考试重排一次，不依赖对应页面是否被打开
  static Future<void> scheduleFromCache() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (!_sessionActive) return; // 已退出登录：不恢复旧账号提醒
    final term = TermUtils.currentTerm();
    try {
      final raw =
          await LocalCache.read('cache_timetable_${term.xnm}_${term.xqm}');
      if (raw != null && raw.isNotEmpty) {
        final t = Timetable.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        // 不清空去重 key：同一小时内启动 + 课表页各触发一次时只排一次，避免卡顿
        if (t.courses.isNotEmpty) await scheduleLessons(t);
      }
    } catch (e) {
      AppLog.w('提醒', '启动按缓存重排课表失败：$e');
    }
    try {
      final raw = await LocalCache.read('cache_exam_${term.xnm}_${term.xqm}');
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .map((e) => Exam.fromJson(e as Map<String, dynamic>))
            .toList();
        if (list.isNotEmpty) await scheduleExams(list);
      }
    } catch (e) {
      AppLog.w('提醒', '启动按缓存重排考试失败：$e');
    }
  }

  /// 排未来 [_scheduleDays] 天的上课提醒（每天每门课一条，原生侧持久化并支持开机重建）
  static Future<void> scheduleLessons(Timetable t) async {
    if (!kIsWeb && !Platform.isAndroid) return;
    if (!_sessionActive) return;
    _lastTimetable = t;
    final now = DateTime.now();
    final baseWeek = TermUtils.estimatedCurrentWeek(TermUtils.currentTerm());
    // 内容指纹：仅用课程数会在同小时内课表刷新（换教室/换时间）时漏更新
    final sig = Object.hashAll(t.courses.map((c) =>
        '${c.kcmc}|${c.weekday}|${c.startSection}|${c.endSection}|'
        '${c.zcd}|${c.room}'));
    final key = '${now.year}${now.month}${now.day}-${now.hour}-'
        '$baseWeek-${t.courses.length}-$sig-$remindMinutes-$lessonEnabled';
    if (_lastLessonsKey == key) return;
    _lastLessonsKey = key;

    if (!lessonEnabled || baseWeek == null) {
      await _ch.invokeMethod(
          'scheduleLessons', {'items': <Map<String, Object>>[]});
      return;
    }

    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final items = <Map<String, Object>>[];
    final seen = <String>{};
    var id = 1;
    var full = false;
    for (var d = 0; d < _scheduleDays && !full; d++) {
      final date = today.add(Duration(days: d));
      final week = baseWeek + date.difference(monday).inDays ~/ 7;
      for (final c in t.courses) {
        if (!c.isScheduled || c.weekday != date.weekday) continue;
        if (c.weeks.isNotEmpty && !c.weeks.contains(week)) continue;
        final hm = _sectionStart(c.startSection);
        if (hm == null) continue;
        final fire =
            DateTime(date.year, date.month, date.day, hm.$1, hm.$2)
                .subtract(Duration(minutes: remindMinutes));
        if (!fire.isAfter(now)) continue;
        if (!seen.add('${date.year}${date.month}${date.day}-'
            '${c.startSection}-${c.kcmc}')) {
          continue;
        }
        if (id > _maxLessons) {
          full = true;
          break;
        }
        final start = _hhmm(hm.$1, hm.$2);
        final room = c.room.trim();
        items.add({
          'id': id,
          'title': '上课提醒 · ${c.kcmc}',
          'body': '第${c.startSection}-${c.endSection}节 $start 上课'
              '${room.isEmpty ? '' : ' · $room'}',
          'at': fire.millisecondsSinceEpoch,
          'page': 0,
          // 点击通知直达课程详情所需标识
          'kind': 'lesson',
          'name': c.kcmc,
          'weekday': c.weekday,
          'startSection': c.startSection,
          'week': week,
          'room': room,
        });
        id++;
      }
    }
    await _ch.invokeMethod('scheduleLessons', {'items': items});
    AppLog.d('提醒', '上课提醒排 ${items.length} 条（未来 $_scheduleDays 天）');
    _logUpcoming('上课', items);
  }

  /// 排全部未来考试的提醒：前一天 20:00 预提醒 + 开考前自定义分钟数提醒
  static Future<void> scheduleExams(List<Exam> exams) async {
    if (!kIsWeb && !Platform.isAndroid) return;
    if (!_sessionActive) return;
    _lastExams = exams;
    final key = '$examEnabled-$examRemindMinutes-'
        '${exams.map((e) => e.kssj).join(',')}';
    if (_lastExamsKey == key) return;
    _lastExamsKey = key;

    if (!examEnabled) {
      await _ch.invokeMethod('scheduleExams', {'items': <Map<String, Object>>[]});
      return;
    }

    final now = DateTime.now();
    final items = <Map<String, Object>>[];
    var id = 1000;
    var full = false;
    for (final e in exams) {
      // 教务时间形如 2026-12-30(10:10-12:10)，DateTime.tryParse 会解析失败
      final dt = e.startAt;
      if (dt == null) continue;
      final where = e.cdmc.trim().isEmpty ? '' : ' · ${e.cdmc.trim()}';
      final time = _hhmm(dt.hour, dt.minute);

      // 前一天 20:00 预提醒
      final eve = DateTime(dt.year, dt.month, dt.day - 1, 20, 0);
      if (eve.isAfter(now)) {
        if (id > 1499) {
          full = true;
          break;
        }
        items.add({
          'id': id,
          'title': '明日考试 · ${e.kcmc}',
          'body': '${dt.month}月${dt.day}日 $time$where',
          'at': eve.millisecondsSinceEpoch,
          'page': 2,
          'kind': 'exam',
          'name': e.kcmc,
          'time': e.kssj,
          'room': e.cdmc.trim(),
        });
        id++;
      }

      // 当天提醒：开考前自定义分钟数（与上课提醒保持一致的口径）
      final todayFire = dt.subtract(Duration(minutes: examRemindMinutes));
      if (todayFire.isAfter(now) && todayFire.isBefore(dt)) {
        if (id > 1499) {
          full = true;
          break;
        }
        items.add({
          'id': id,
          'title': '考试提醒 · ${e.kcmc}',
          'body': '${dt.month}月${dt.day}日 $time$where',
          'at': todayFire.millisecondsSinceEpoch,
          'page': 2,
          'kind': 'exam',
          'name': e.kcmc,
          'time': e.kssj,
          'room': e.cdmc.trim(),
        });
        id++;
      }

      // 临近开考再补一条 10 分钟提醒，形成多段提醒（自定义提前量更早时才有意义）
      const finalMinutes = 10;
      final finalFire = dt.subtract(const Duration(minutes: finalMinutes));
      // 提前量太接近 10 分钟时不重复打扰
      if (examRemindMinutes >= 20 &&
          finalFire.isAfter(now) &&
          finalFire.isBefore(dt)) {
        if (id > 1499) {
          full = true;
          break;
        }
        items.add({
          'id': id,
          'title': '即将开考 · ${e.kcmc}',
          'body': '$finalMinutes 分钟后开考$where',
          'at': finalFire.millisecondsSinceEpoch,
          'page': 2,
          'kind': 'exam',
          'name': e.kcmc,
          'time': e.kssj,
          'room': e.cdmc.trim(),
        });
        id++;
      }
    }
    await _ch.invokeMethod('scheduleExams', {'items': items});
    AppLog.d('提醒', '考试提醒排 ${items.length} 条');
    _logUpcoming('考试', items);
    if (full) AppLog.w('提醒', '考试提醒数量超过上限，部分未排程');
  }

  /// 提醒设置变更后重排：关闭时清空对应的已排提醒，开启/改时间则按最近数据重排
  static Future<void> reschedule() async {
    if (!kIsWeb && !Platform.isAndroid) return;
    if (!_sessionActive) return;
    _lastLessonsKey = null;
    _lastExamsKey = null;
    if (!lessonEnabled) {
      await _ch.invokeMethod(
          'scheduleLessons', {'items': <Map<String, Object>>[]});
    } else if (_lastTimetable != null) {
      await scheduleLessons(_lastTimetable!);
    }
    if (!examEnabled) {
      await _ch.invokeMethod(
          'scheduleExams', {'items': <Map<String, Object>>[]});
    } else if (_lastExams != null) {
      await scheduleExams(_lastExams!);
    }
  }
}
