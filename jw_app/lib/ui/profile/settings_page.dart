import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/ink_page_transition.dart';
import '../../theme/ink_tokens.dart';
import '../../util/lesson_notifier.dart';
import '../../util/term_utils.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_dialog.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';
import '../widgets/ink_panel.dart';
import '../widgets/permission_prompt.dart';
import 'storage_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // 滑条拖动中的临时值：拖动过程仅更新本地 UI，松手再真正生效，避免即时排程卡顿
  double? _dragFont;
  int? _dragRemind;
  int? _dragExam;
  double? _dragBgBlur;

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final s = ref.watch(settingsProvider);
    return InkPageScaffold(
      showBack: true,
      title: '设置',
      children: [
        const InkSectionHeader(title: '外观'),
        InkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('明暗模式', style: context.tsBodyStrong),
              const SizedBox(height: InkSpacing.m),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
                style: SegmentedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.system, label: Text('跟随系统')),
                  ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (sel) {
                  final m = sel.first;
                  ref.read(settingsProvider.notifier).setThemeMode(m);
                  final label = switch (m) {
                    ThemeMode.light => '浅色',
                    ThemeMode.dark => '深色',
                    _ => '跟随系统',
                  };
                  showInkToast(context, '外观已改为 $label');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: InkSpacing.m),
        InkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('字体大小', style: context.tsBodyStrong),
                  const Spacer(),
                  Text(
                    '${(_dragFont ?? s.fontSizeScale).toStringAsFixed(2)}×',
                    style: context.tsBodyStrong.copyWith(color: cs.primary),
                  ),
                ],
              ),
              const SizedBox(height: InkSpacing.s),
              Slider(
                value: (_dragFont ?? s.fontSizeScale).clamp(0.8, 1.4),
                min: 0.8,
                max: 1.4,
                divisions: 12,
                label: '${(_dragFont ?? s.fontSizeScale).toStringAsFixed(2)}×',
                onChanged: (v) => setState(() => _dragFont = v),
                onChangeEnd: (v) {
                  _dragFont = null;
                  final n = ref.read(settingsProvider.notifier);
                  n.setFontSize(v);
                  if (mounted) {
                    showInkToast(
                        context, '字体大小已设为 ${v.toStringAsFixed(2)}×');
                  }
                },
              ),
              Row(
                children: [
                  Expanded(child: Text('小', style: context.tsCaption)),
                  Expanded(
                    child: Text('标准',
                        textAlign: TextAlign.center,
                        style: context.tsCaption),
                  ),
                  Expanded(
                    child: Text('大',
                        textAlign: TextAlign.end, style: context.tsCaption),
                  ),
                ],
              ),
            ],
          ),
        ),
        const InkSectionHeader(title: '背景'),
        _backgroundSection(context, ref, s),
        const InkSectionHeader(title: '提醒'),
        _remindSection(context, ref, s),
        const InkSectionHeader(title: '课表'),
        InkCard(
          padding: EdgeInsets.zero,
          child: _semesterStartRow(context, ref),
        ),
        const InkSectionHeader(title: '存储'),
        const _StorageSection(),
        const InkSectionHeader(title: '维护'),
        InkCard(
          padding: EdgeInsets.zero,
          child: InkSettingTile(
            title: '错误修复',
            icon: AppIcons.shieldCheck,
            iconTone: InkTone.info,
            onTap: () => _clearCache(context, ref),
            showDivider: false,
          ),
        ),
        const SizedBox(height: InkSpacing.l),
      ],
    );
  }

  /// 当前学期开学日（用于校准周数）
  Widget _semesterStartRow(BuildContext context, WidgetRef ref) {
    final start = ref.watch(settingsProvider).semesterStart;
    final txt = start == null
        ? '系统估算（${TermUtils.currentTerm().xqm == "3" ? "9月" : "3月"}）'
        : '${start.year}-${start.month.toString().padLeft(2, "0")}-${start.day.toString().padLeft(2, "0")}';
    return InkSettingTile(
      title: '开学周起始日期',
      icon: AppIcons.week,
      iconTone: InkTone.info,
      trailing: Text(
        txt,
        style: context.tsBodyStrong.copyWith(color: context.scheme.primary),
      ),
      onTap: () => _pickSemesterStart(context, ref, start),
      showDivider: false,
    );
  }

  Future<void> _pickSemesterStart(
      BuildContext context, WidgetRef ref, DateTime? current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1, 8, 1),
      lastDate: now.add(const Duration(days: 60)),
      helpText: '选择当前学期开学日',
    );
    if (picked == null) return;
    await ref.read(settingsProvider.notifier).setSemesterStart(picked);
    if (context.mounted) showInkToast(context, '已设置开学日，周数将按此校准');
  }

  Widget _remindSection(BuildContext context, WidgetRef ref, AppSettings s) {
    final cs = context.scheme;
    return InkCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkSettingTile(
            title: '上课提醒',
            icon: AppIcons.notifications,
            iconTone: InkTone.info,
            trailing: Switch(
              value: s.remindEnabled,
              onChanged: (v) {
                if (v) LessonNotifier.requestPerm();
                ref.read(settingsProvider.notifier).setRemindEnabled(v);
                showInkToast(context, v ? '已开启上课提醒' : '已关闭上课提醒');
              },
            ),
          ),
          InkSettingTile(
            title: '考试提醒',
            icon: AppIcons.examEvent,
            iconTone: InkTone.info,
            trailing: Switch(
              value: s.examRemindEnabled,
              onChanged: (v) {
                if (v) LessonNotifier.requestPerm();
                ref.read(settingsProvider.notifier).setExamRemindEnabled(v);
                showInkToast(context, v ? '已开启考试提醒' : '已关闭考试提醒');
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              InkSpacing.l,
              InkSpacing.s,
              InkSpacing.l,
              InkSpacing.m,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('上课提前提醒', style: context.tsBody),
                    const Spacer(),
                    Text(
                      '${_dragRemind ?? s.remindMinutes} 分钟',
                      style:
                          context.tsBodyStrong.copyWith(color: cs.primary),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text('5', style: context.tsCaption),
                    Expanded(
                      child: Slider(
                        value: (_dragRemind ?? s.remindMinutes).toDouble(),
                        min: 5,
                        max: 60,
                        divisions: 11,
                        label: '${_dragRemind ?? s.remindMinutes}',
                        // 拖动只更新本地显示，松手才真正生效，避免即时重置提醒造成卡顿
                        onChanged: (v) =>
                            setState(() => _dragRemind = v.round()),
                        onChangeEnd: (v) {
                          final mins = v.round();
                          _dragRemind = null;
                          ref
                              .read(settingsProvider.notifier)
                              .setRemindMinutes(mins);
                          if (mounted) {
                            showInkToast(
                                context, '上课提前提醒已改为 $mins 分钟');
                          }
                        },
                      ),
                    ),
                    Text('60', style: context.tsCaption),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              InkSpacing.l,
              0,
              InkSpacing.l,
              InkSpacing.m,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('考试提前提醒', style: context.tsBody),
                    const Spacer(),
                    Text(
                      '${_dragExam ?? s.examRemindMinutes} 分钟',
                      style:
                          context.tsBodyStrong.copyWith(color: cs.primary),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text('5', style: context.tsCaption),
                    Expanded(
                      child: Slider(
                        value: (_dragExam ?? s.examRemindMinutes).toDouble(),
                        min: 5,
                        max: 120,
                        divisions: 23,
                        label: '${_dragExam ?? s.examRemindMinutes}',
                        onChanged: (v) =>
                            setState(() => _dragExam = v.round()),
                        onChangeEnd: (v) {
                          final mins = v.round();
                          _dragExam = null;
                          ref
                              .read(settingsProvider.notifier)
                              .setExamRemindMinutes(mins);
                          if (mounted) {
                            showInkToast(
                                context, '考试提前提醒已改为 $mins 分钟');
                          }
                        },
                      ),
                    ),
                    Text('120', style: context.tsCaption),
                  ],
                ),
              ],
            ),
          ),
          // 权限被跳过/误关时可以在这里重新走一遍一键授权
          InkSettingTile(
            title: '权限与后台运行',
            subtitle: '通知、精确闹钟、电池优化白名单',
            icon: AppIcons.shieldCheck,
            iconTone: InkTone.info,
            trailing: Text(
              '去授权',
              style: context.tsBodyStrong.copyWith(color: cs.primary),
            ),
            onTap: () => showPermissionPrompt(context),
            showDivider: false,
          ),
        ],
      ),
    );
  }

  static const List<int> _bgColors = [
    0xFFF7F9FA, // 宣纸白
    0xFFEDF4F8, // 雾蓝
    0xFFF8EEE8, // 暖粉
    0xFFEEF4EB, // 竹绿
    0xFFFCF4E7, // 暖黄
    0xFFE9EFF7, // 夜蓝
    0xFF33506A, // 深蓝
    0xFF1B272E, // 墨黑
  ];

  static const List<(String, String)> _bgStyles = [
    ('ink', '宣纸'),
    ('mist', '晨雾'),
    ('dusk', '暮色'),
    ('bamboo', '竹影'),
    ('sunrise', '暖阳'),
    ('night', '夜墨'),
    ('solid', '纯色'),
    ('image', '图片'),
  ];

  Widget _backgroundSection(
      BuildContext context, WidgetRef ref, AppSettings s) {
    final cs = context.scheme;
    final isDark = context.isDark;
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('背景风格', style: context.tsBodyStrong),
          const SizedBox(height: InkSpacing.m),
          Wrap(
            spacing: InkSpacing.s,
            runSpacing: InkSpacing.s,
            children: [
              for (final it in _bgStyles)
                _bgTile(context, ref, s, it.$1, it.$2, isDark),
            ],
          ),
          if (s.backgroundStyle == 'solid') ...[
            const SizedBox(height: InkSpacing.l),
            Text('纯色色板', style: context.tsLabel),
            const SizedBox(height: InkSpacing.s),
            Wrap(
              spacing: InkSpacing.s,
              runSpacing: InkSpacing.s,
              children: [
                for (final c in _bgColors)
                  GestureDetector(
                    onTap: () => ref
                        .read(settingsProvider.notifier)
                        .setBackgroundSeed(c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: s.backgroundSeed == c
                              ? cs.primary
                              : context.ink.hairline,
                          width: s.backgroundSeed == c ? 2.4 : InkStroke.hairline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (s.backgroundStyle == 'image') ...[
            const SizedBox(height: InkSpacing.l),
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.backgroundImage.isEmpty ? '尚未选择图片' : '已选择本地图片',
                    style: context.tsBody,
                  ),
                ),
                TextButton(
                  onPressed: () => _pickLocalImage(ref),
                  child: Text(s.backgroundImage.isEmpty ? '选择图片' : '重新选择'),
                ),
              ],
            ),
            const SizedBox(height: InkSpacing.s),
            Row(
              children: [
                Text('模糊', style: context.tsBody),
                Expanded(
                  child: Slider(
                    value: _dragBgBlur ?? s.backgroundBlur.clamp(0, 24),
                    min: 0,
                    max: 24,
                    divisions: 12,
                    label: (_dragBgBlur ?? s.backgroundBlur).toStringAsFixed(0),
                    onChanged: (v) => setState(() => _dragBgBlur = v),
                    onChangeEnd: (v) {
                      setState(() => _dragBgBlur = null);
                      ref
                          .read(settingsProvider.notifier)
                          .setBackgroundBlur(v);
                    },
                  ),
                ),
                Text((_dragBgBlur ?? s.backgroundBlur).toStringAsFixed(0),
                    style: context.tsCaption),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bgTile(
    BuildContext context,
    WidgetRef ref,
    AppSettings s,
    String style,
    String label,
    bool isDark,
  ) {
    final cs = context.scheme;
    final selected = s.backgroundStyle == style;
    return GestureDetector(
      onTap: () async {
        await ref.read(settingsProvider.notifier).setBackgroundStyle(style);
        if (style == 'image' &&
            ref.read(settingsProvider).backgroundImage.isEmpty) {
          await _pickLocalImage(ref);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: InkMotion.fast,
            width: 58,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? cs.primary : context.ink.hairline,
                width: selected ? 2.2 : InkStroke.hairline,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _bgPreview(context, s, style, isDark),
            ),
          ),
          const SizedBox(height: InkSpacing.xs),
          Text(
            label,
            style: InkTextStyles.label.copyWith(
              color: selected ? cs.primary : context.ink.secondaryLabel,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bgPreview(
      BuildContext context, AppSettings s, String style, bool isDark) {
    if (style == 'solid') return ColoredBox(color: Color(s.backgroundSeed));
    if (style == 'image') {
      if (s.backgroundImage.isEmpty) {
        return ColoredBox(
          color: context.ink.groupedBackground,
          child: Icon(AppIcons.palette,
              size: 18, color: context.ink.secondaryLabel),
        );
      }
      return Image.file(File(s.backgroundImage),
          fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox());
    }
    if (style == 'ink') {
      return ColoredBox(color: context.scheme.surface);
    }
    final preset = inkBgPresets[style];
    if (preset == null) return ColoredBox(color: context.scheme.surface);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark ? preset.$2 : preset.$1,
        ),
      ),
    );
  }

  static const MethodChannel _pickChannel =
      MethodChannel('cn.gdou.xiuhong/pick');

  /// 从相册选择本地图片，原生侧会压缩并复制到应用私有目录。
  Future<void> _pickLocalImage(WidgetRef ref) async {
    try {
      final path = await _pickChannel.invokeMethod<String>('pickImage');
      if (path == null || path.isEmpty) return;
      await ref.read(settingsProvider.notifier).setBackgroundImage(path);
      if (!mounted) return;
      showInkToast(context, '已应用本地背景');
    } catch (e) {
      if (!mounted) return;
      showInkToast(context, '选择图片失败：$e', error: true);
    }
  }

  /// 清理缓存：清 Cookie/学籍缓存并回到登录页
  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await showInkDialog(
      context,
      title: '清理缓存',
      message: '将清除登录会话与本地缓存数据，并返回登录页（学号会保留）。'
          '遇到数据异常、加载失败等问题时可尝试此操作修复。',
      confirmText: '清理',
      danger: true,
    );
    if (!confirmed) return;
    await ref.read(sessionProvider.notifier).resetForRepair();
    if (context.mounted) {
      showInkToast(context, '已清理缓存，请重新登录');
    }
  }
}

/// 本地占用入口：显示占用大小，点击进入存储占用详情页
class _StorageSection extends ConsumerStatefulWidget {
  const _StorageSection();
  @override
  ConsumerState<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<_StorageSection> {
  int _bytes = -1;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    int total = 0;
    try {
      final dir = await getApplicationSupportDirectory();
      await for (final f in dir.list(recursive: true, followLinks: false)) {
        if (f is File) {
          try {
            total += await f.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _bytes = total);
  }

  String _fmt(int b) {
    if (b < 0) return '计算中…';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return InkCard(
      padding: EdgeInsets.zero,
      child: InkSettingTile(
        title: '本地占用',
        subtitle: _fmt(_bytes),
        icon: AppIcons.storage,
        iconTone: InkTone.info,
        onTap: () => Navigator.push(context,
            InkPageRoute(builder: (_) => const StoragePage())),
        showDivider: false,
      ),
    );
  }
}
