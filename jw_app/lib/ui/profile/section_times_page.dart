import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../theme/ink_tokens.dart';
import '../../util/section_times.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_dialog.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

/// 三级设置页：维护每一节的上课 / 下课时间。
///
/// 改动会同时作用于课表时间栏、上课提醒与桌面小组件。
class SectionTimesPage extends ConsumerWidget {
  const SectionTimesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final times = s.sectionTimes;
    return InkPageScaffold(
      showBack: true,
      title: '课程时间',
      children: [
        InkCard(
          child: Text(
            '用于课表时间栏、上课提醒和桌面小组件的起止时间计算。'
            '修改后立即生效；未设置的节次不会显示时间，也不参与下课倒计时。',
            style: context.tsSecondary,
          ),
        ),
        const InkSectionHeader(title: '节次时间'),
        InkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < times.length; i++) ...[
                _row(context, ref, times[i]),
                if (i != times.length - 1)
                  Container(
                    height: InkStroke.hairline,
                    margin: const EdgeInsets.only(left: InkSpacing.l),
                    color: context.ink.hairline,
                  ),
              ],
            ],
          ),
        ),
        const InkSectionHeader(title: '维护'),
        InkCard(
          padding: EdgeInsets.zero,
          child: InkSettingTile(
            title: '恢复默认作息',
            subtitle: '1-10 节恢复默认，11-12 节清空',
            icon: AppIcons.refresh,
            iconTone: InkTone.info,
            onTap: () => _reset(context, ref),
            showDivider: false,
          ),
        ),
        const SizedBox(height: InkSpacing.l),
      ],
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, SectionTime t) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: InkSpacing.l,
        vertical: InkSpacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              '第 ${t.section} 节',
              style: context.tsBodyStrong,
            ),
          ),
          _timeCell(
            context,
            label: '上课',
            value: t.isSet ? t.startLabel : '未设置',
            unset: !t.isSet,
            onTap: () => _pick(context, ref, t, true),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('—', style: context.tsCaption),
          ),
          _timeCell(
            context,
            label: '下课',
            value: t.isSet ? t.endLabel : '未设置',
            unset: !t.isSet,
            onTap: () => _pick(context, ref, t, false),
          ),
        ],
      ),
    );
  }

  Widget _timeCell(
    BuildContext context, {
    required String label,
    required String value,
    required bool unset,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.tsCaption),
              const SizedBox(height: 1),
              Text(
                value,
                style: context.tsBodyStrong.copyWith(
                  color: unset
                      ? context.ink.secondaryLabel
                      : context.scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    SectionTime t,
    bool start,
  ) async {
    final current = start ? t.startMinutes : t.endMinutes;
    final initial = current >= 0
        ? TimeOfDay(hour: current ~/ 60, minute: current % 60)
        : const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: '第 ${t.section} 节 ${start ? '上课' : '下课'}时间',
    );
    if (picked == null || !context.mounted) return;

    final minutes = picked.hour * 60 + picked.minute;
    var s = t.startMinutes;
    var e = t.endMinutes;
    if (start) {
      s = minutes;
      if (e < 0) e = (minutes + 45).clamp(0, 23 * 60 + 59).toInt();
    } else {
      e = minutes;
      if (s < 0) s = (minutes - 45).clamp(0, 23 * 60 + 59).toInt();
    }
    if (s < 0 || e <= s) {
      showInkToast(context, '下课时间需晚于上课时间', error: true);
      return;
    }

    final times = ref.read(settingsProvider).sectionTimes;
    final next = [
      for (final x in times)
        x.section == t.section ? SectionTime(t.section, s, e) : x,
    ];
    await ref.read(settingsProvider.notifier).setSectionTimes(next);
    if (context.mounted) {
      showInkToast(context, '第 ${t.section} 节时间已更新');
    }
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final ok = await showInkDialog(
      context,
      title: '恢复默认作息',
      message: '将把 1-10 节恢复为默认时间，11-12 节清空。',
      confirmText: '恢复',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await ref
        .read(settingsProvider.notifier)
        .setSectionTimes(kDefaultSectionTimes);
    if (context.mounted) showInkToast(context, '已恢复默认课程时间');
  }
}
