import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/update_api.dart';
import '../../api/usage_api.dart';
import '../../providers/data_providers.dart';
import '../../providers/session_provider.dart';
import '../../theme/ink_page_transition.dart';
import '../../util/app_log.dart';
import '../../util/notify_target.dart';
import '../../theme/ink_tokens.dart';
import '../academic/academic_page.dart';
import '../exam/exam_page.dart';
import '../grade/grade_page.dart';
import '../profile/profile_page.dart';
import '../profile/update_page.dart';
import '../timetable/timetable_page.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_dialog.dart';
import '../widgets/ink_page.dart';
import '../widgets/ink_shell.dart';
import 'access_denied_page.dart';

/// 主壳：水墨悬浮胶囊导航 + 5 个页面（含云端准入校验）。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  final _shellKey = GlobalKey<InkAppShellState>();

  static const List<Widget> _pages = [
    TimetablePage(),
    GradePage(),
    ExamPage(),
    AcademicPage(),
    ProfilePage(),
  ];

  // 通知点击跳转：从原生读取目标 tab 与课程/考试标识
  static const _navCh = MethodChannel('cn.gdou.xiuhong/nav');
  int? _pendingPage;

  Timer? _importTimer;
  bool _importBusy = false;
  bool _importOpen = false;
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPage();
      _checkUpdateOnLaunch();
    });
  }

  @override
  void dispose() {
    _importTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncPage();
  }

  /// 读取通知点击带来的目标：切到对应 tab，并记录课程/考试标识供页面直达详情
  Future<void> _syncPage() async {
    try {
      final raw = await _navCh.invokeMethod<Map>('getLaunchTarget');
      if (!mounted) return;
      if (raw != null) {
        final target = NotifyTarget.fromMap(raw);
        AppLog.w('提醒诊断', '通知点击 → ${target.logText}');
        ref.read(notifyTargetProvider.notifier).state = target;
        _pendingPage = target.page;
        _tryGo();
        return;
      }
      // 兼容仅带 page 的旧通知
      final page = await _navCh.invokeMethod<int>('getLaunchPage') ?? -1;
      if (page < 0 || page > 4 || !mounted) return;
      _pendingPage = page;
      _tryGo();
    } catch (_) {
      // 原生方法不可用时忽略
    }
  }

  /// shell 尚未构建（准入校验中/启动页）时保留目标，构建完成后补跳
  void _tryGo() {
    final page = _pendingPage;
    if (page == null) return;
    final state = _shellKey.currentState;
    if (state == null) return;
    state.goTo(page);
    _pendingPage = null;
  }

  @override
  Widget build(BuildContext context) {
    // APP 准入：默认禁止，管理员开通后可用；未登录/游客不拦截。
    final access = ref.watch(appAccessProvider);
    final session = ref.watch(sessionProvider);
    final timetable = ref.watch(timetableProvider);
    // 常驻同步桌面小组件（今日课表 + 考试倒计时）
    ref.watch(homeWidgetSyncProvider);
    // 登录后首屏导入：权限校验与课表拉取期间弹出步骤明确的进度，避免只剩角落转圈
    final importing = session.status == SessionStatus.loggedIn &&
        (access.isLoading ||
            (timetable.isLoading && timetable.valueOrNull == null));
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncImport(importing));
    return access.when(
      loading: () => const AccessChecking(),
      error: (_, _) => const AccessDeniedPage(),
      data: (allowed) => allowed
          ? _buildShell()
          : const AccessDeniedPage(),
    );
  }

  /// 启动后静默检查更新：等首屏导入结束再问，避免和进度弹窗抢同一层。
  Future<void> _checkUpdateOnLaunch() async {
    if (_updateChecked) return;
    _updateChecked = true;
    await Future<void>.delayed(const Duration(seconds: 2));
    // 首屏导入（含登录态拉课表）期间先让路，最多等 10 秒
    for (var i = 0; i < 20 && _importBusy; i++) {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return;
    try {
      final gates = await ref.read(featureGatesProvider.future);
      if (gates[UsageTracker.gateUpdateBlock] == true) return;
    } catch (_) {
      // 门控查询失败不影响检查
    }
    try {
      final r = await ref.read(updateApiProvider).checkLatest();
      if (!mounted || r.$1.isEmpty || r.$4.isEmpty) return;
      AppLog.d('更新', '启动检测到新版本 v${r.$1}');
      final go = await showInkDialog(
        context,
        title: '发现新版本 v${r.$1}',
        message: '修复问题并改进使用体验，是否前往更新？',
        cancelText: '稍后',
        confirmText: '去更新',
      );
      if (!go || !mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        InkPageRoute(builder: (_) => const UpdatePage()),
      );
    } catch (e) {
      AppLog.d('更新', '启动检查更新跳过：$e');
    }
  }

  /// 导入进度弹窗：延迟 400ms 再弹出，避免缓存命中时一闪而过。
  void _syncImport(bool busy) {
    if (busy == _importBusy) return;
    _importBusy = busy;
    if (busy) {
      _importTimer ??= Timer(const Duration(milliseconds: 400), () {
        _importTimer = null;
        if (!mounted || !_importBusy || _importOpen) return;
        _importOpen = true;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (_) => const _ImportDialog(),
        ).whenComplete(() => _importOpen = false);
      });
    } else {
      _importTimer?.cancel();
      _importTimer = null;
      if (_importOpen) {
        _importOpen = false;
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      }
    }
  }

  Widget _buildShell() {
    // 准入校验/启动页期间收到通知跳转时，shell 就绪后补跳目标 tab
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryGo());
    return InkAppShell(
      key: _shellKey,
      items: const [
        InkNavItem(
          label: '课表',
          icon: AppIcons.timetable,
          selectedIcon: AppIcons.timetableActive,
        ),
        InkNavItem(
          label: '成绩',
          icon: AppIcons.grade,
          selectedIcon: AppIcons.gradeActive,
        ),
        InkNavItem(
          label: '考试',
          icon: AppIcons.exam,
          selectedIcon: AppIcons.examActive,
        ),
        InkNavItem(
          label: '学业',
          icon: AppIcons.academic,
          selectedIcon: AppIcons.academicActive,
        ),
        InkNavItem(
          label: '我的',
          icon: AppIcons.profile,
          selectedIcon: AppIcons.profileActive,
        ),
      ],
      pages: _pages,
    );
  }
}

