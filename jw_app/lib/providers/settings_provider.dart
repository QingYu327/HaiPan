import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/app_log.dart';
import '../util/home_widget.dart';
import '../util/lesson_notifier.dart';
import '../util/section_times.dart';
import '../util/term_utils.dart';

class AppSettings {
  final ThemeMode themeMode; // 明暗：system / light / dark
  final double fontSizeScale; // 字体缩放倍数
  final String locale; // zh / en
  final bool showDebug; // 「调试」隐藏入口开关
  final bool onboardingDone; // 首启引导是否已看过
  final DateTime? semesterStart; // 自定义当前学期开学日（用于周数校准）
  final bool remindEnabled; // 上课提醒总开关
  final bool examRemindEnabled; // 考试提醒开关
  final int remindMinutes; // 上课提醒提前分钟数
  final int examRemindMinutes; // 考试提醒提前分钟数
  final List<SectionTime> sectionTimes; // 各节上课 / 下课时间

  // 自定义背景：ink=默认宣纸，其余为预设渐变；solid=纯色，image=图片
  final String backgroundStyle;
  final int backgroundSeed; // 纯色背景色值（ARGB）
  final String backgroundImage; // 本地图片绝对路径
  final double backgroundBlur; // 图片模糊 0~30

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.fontSizeScale = 1.0,
    this.locale = 'zh',
    this.showDebug = false,
    this.onboardingDone = false,
    this.semesterStart,
    this.remindEnabled = true,
    this.examRemindEnabled = true,
    this.remindMinutes = 10,
    this.examRemindMinutes = 30,
    this.sectionTimes = kDefaultSectionTimes,
    this.backgroundStyle = 'ink',
    this.backgroundSeed = 0xFFF7F9FA,
    this.backgroundImage = '',
    this.backgroundBlur = 0,
  });

  static const Object _unset = Object();

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? fontSizeScale,
    String? locale,
    bool? showDebug,
    bool? onboardingDone,
    Object? semesterStart = _unset,
    bool? remindEnabled,
    bool? examRemindEnabled,
    int? remindMinutes,
    int? examRemindMinutes,
    List<SectionTime>? sectionTimes,
    String? backgroundStyle,
    int? backgroundSeed,
    String? backgroundImage,
    double? backgroundBlur,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        fontSizeScale: fontSizeScale ?? this.fontSizeScale,
        locale: locale ?? this.locale,
        showDebug: showDebug ?? this.showDebug,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        semesterStart: identical(semesterStart, _unset)
            ? this.semesterStart
            : semesterStart as DateTime?,
        remindEnabled: remindEnabled ?? this.remindEnabled,
        examRemindEnabled: examRemindEnabled ?? this.examRemindEnabled,
        remindMinutes: remindMinutes ?? this.remindMinutes,
        examRemindMinutes: examRemindMinutes ?? this.examRemindMinutes,
        sectionTimes: sectionTimes ?? this.sectionTimes,
        backgroundStyle: backgroundStyle ?? this.backgroundStyle,
        backgroundSeed: backgroundSeed ?? this.backgroundSeed,
        backgroundImage: backgroundImage ?? this.backgroundImage,
        backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      );
}

class SettingsController extends Notifier<AppSettings> {
  static const _kMode = 'settings_theme_mode';
  static const _kFont = 'settings_font_scale';
  static const _kLocale = 'settings_locale';
  static const _kShowDebug = 'settings_show_select';
  static const _kSemStart = 'settings_sem_start';
  static const _kOnboarding = 'settings_onboarding_done';
  static const _kRemindOn = 'settings_remind_on';
  static const _kExamOn = 'settings_exam_on';
  static const _kRemindMin = 'settings_remind_min';
  static const _kExamMin = 'settings_exam_remind_min';
  static const _kSectionTimes = 'settings_section_times';
  static const _kBgStyle = 'settings_bg_style';
  static const _kBgSeed = 'settings_bg_seed';
  static const _kBgImage = 'settings_bg_image';
  static const _kBgBlur = 'settings_bg_blur';

  @override
  AppSettings build() {
    // 首次在异步前先用默认值，随后异步补齐
    return const AppSettings();
  }

