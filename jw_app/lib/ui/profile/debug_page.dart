import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/usage_api.dart';
import '../../providers/session_provider.dart';
import '../../theme/ink_page_transition.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../../util/lesson_notifier.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';
import 'log_page.dart';
import 'tunnel_page.dart';
import 'usage_page.dart';

/// 调试：收纳"运行日志 / 日志保留天数 / 发送测试通知"
class DebugPage extends ConsumerWidget {
  const DebugPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner =
        ref.watch(sessionProvider).student.xh == UsageTracker.ownerXh;
    return InkPageScaffold(
      showBack: true,
      title: '调试',
      children: [
        InkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // 用户统计：仅管理员账号可见（收纳于调试图内）
              if (isOwner)
                InkSettingTile(
                  title: '用户统计',
                  icon: AppIcons.chartBar,
                  iconTone: InkTone.info,
                  onTap: () => Navigator.push(context,
                      InkPageRoute(builder: (_) => const UsagePage())),
                ),
              if (isOwner)
                InkSettingTile(
                  title: '公网通道',
                  icon: AppIcons.bolt,
                  iconTone: InkTone.info,
                  onTap: () => Navigator.push(context,
                      InkPageRoute(builder: (_) => const TunnelPage())),
                ),
              InkSettingTile(
                title: '运行日志',
                icon: AppIcons.description,
                iconTone: InkTone.info,
                onTap: () => Navigator.push(context,
                    InkPageRoute(builder: (_) => const LogPage())),
              ),
              const _RetentionRow(),
              const _DetailRow(),
              InkSettingTile(
                title: '发送测试通知',
                icon: AppIcons.notifications,
                iconTone: InkTone.info,
                onTap: () async {
                  try {
                    await LessonNotifier.requestPerm();
                    await LessonNotifier.triggerTest();
                    if (context.mounted) {
                      showInkToast(context, '已发送测试通知，请留意通知栏');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showInkToast(context, '发送失败：$e', error: true);
                    }
                  }
                },
                showDivider: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: InkSpacing.l),
        const _ReminderDiag(),
      ],
    );
  }
}

/// 提醒诊断：通知权限 / 精确闹钟 / 已排条数 / 下一次触发
class _ReminderDiag extends StatefulWidget {
  const _ReminderDiag();

  @override
  State<_ReminderDiag> createState() => _ReminderDiagState();
}

