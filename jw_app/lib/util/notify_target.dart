import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 通知点击携带的目标：用于直达课程/考试详情。
///
/// 原生侧在点击通知时把标识写进 MainActivity 的 intent，
/// Flutter 启动/恢复后通过 `cn.gdou.xiuhong/nav` 读取并写入本 Provider，
/// 由课表/考试页消费一次后清空。
class NotifyTarget {
  const NotifyTarget({
    this.id = 0,
    this.page = 0,
    this.kind = '',
    this.name = '',
    this.weekday = 0,
    this.startSection = 0,
    this.week = 0,
    this.time = '',
    this.room = '',
  });

  /// 通知 id（同一条通知只处理一次）
  final int id;

  /// 0 课表 / 1 成绩 / 2 考试 / 3 学业 / 4 我的
  final int page;

  /// lesson（上课提醒）/ exam（考试提醒）
  final String kind;
  final String name;
  final int weekday;
  final int startSection;
  final int week;
  final String time; // 考试时间原文
  final String room;

  bool get isLesson => kind == 'lesson';
  bool get isExam => kind == 'exam';

  factory NotifyTarget.fromMap(Map<dynamic, dynamic> m) => NotifyTarget(
        id: (m['id'] as num?)?.toInt() ?? 0,
        page: (m['page'] as num?)?.toInt() ?? 0,
        kind: '${m['kind'] ?? ''}',
        name: '${m['name'] ?? ''}',
        weekday: (m['weekday'] as num?)?.toInt() ?? 0,
        startSection: (m['startSection'] as num?)?.toInt() ?? 0,
        week: (m['week'] as num?)?.toInt() ?? 0,
        time: '${m['time'] ?? ''}',
        room: '${m['room'] ?? ''}',
      );

  String get logText => 'id=$id page=$page kind=$kind '
      'name=$name weekday=$weekday start=$startSection week=$week time=$time';
}

/// 待处理的通知跳转目标；页面消费后置空。
final notifyTargetProvider = StateProvider<NotifyTarget?>((ref) => null);
