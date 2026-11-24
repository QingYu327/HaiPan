import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../util/lesson_notifier.dart';
import 'ink_dialog.dart';
import 'ink_notice.dart';

/// 首次启动权限引导是否已弹过（跳过也算，避免每次启动打扰）。
const String _kPrompted = 'settings_perm_prompted';

Future<bool> permissionPrompted() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kPrompted) ?? false;
}

Future<void> markPermissionPrompted() async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_kPrompted, true);
}

/// 权限引导：说明用途后一次性依次打开
/// 通知 → 精确闹钟 → 电池优化（MIUI 额外含自启动）系统页面。
/// 用户选择「稍后」也会记录已提示；设置页可随时重新进入。
Future<void> showPermissionPrompt(BuildContext context) async {
  final go = await showInkDialog(
    context,
    title: '开启必要权限',
    message: '为了准点提醒上课与考试，需要以下授权：\n'
        '· 通知：显示提醒\n'
        '· 精确闹钟：到点准时触发\n'
        '· 电池优化白名单：后台不被系统拦截\n\n'
        '确认后会依次弹出系统页面，逐项允许即可。'
        '也可以稍后在「设置 → 权限与后台运行」中重新授权。',
    cancelText: '稍后',
    confirmText: '一键授权',
  );
  await markPermissionPrompted();
  if (!go) return;

  final r = await LessonNotifier.requestAllPerms();
  if (!context.mounted) return;
  final ok = r['notifications'] == true;
  showInkToast(
    context,
    ok ? '权限引导已完成' : '仍有权限未开启，可稍后在设置中重新授权',
    error: !ok,
  );
}