  Future<void> _persist(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMode, switch (s.themeMode) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    });
    await p.setDouble(_kFont, s.fontSizeScale);
    await p.setString(_kLocale, s.locale);
    await p.setBool(_kShowDebug, s.showDebug);
    await p.setBool(_kOnboarding, s.onboardingDone);
    await p.setString(
        _kSemStart,
        s.semesterStart == null
            ? ''
            : s.semesterStart!.toIso8601String().split('T').first);
    await p.setBool(_kRemindOn, s.remindEnabled);
    await p.setBool(_kExamOn, s.examRemindEnabled);
    await p.setInt(_kRemindMin, s.remindMinutes);
    await p.setInt(_kExamMin, s.examRemindMinutes);
    await p.setString(_kSectionTimes, SectionTimes.encode(s.sectionTimes));
    await p.setString(_kBgStyle, s.backgroundStyle);
    await p.setInt(_kBgSeed, s.backgroundSeed);
    await p.setString(_kBgImage, s.backgroundImage);
    await p.setDouble(_kBgBlur, s.backgroundBlur);
  }

  /// 启动时从本地恢复设置（在 runApp 前调用）
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final mode = p.getString(_kMode) ?? 'system';
    final sem = p.getString(_kSemStart);
    final semesterStart = (sem == null || sem.isEmpty)
        ? null
        : DateTime.tryParse(sem);
    TermUtils.semesterStartOverride = semesterStart;
    final sectionTimes = SectionTimes.decode(p.getString(_kSectionTimes));
    SectionTimes.apply(sectionTimes);
    final s = AppSettings(
      themeMode: switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      fontSizeScale: p.getDouble(_kFont) ?? 1.0,
      locale: p.getString(_kLocale) ?? 'zh',
      showDebug: p.getBool(_kShowDebug) ?? false,
      onboardingDone: p.getBool(_kOnboarding) ?? false,
      semesterStart: semesterStart,
      remindEnabled: p.getBool(_kRemindOn) ?? true,
      examRemindEnabled: p.getBool(_kExamOn) ?? true,
      remindMinutes: p.getInt(_kRemindMin) ?? 10,
      examRemindMinutes: p.getInt(_kExamMin) ?? 30,
      sectionTimes: sectionTimes,
      backgroundStyle: p.getString(_kBgStyle) ?? 'ink',
      backgroundSeed: p.getInt(_kBgSeed) ?? 0xFFF7F9FA,
      // 旧版本可能存过在线链接，现已只支持本地图片，直接丢弃。
      backgroundImage: _localOnly(p.getString(_kBgImage) ?? ''),
      backgroundBlur: p.getDouble(_kBgBlur) ?? 0,
    );
    _syncNotifier(s);
    state = s;
  }

  Future<void> setThemeMode(ThemeMode m) async {
    state = state.copyWith(themeMode: m);
    AppLog.d('设置', '明暗模式改为 ${m.name}');
    await _persist(state);
  }

  Future<void> setFontSize(double v) async {
    state = state.copyWith(fontSizeScale: v);
    AppLog.d('设置', '字体缩放改为 ${v.toStringAsFixed(2)}×');
    await _persist(state);
  }

  /// 显示/隐藏「调试」入口（关于页连续点击版本号切换）
  Future<void> toggleDebugEntry() async {
    state = state.copyWith(showDebug: !state.showDebug);
    await _persist(state);
  }

  Future<void> setOnboardingDone() async {
    state = state.copyWith(onboardingDone: true);
    await _persist(state);
  }

  /// 自定义当前学期开学日（null = 清除，恢复系统估算）
  Future<void> setSemesterStart(DateTime? d) async {
    TermUtils.semesterStartOverride = d;
    state = state.copyWith(semesterStart: d);
    AppLog.d('设置', d == null ? '开学日恢复系统估算' : '开学日设为 $d');
    await _persist(state);
    // 周次映射变了，已排的上课提醒要按新周次重排
    await LessonNotifier.reschedule();
  }

  Future<void> setRemindEnabled(bool on) async {
    state = state.copyWith(remindEnabled: on);
    _syncNotifier(state);
    AppLog.d('提醒', '上课提醒${on ? '开启' : '关闭'}');
    await _persist(state);
    await LessonNotifier.reschedule();
  }

  Future<void> setExamRemindEnabled(bool on) async {
    state = state.copyWith(examRemindEnabled: on);
    _syncNotifier(state);
    AppLog.d('提醒', '考试提醒${on ? '开启' : '关闭'}');
    await _persist(state);
    await LessonNotifier.reschedule();
  }

  Future<void> setRemindMinutes(int m) async {
    state = state.copyWith(remindMinutes: m);
    _syncNotifier(state);
    AppLog.d('提醒', '上课提前 $m 分钟');
    await _persist(state);
    await LessonNotifier.reschedule();
  }

  Future<void> setExamRemindMinutes(int m) async {
    state = state.copyWith(examRemindMinutes: m);
    _syncNotifier(state);
    AppLog.d('提醒', '考试提前 $m 分钟');
    await _persist(state);
    await LessonNotifier.reschedule();
  }

  /// 用户自定义各节上课 / 下课时间
  Future<void> setSectionTimes(List<SectionTime> times) async {
    final list = [...times]..sort((a, b) => a.section.compareTo(b.section));
    SectionTimes.apply(list);
    state = state.copyWith(sectionTimes: List.unmodifiable(list));
    AppLog.d('设置', '课程时间已更新');
    await _persist(state);
    // 上课提醒按新时间重排，桌面小组件立即重绘
    await LessonNotifier.reschedule();
    await HomeWidgetSync.refresh();
  }

  /// 自定义背景（风格 / 纯色 / 图片 / 模糊 / 暗化）
  Future<void> setBackgroundStyle(String style) async {
    state = state.copyWith(backgroundStyle: style);
    AppLog.d('设置', '背景风格改为 $style');
    await _persist(state);
  }

  Future<void> setBackgroundSeed(int color) async {
    state = state.copyWith(backgroundSeed: color);
    AppLog.d('设置', '背景纯色改为 #${color.toRadixString(16)}');
    await _persist(state);
  }

  Future<void> setBackgroundImage(String path) async {
    state = state.copyWith(backgroundImage: path.trim());
    AppLog.d('设置', path.trim().isEmpty ? '清除背景图片' : '应用本地背景图片');
    await _persist(state);
  }

  Future<void> setBackgroundBlur(double v) async {
    state = state.copyWith(backgroundBlur: v.clamp(0, 30));
    AppLog.d('设置', '背景模糊 ${v.toStringAsFixed(0)}');
    await _persist(state);
  }

  /// 仅保留本地文件路径；http(s) 链接视为无效。
  static String _localOnly(String v) =>
      v.startsWith('http://') || v.startsWith('https://') ? '' : v;

  /// 把提醒配置同步到通知模块（排程时使用）
  void _syncNotifier(AppSettings s) {
    LessonNotifier.lessonEnabled = s.remindEnabled;
    LessonNotifier.examEnabled = s.examRemindEnabled;
    LessonNotifier.remindMinutes = s.remindMinutes;
    LessonNotifier.examRemindMinutes = s.examRemindMinutes;
  }
}

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);