class _ReminderDiagState extends State<_ReminderDiag> {
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
  })? _st;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await LessonNotifier.status();
    if (mounted) setState(() => _st = s);
    await LessonNotifier.diagnose('调试页');
  }

  /// 走真实闹钟链路：60 秒后由系统广播弹出，验证后台/锁屏下也能收到
  Future<void> _alarmTest() async {
    await LessonNotifier.requestPerm();
    await LessonNotifier.triggerAlarmTest();
    if (!mounted) return;
    showInkToast(context, '已排程：60 秒后弹提醒，可切到后台或锁屏等待');
  }

  Future<void> _reschedule() async {
    setState(() => _busy = true);
    await LessonNotifier.requestPerm();
    await LessonNotifier.scheduleFromCache();
    await LessonNotifier.reschedule();
    final s = await LessonNotifier.status();
    if (!mounted) return;
    setState(() {
      _st = s;
      _busy = false;
    });
    showInkToast(context, '已重新排程：${s.pending} 条');
  }

  String _fmt(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final hm = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return '今天 $hm';
    if (day == today.add(const Duration(days: 1))) return '明天 $hm';
    return '${d.month}/${d.day} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final s = _st;
    final line = s == null
        ? '读取中…'
        : '已排 ${s.pending} 条 · '
            '${s.nextAt == null ? '暂无下一次提醒' : '下次 ${_fmt(s.nextAt!)}'}'
            '${s.lastAt == null ? '' : ' · 最近触发 ${_fmt(s.lastAt!)} ${s.lastTitle}'}';
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('提醒诊断', style: context.tsBody),
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : _alarmTest,
                child: const Text('闹钟自测'),
              ),
              TextButton(
                onPressed: _busy ? null : _reschedule,
                child: Text(_busy ? '处理中…' : '重新排程'),
              ),
            ],
          ),
          const SizedBox(height: InkSpacing.xs),
          Text(line, style: context.tsCaption),
          if (s != null && !s.enabled) ...[
            const SizedBox(height: InkSpacing.m),
            InkBanner(
              message: '通知权限未开启，提醒不会显示',
              tone: InkTone.danger,
              icon: AppIcons.warning,
              action: TextButton(
                onPressed: LessonNotifier.openNotificationSettings,
                child: const Text('去开启'),
              ),
            ),
          ],
          if (s != null && s.enabled && s.channelImportance == 0) ...[
            const SizedBox(height: InkSpacing.m),
            InkBanner(
              message: '「上课/考试提醒」通知渠道已被关闭，提醒不会弹出',
              tone: InkTone.danger,
              icon: AppIcons.warning,
              action: TextButton(
                onPressed: LessonNotifier.openNotificationSettings,
                child: const Text('去开启'),
              ),
            ),
          ],
          if (s != null && s.enabled && !s.exact) ...[
            const SizedBox(height: InkSpacing.m),
            InkBanner(
              message: '未授予精确闹钟，提醒可能被系统延后',
              tone: InkTone.warning,
              icon: AppIcons.warning,
              action: TextButton(
                onPressed: LessonNotifier.requestExactAlarm,
                child: const Text('去授权'),
              ),
            ),
          ],
          if (s != null && s.batteryRestricted) ...[
            const SizedBox(height: InkSpacing.m),
            InkBanner(
              message: '未加入电池优化白名单，系统可能在后台拦截提醒；'
                  'MIUI 还需允许「自启动」',
              tone: InkTone.warning,
              icon: AppIcons.warning,
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: LessonNotifier.requestBatteryOpt,
                    child: const Text('去设置'),
                  ),
                  TextButton(
                    onPressed: LessonNotifier.openAutoStart,
                    child: const Text('自启动'),
                  ),
                ],
              ),
            ),
          ],
          if (s != null && s.lastError.isNotEmpty) ...[
            const SizedBox(height: InkSpacing.m),
            InkBanner(
              message: '上次弹通知失败：${s.lastError}',
              tone: InkTone.danger,
              icon: AppIcons.warning,
            ),
          ],
          if (s != null && s.enabled && s.exact && s.pending == 0) ...[
            const SizedBox(height: InkSpacing.m),
            const InkBanner(
              message: '当前没有待触发提醒，请打开课表页或点「重新排程」',
              tone: InkTone.info,
              icon: AppIcons.info,
            ),
          ],
        ],
      ),
    );
  }
}

/// 输出详细日志开关：关闭=查看级（仅 W/E），打开=调试级（含 D 级细节）
class _DetailRow extends StatefulWidget {
  const _DetailRow();
  @override
  State<_DetailRow> createState() => _DetailRowState();
}

class _DetailRowState extends State<_DetailRow> {
  @override
  Widget build(BuildContext context) {
    return InkSettingTile(
      title: '输出详细日志',
      icon: AppIcons.tune,
      iconTone: InkTone.info,
      trailing: Switch(
        value: AppLog.debugDetail,
        onChanged: (on) {
          AppLog.setDetail(on).then((_) {
            if (mounted) setState(() {});
          });
        },
      ),
    );
  }
}

/// 日志保留天数选择（超过的天数自动清理）
class _RetentionRow extends StatefulWidget {
  const _RetentionRow();
  @override
  State<_RetentionRow> createState() => _RetentionRowState();
}

class _RetentionRowState extends State<_RetentionRow> {
  @override
  Widget build(BuildContext context) {
    return InkSettingTile(
      title: '日志保留',
      icon: AppIcons.time,
      iconTone: InkTone.info,
      trailing: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: WidgetStatePropertyAll(Size(0, 32)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8),
          ),
          textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
        ),
        segments: const [
          ButtonSegment(value: 3, label: Text('3 天')),
          ButtonSegment(value: 7, label: Text('7 天')),
          ButtonSegment(value: 30, label: Text('30 天')),
        ],
        selected: {AppLog.retentionDays},
        onSelectionChanged: (sel) {
          AppLog.setRetention(sel.first).then((_) {
            if (mounted) setState(() {});
          });
        },
      ),
    );
  }
}