/// 登录后首屏导入进度：把"权限校验 → 课表 → 其他数据"显式列出来，
/// 完成时由 HomeShell 自动关闭，不阻断操作。
class _ImportDialog extends ConsumerWidget {
  const _ImportDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(appAccessProvider);
    final timetable = ref.watch(timetableProvider);
    final accessDone = access.hasValue || access.hasError;
    final timetableDone = timetable.hasValue || timetable.hasError;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: InkCard(
        padding: const EdgeInsets.all(InkSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('正在导入数据', style: context.tsTitle),
            const SizedBox(height: InkSpacing.xs),
            Text(
              '首次登录或切换账号后需要同步几项数据，完成后自动进入。',
              style: context.tsSecondary,
            ),
            const SizedBox(height: InkSpacing.l),
            _step(context, '校验访问权限', accessDone ? 1 : 0),
            const SizedBox(height: InkSpacing.s),
            _step(
              context,
              '导入课表与学期信息',
              timetableDone ? 1 : (accessDone ? 0 : -1),
            ),
            const SizedBox(height: InkSpacing.s),
            _step(context, '准备成绩与考试数据', -1),
          ],
        ),
      ),
    );
  }

  /// state：-1 等待、0 进行中、1 完成
  Widget _step(BuildContext context, String text, int state) {
    final Widget leading;
    if (state == 1) {
      leading = Icon(Icons.check_circle, size: 18, color: context.ink.success);
    } else if (state == 0) {
      leading = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      leading = Icon(
        Icons.radio_button_unchecked,
        size: 18,
        color: context.ink.secondaryLabel,
      );
    }
    return Row(
      children: [
        SizedBox(width: 18, height: 18, child: Center(child: leading)),
        const SizedBox(width: InkSpacing.s),
        Text(
          text,
          style: state == -1 ? context.tsSecondary : context.tsBody,
        ),
      ],
    );
  }
}
