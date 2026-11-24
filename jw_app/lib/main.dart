import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/jw_client.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'theme/ink_page_transition.dart';
import 'theme/ink_tokens.dart';
import 'ui/home/home_shell.dart';
import 'ui/login/login_page.dart';
import 'ui/onboarding/onboarding_page.dart';
import 'ui/widgets/ink_dialog.dart';
import 'ui/widgets/ink_panel.dart';
import 'ui/widgets/permission_prompt.dart';
import 'util/app_log.dart';
import 'util/campus_tunnel.dart';
import 'util/lesson_notifier.dart';
import 'util/server_config.dart';

void main() {
  // 将初始化和 runApp 放在同一个 zone 内，避免 Binding 初始化 zone 不一致告警
  runZonedGuarded(_bootstrap, (e, st) => AppLog.e('Zone', '$e\n$st'));
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 二级路由使用与全局一致的不透明背景，消除推入/返回时的页面残影。
  InkPageTransitionsBuilder.backdropBuilder = (_) =>
      const InkBackground(animate: false);
  final container = ProviderContainer();
  // 立即渲染首帧（先展示启动页），无需等待初始化
  runApp(UncontrolledProviderScope(container: container, child: const JwApp()));
  // 后台完成初始化（日志、通知权限、设置恢复），完成后各 Provider 自动重建生效
  unawaited(_warmup(container));
}

Future<void> _warmup(ProviderContainer container) async {
  final sw = Stopwatch()..start();
  // 移动数据下教务直连会失败：抓到连接错误就先启用校外通道再重试一次，
  // 覆盖「校内启动后切到移动数据」这类运行期切换。
  final client = container.read(jwClientProvider);
  final tunnel = container.read(campusTunnelProvider);
  client.onConnectionError = () async {
    var xh = '';
    try {
      final s = container.read(sessionProvider);
      xh = s.student.xh.trim().isNotEmpty
          ? s.student.xh.trim()
          : s.savedUsername.trim();
    } catch (_) {
      // 会话 Provider 仍在构建时忽略，交给启动期自适应处理
    }
    return tunnel.adapt(client, xh: xh);
  };
  await Future.wait([
    AppLog.init(),
    LessonNotifier.init(),
    container.read(settingsProvider.notifier).load(),
    ServerConfig.load(),
  ]);
  AppLog.d('启动', '基础初始化 ${sw.elapsedMilliseconds}ms');
  // 冷启动也按缓存课表重排一次，避免没打开课表页就漏掉提醒
  await LessonNotifier.scheduleFromCache();
}

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

class JwApp extends ConsumerStatefulWidget {
  const JwApp({super.key});

  @override
  ConsumerState<JwApp> createState() => _JwAppState();
}

class _JwAppState extends ConsumerState<JwApp> {
  static const _nav = MethodChannel('cn.gdou.xiuhong/nav');
  bool _guideOpen = false;
  // 首次启动权限引导只尝试一次
  bool _permPromptTried = false;

