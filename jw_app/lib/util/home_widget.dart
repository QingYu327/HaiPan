import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'app_log.dart';
import 'term_utils.dart';

/// 桌面小组件数据同步：今日课表（「仅课表」与「课表 + 考试」两个组件共用）。
///
/// 把渲染所需的最小快照写入 SharedPreferences（原生小组件读取
/// `flutter.widget.payload`），再通知原生立即刷新。
/// 快照包含当前周次与本周周一日期，小组件据此自行推算跨天后的周次。
class HomeWidgetSync {
  HomeWidgetSync._();

  static const _ch = MethodChannel('cn.gdou.xiuhong/widget');
  static const _key = 'widget.payload';

  static Future<void> update(Timetable timetable, List<Exam> exams) async {
    if (!Platform.isAndroid) return;
    try {
      final now = DateTime.now();
      final week = TermUtils.estimatedCurrentWeek(TermUtils.currentTerm()) ?? 0;
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final courses = <Map<String, Object>>[
        for (final c in timetable.courses)
          if (c.isScheduled)
            {
              'w': c.weekday,
              's': c.startSection,
              'e': c.endSection,
              'n': c.kcmc,
              'r': c.room,
              'ws': c.weeks.toList()..sort(),
            }
      ];
      final upcoming = <Map<String, Object>>[
        for (final e in exams)
          if (e.startAt != null)
            {
              'n': e.kcmc,
              'at': e.startAt!.millisecondsSinceEpoch,
              'p': e.cdmc,
            }
      ]..sort((a, b) => (a['at'] as int).compareTo(b['at'] as int));
      final payload = jsonEncode({
        'at': now.millisecondsSinceEpoch,
        'week': week,
        'monday': monday.millisecondsSinceEpoch,
        'courses': courses,
        'exams': upcoming,
      });
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, payload);
      await _ch.invokeMethod('refresh');
      AppLog.d('小组件', '已同步 ${courses.length} 门课 / ${upcoming.length} 场考试');
    } catch (e) {
      AppLog.w('小组件', '同步失败：$e');
    }
  }
}
