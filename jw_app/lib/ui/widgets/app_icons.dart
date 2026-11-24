import 'package:flutter/material.dart';

/// 语义图标表：业务代码只引用这里的名字，不直接写 `Icons.xxx`。
///
/// 全部使用细线风格（Material outlined / rounded），与水墨体系一致。
abstract final class AppIcons {
  // 底部导航
  static const IconData timetable = Icons.calendar_view_week_outlined;
  static const IconData timetableActive = Icons.calendar_view_week_rounded;
  static const IconData grade = Icons.assessment_outlined;
  static const IconData gradeActive = Icons.assessment_rounded;
  static const IconData exam = Icons.edit_note_outlined;
  static const IconData examActive = Icons.edit_note_rounded;
  static const IconData academic = Icons.school_outlined;
  static const IconData academicActive = Icons.school_rounded;
  static const IconData profile = Icons.person_outline_rounded;
  static const IconData profileActive = Icons.person_rounded;

  // 通用
  static const IconData back = Icons.arrow_back_ios_new_rounded;
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData chevronLeft = Icons.chevron_left_rounded;
  static const IconData expandMore = Icons.expand_more_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData error = Icons.error_outline_rounded;
  static const IconData success = Icons.check_circle_rounded;
  static const IconData cloudOff = Icons.cloud_off_rounded;
  static const IconData inbox = Icons.inbox_rounded;
  static const IconData lock = Icons.lock_outline_rounded;
  static const IconData login = Icons.login_rounded;
  static const IconData logout = Icons.logout_rounded;
  static const IconData week = Icons.event_outlined;
  static const IconData time = Icons.schedule_outlined;
  static const IconData examEvent = Icons.event_available_outlined;

  // 登录
  static const IconData shield = Icons.verified_user_outlined;
  static const IconData school = Icons.school_outlined;

  // 课表
  static const IconData today = Icons.today_outlined;
  static const IconData location = Icons.place_outlined;
  static const IconData teacher = Icons.person_outline_rounded;
  static const IconData add = Icons.add_rounded;

  // 成绩
  static const IconData chartBar = Icons.bar_chart_rounded;
  static const IconData leaderboard = Icons.leaderboard_outlined;

  // 考试
  static const IconData seat = Icons.chair_outlined;
  static const IconData method = Icons.draw_outlined;
  static const IconData verified = Icons.verified_outlined;
  static const IconData hourglass = Icons.hourglass_bottom_rounded;
  static const IconData widget = Icons.widgets_outlined;

  // 学业
  static const IconData accountBalance = Icons.account_balance_outlined;
  static const IconData book = Icons.menu_book_outlined;
  static const IconData groups = Icons.groups_outlined;
  static const IconData warningAmber = Icons.warning_amber_rounded;

  // 我的 / 功能入口
  static const IconData settings = Icons.settings_outlined;
  static const IconData room = Icons.meeting_room_outlined;
  static const IconData bolt = Icons.bolt_rounded;
  static const IconData update = Icons.system_update_alt_rounded;
  static const IconData feedback = Icons.feedback_outlined;
  static const IconData mail = Icons.mail_outline_rounded;
  static const IconData debug = Icons.developer_mode_outlined;

  // 二级页通用
  static const IconData delete = Icons.delete_outline_rounded;
  static const IconData download = Icons.download_rounded;
  static const IconData upload = Icons.upload_rounded;
  static const IconData copy = Icons.copy_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData filter = Icons.tune_rounded;
  static const IconData list = Icons.format_list_bulleted_rounded;
  static const IconData star = Icons.star_outline_rounded;
  static const IconData starFilled = Icons.star_rounded;
  static const IconData pause = Icons.pause_rounded;
  static const IconData stop = Icons.stop_rounded;
  static const IconData edit = Icons.edit_outlined;
  static const IconData check = Icons.check_rounded;
  static const IconData more = Icons.more_horiz_rounded;
  static const IconData storage = Icons.storage_rounded;
  static const IconData cleaning = Icons.cleaning_services_outlined;
  static const IconData notifications = Icons.notifications_none_rounded;
  static const IconData tune = Icons.tune_rounded;
  static const IconData palette = Icons.palette_outlined;
  static const IconData shieldCheck = Icons.verified_user_outlined;
  static const IconData sort = Icons.sort_rounded;
  static const IconData code = Icons.code_rounded;
  static const IconData description = Icons.description_outlined;
}