  @override
  void initState() {
    super.initState();
    // 原生桌面不支持一键固定小组件时，由 MainActivity 请求这里展示引导弹窗，
    // 保证弹窗视觉与 App 内保持一致。
    _nav.setMethodCallHandler(_onNavCall);
    // 首次启动且会话状态已确定时，弹出一次性权限授权引导
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(sessionProvider).status != SessionStatus.unknown) {
        _maybePromptPermissions();
      }
    });
  }

  /// 首次启动引导：通知 / 精确闹钟 / 电池优化（MIUI 含自启动）一次性授权。
  /// 跳过会记录已提示，之后可在「设置 → 权限与后台运行」重新授权。
  Future<void> _maybePromptPermissions() async {
    if (_permPromptTried) return;
    _permPromptTried = true;
    if (await permissionPrompted()) return;
    if (!mounted) return;
    final ctx = _navKey.currentState?.overlay?.context;
    if (ctx == null || !ctx.mounted) return;
    await showPermissionPrompt(ctx);
  }

  @override
  void dispose() {
    _nav.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onNavCall(MethodCall call) async {
    if (call.method != 'showWidgetGuide') return;
    final ctx = _navKey.currentContext;
    if (ctx == null) {
      // 首帧未就绪：抛错让原生侧稍后重试
      throw PlatformException(code: 'not_ready', message: 'UI not ready');
    }
    if (_guideOpen) return;
    _guideOpen = true;
    final goHome = await showInkGuideDialog(
      ctx,
      title: '添加「海畔」桌面小组件',
      message: '当前桌面不支持一键添加，请手动完成',
      steps: const [
        '回到桌面，长按空白处',
        '点「小组件」或「添加工具」',
        '找到「海畔」',
        '选「今日课表」（仅课表）或「课表 + 考试」拖到桌面',
      ],
      confirmText: '回到桌面',
    );
    _guideOpen = false;
    if (goHome) {
      try {
        await _nav.invokeMethod('moveToBack');
      } catch (_) {
        // 原生侧不可用时忽略，用户可自行返回桌面
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final settings = ref.watch(settingsProvider);

    // 会话状态确定后再弹首次权限引导，避免盖在启动页上
    ref.listen(sessionProvider, (prev, next) {
      if (next.status != SessionStatus.unknown) _maybePromptPermissions();
    });

    // 汇话失效提醒：收到信号后弹窗提示，引导去「我的」页重新登录
    ref.listen<int>(sessionExpiredSignalProvider, (prev, next) {
      if (next == 0 || next == prev) return;
      final nav = _navKey.currentState;
      if (nav == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final ctx = _navKey.currentContext;
        if (ctx == null) return;
        final renew = await showInkDialog(
          ctx,
          title: '登录已失效',
          message: '需要重新登录才能获取在线数据，账号密码已自动回填。',
          cancelText: '稍后',
          confirmText: '立即续期',
        );
        if (!renew) return;
        final nav = _navKey.currentState;
        if (nav != null) {
          nav.push(
            InkPageRoute(
              builder: (_) => const LoginPage(showGuestButton: false),
            ),
          );
        }
      });
      ref.read(sessionExpiredSignalProvider.notifier).state = 0;
    });

    return MaterialApp(
      title: '海畔',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      locale: Locale(settings.locale),
      supportedLocales: const [Locale('zh'), Locale('en')],
      // 中文本地化支持（缺少会导致 AppBar 报 No MaterialLocalizations found）
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // 全局字体缩放 + 宣纸底。
        // builder 里必须包一层 Material，否则 TextField 会出现双下划线。
        return Material(
          type: MaterialType.transparency,
          child: InkBackground(
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(settings.fontSizeScale)),
              child: child!,
            ),
          ),
        );
      },
      // 会话状态切换（启动页/登录/主页）平滑过渡
      home: AnimatedSwitcher(
        duration: InkMotion.normal,
        switchInCurve: InkMotion.standard,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: switch (session.status) {
          SessionStatus.unknown => const KeyedSubtree(
            key: ValueKey('splash'),
            child: _SplashPage(),
          ),
          // 游客或会话失效暂留 → 一直停留主页面；真正退出登录才回登录页
          SessionStatus.loggedOut =>
            session.browsing
                ? const KeyedSubtree(key: ValueKey('home'), child: HomeShell())
                : (settings.onboardingDone
                      ? const KeyedSubtree(
                          key: ValueKey('login'),
                          child: LoginPage(),
                        )
                      : const KeyedSubtree(
                          key: ValueKey('onboarding'),
                          child: OnboardingPage(),
                        )),
          SessionStatus.loggedIn => const KeyedSubtree(
            key: ValueKey('home'),
            child: HomeShell(),
          ),
        },
      ),
    );
  }
}

class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/app_icon.png',
                width: 76,
                height: 76,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: InkSpacing.xl),
            Text('海畔', style: context.tsTitle),
            const SizedBox(height: InkSpacing.xl),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
