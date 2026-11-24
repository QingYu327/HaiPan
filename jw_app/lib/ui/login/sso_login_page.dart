import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/jw_client.dart';
import '../../api/usage_api.dart';
import '../../providers/session_provider.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../../util/campus_tunnel.dart';
import '../../util/network_info.dart';
import '../../util/webview_proxy.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_notice.dart';

/// 新版统一身份认证登录：内嵌 WebView 打开学校认证页，
/// 登录成功回跳教务后读取 jw 域下的 JSESSIONID，注入 Dio 会话。
class SsoLoginPage extends ConsumerStatefulWidget {
  const SsoLoginPage({super.key});

  @override
  ConsumerState<SsoLoginPage> createState() => _SsoLoginPageState();
}

class _SsoLoginPageState extends ConsumerState<SsoLoginPage> {
  /// 教务侧的 SSO 入口，会 302 到 authserver 登录页
  static const _entry = 'https://jw.gdou.edu.cn/sso/jziotlogin';

  /// 统一认证原始登录页（校外经隧道访问）
  static const _authEntry =
      'https://authserver.gdou.edu.cn/authserver/login'
      '?service=https%3A%2F%2Fjw.gdou.edu.cn%2Fsso%2Fjziotlogin';

  static final _jwDomain = Uri.parse(JwClient.base);

  late final WebViewController _controller;
  Timer? _poll;
  Timer? _loadTimer;
  double _progress = 0;
  bool _submitting = false;
  bool _done = false;
  bool _tunnelTried = false;
  int _failures = 0;
  String? _error;

  /// 当前应加载的入口（校内直连 jw；校外经隧道打开 authserver）
  String _loadUrl = _entry;

  /// 最近一次主框架加载的 URL（仅用于日志定位）
  String _lastUrl = '';

  /// 日志用短 URL：只保留 host+path，丢掉可能含 ticket 的查询串
  static String _briefUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return '${u.host}${u.path}';
  }

  /// 首帧是否已正常渲染。未就绪时用遮罩盖住 WebView，
  /// 避免把 Chromium 的 ERR_TUNNEL_CONNECTION_FAILED 错误页给用户看到。
  bool _pageReady = false;

  /// 本次加载是否已经遇到主框架错误（错误页也会触发 onPageFinished）。
  bool _loadFailed = false;

  /// 隧道建立后的加载重试次数
  int _retryCount = 0;

  /// 遮罩上的分步进度
  List<String> _steps = const ['打开统一身份认证页'];
  int _step = 0;
  String _stageTitle = '正在打开统一身份认证…';
  String _stageHint = '首次连接可能需要几秒';

  /// 校园网直连提示（可关闭）
  bool _hintVisible = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p / 100;
              if (p >= 100 && !_loadFailed && _error == null) _pageReady = true;
            });
          },
          onPageStarted: (url) {
            _loadFailed = false;
            _lastUrl = url;
            AppLog.d('通道', '认证页开始加载：${_briefUrl(url)}');
            if (mounted) setState(() => _pageReady = false);
            _maybePoll(url);
          },
          onPageFinished: (url) {
            _loadTimer?.cancel();
            _maybePoll(url);
            _logPageTip();
            if (!mounted || _submitting) return;
            if (!_loadFailed && _error == null) {
              setState(() {
                _progress = 1;
                _pageReady = true;
              });
            }
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame != true || !mounted || _done) return;
            _loadFailed = true;
            if (mounted) setState(() => _pageReady = false);
            // 公网直连教务失败：自动切到校内隧道，而不是直接报错
            if (!_tunnelTried) {
              AppLog.w(
                '通道',
                '认证页直连失败，切换校园通道：${e.description} @${_briefUrl(_lastUrl)}',
              );
              _enableTunnel();
            } else {
              // 隧道已就绪仍失败：静默重试，重试仍失败才提示
              AppLog.w(
                '通道',
                '认证页加载失败：${e.description} @${_briefUrl(_lastUrl)}',
              );
              _retryAfterTunnel(e.description);
            }
          },
        ),
      );
    _prepare();
  }

  /// 直接打开认证入口，保留 WebView 里认证中心的长效 Cookie，
  /// 这样学校认证会话仍有效时可静默回跳，不必重新输账号密码。
  Future<void> _prepare() async {
    if (mounted) {
      setState(() {
        _error = null;
        _done = false;
        _failures = 0;
        _progress = 0;
        // 重试时允许再次判定是否需要走校外通道
        _tunnelTried = false;
        _pageReady = false;
        _loadFailed = false;
        _retryCount = 0;
        _steps = const ['打开统一身份认证页'];
        _step = 0;
        _stageTitle = '正在打开统一身份认证…';
        _stageHint = '首次连接可能需要几秒，请稍候';
        _loadUrl = _entry;
      });
    }
    _loadTimer?.cancel();
    // 移动数据下教务/认证网大概率不可直连，直接走校外通道省掉一次失败等待；
    // Wi-Fi/有线（可能是校园网）才先尝试直连。
    if (await NetworkInfo.isCellularOnly()) {
      AppLog.d('通道', '检测到移动数据，直接走校外通道');
      await _enableTunnel();
      return;
    }
    _loadTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _done || _progress >= 1 || _tunnelTried) return;
      // 页面长时间没有进展，按公网受限处理
      _enableTunnel();
    });
    await _controller.loadRequest(Uri.parse(_loadUrl));
  }

  /// 启用校外通道：本地 CONNECT 代理 + WebView 代理接管，
  /// 让认证页的请求经隧道回到校园网。
  Future<void> _enableTunnel() async {
    if (_tunnelTried) return;
    _tunnelTried = true;
    _loadTimer?.cancel();
    if (mounted) {
      setState(() {
        _error = null;
        _done = false;
        _progress = 0;
        _pageReady = false;
        _retryCount = 0;
        _steps = const ['验证设备身份', '建立校园隧道', '打开统一身份认证页'];
        _step = 0;
        _stageTitle = '正在验证设备身份…';
        _stageHint = '正在确认本机安全性，请稍候';
      });
    }
    final tunnel = ref.read(campusTunnelProvider);
    // 校外首次登录时本地还没有学号，先让用户补一次用于设备认证
    final session = ref.read(sessionProvider);
    final known = session.student.xh.trim().isNotEmpty
        ? session.student.xh.trim()
        : session.savedUsername.trim();
    var xhForAuth = known;
    if (known.isEmpty) {
      final xh = await _askXh();
      if (!mounted) return;
      if (xh == null) {
        _tunnelTried = false;
        setState(() {
          _error = '校外登录需要填写学号后才能建立通道';
          _steps = const ['打开统一身份认证页'];
          _step = 0;
        });
        return;
      }
      tunnel.setFallbackXh(xh);
      xhForAuth = xh;
    }
    try {
      // 先单独完成设备认证：遮罩里能明确展示"验证设备 → 建隧道"两步，
      // 认证成功后用灵动岛告知，用户不用对着转圈猜进度。
      if (xhForAuth.isNotEmpty) await UsageTracker.tokenFor(xhForAuth);
    } catch (e) {
      AppLog.e('通道', '学号验证失败：$e');
      if (mounted) {
        setState(() {
          _error = _deviceAuthError(e);
          _steps = const ['打开统一身份认证页'];
          _step = 0;
        });
      }
      return;
    }
    AppLog.d('通道', '设备认证完成，开始建立校园隧道');
    if (mounted) {
      setState(() {
        _step = 1;
        _stageTitle = '正在建立隧道连接到教务系统…';
        _stageHint = '校外访问需经校园通道中转，请稍候';
      });
    }
    try {
      final port = await tunnel.ensureStarted();
      await WebViewProxy.set(port);
      ref.read(jwClientProvider).setProxyPort(port);
      AppLog.d('通道', '认证页已切换到校外通道 :$port');
    } catch (e) {
      AppLog.e('通道', '校外通道启动失败：$e');
      if (mounted) {
        setState(() => _error = '校园通道连接失败，请检查网络后重试');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _step = 2;
      _stageTitle = '正在打开统一身份认证…';
      _stageHint = '通道已就绪，正在加载登录页';
      _loadUrl = _authEntry;
    });
    AppLog.d('通道', '加载认证页：${_briefUrl(_loadUrl)}');
    await _controller.loadRequest(Uri.parse(_loadUrl));
    _armTunnelTimeout();
  }

  /// 隧道加载超时兜底：静默重试，避免卡在遮罩上无限等待。
  void _armTunnelTimeout() {
    _loadTimer?.cancel();
    // 登录页经隧道打开，要拉几十个静态资源，首包往往要十几秒，
    // 这里放宽到 40 秒，避免页面还在加载就被判超时。
    _loadTimer = Timer(const Duration(seconds: 40), () {
      if (!mounted || _done || _pageReady || _error != null) return;
      _retryAfterTunnel('加载超时');
    });
  }

  /// 隧道已就绪但加载失败/超时时：自动重试两次，仍失败才提示。
  void _retryAfterTunnel(String reason) {
    _loadTimer?.cancel();
    if (_retryCount < 2) {
      _retryCount++;
      AppLog.w('通道', '认证页加载失败（$_retryCount/2），自动重试：$reason');
      if (mounted) {
        setState(() {
          _error = null;
          _pageReady = false;
          _loadFailed = false;
          _stageTitle = '连接不太稳定，正在重试…';
          _stageHint = '校园通道已就绪，正在重新打开认证页';
        });
      }
      _loadTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted || _done) return;
        _controller.loadRequest(Uri.parse(_loadUrl));
        _armTunnelTimeout();
      });
      return;
    }
    if (mounted) {
      setState(() => _error = '校园通道连接超时，请检查网络后重试');
    }
  }

  /// 设备认证失败：服务端明确拒绝（4xx）属于学号验证问题；
  /// 只有超时/断网等无响应错误才归为通道连接失败。
  String _deviceAuthError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final code = body is Map ? '${body['error'] ?? ''}' : '';
      if (code == 'device_mismatch' || status == 409) {
        return '学号验证失败：该学号已绑定其他设备，请联系管理员重置后重试';
      }
      if (code == 'not_allowed' || status == 403) {
        return '学号验证失败：该学号未加入白名单';
      }
      if (status != null) return '学号验证失败，请检查学号是否正确';
    }
    return '校园通道连接失败，请检查网络后重试';
  }

  /// 校外首次登录：问一次学号，仅用于隧道设备认证（服务端校验 APP 准入名单）。
  Future<String?> _askXh() async {
    final ctrl = TextEditingController();
    String? invalid;
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('填写学号'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('在校外使用统一身份认证需要建立校园通道，请先填写学号完成设备认证。'),
              const SizedBox(height: InkSpacing.m),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 20,
                decoration: InputDecoration(
                  labelText: '学号',
                  counterText: '',
                  errorText: invalid,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (!RegExp(r'^\d{6,20}$').hasMatch(v)) {
                  setLocal(() => invalid = '请输入 6-20 位数字学号');
                  return;
                }
                Navigator.of(ctx).pop(v);
              },
              child: const Text('使用通道'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return value;
  }

  /// 读取认证页的错误提示（账号/密码/验证码错误等），只写日志不改 UI
  Future<void> _logPageTip() async {
    try {
      final v = await _controller.runJavaScriptReturningResult(
        "(function(){var e=document.getElementById('formErrorTip2');"
        "return e&&e.innerText?e.innerText.trim():''})()",
      );
      var tip = v.toString().trim();
      // Android 端返回的是 JSON 字符串，会带一层引号
      if (tip.length >= 2 && tip.startsWith('"') && tip.endsWith('"')) {
        tip = tip.substring(1, tip.length - 1);
      }
      if (tip.isNotEmpty) AppLog.w('通道', '认证页提示：$tip');
    } catch (_) {
      // 页面没有该节点或脚本被禁用时忽略
    }
  }

  void _maybePoll(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // 回到教务域名后开始轮询；跳过 /sso/ 中转页，
    // 避免读到上一轮残留的 JSESSIONID 造成误判。
    if (uri.host == _jwDomain.host && !uri.path.startsWith('/sso/')) {
      _startPoll();
    }
  }

  void _startPoll() {
    if (_poll != null || _done) return;
    _poll = Timer.periodic(const Duration(milliseconds: 700), (_) => _tryRead());
    // 立刻试一次，避免回跳后等待首个周期
    _tryRead();
  }

  Future<void> _tryRead() async {
    if (_done || _submitting) return;
    List<WebViewCookie> cookies;
    try {
      cookies = await WebViewCookieManager().getCookies(domain: _jwDomain);
    } catch (_) {
      return;
    }
    final map = <String, String>{
      for (final c in cookies) c.name: c.value,
    };
    if (!map.containsKey('JSESSIONID')) return;

    _done = true;
    _poll?.cancel();
    _poll = null;
    if (!mounted) return;
    setState(() {
      _submitting = true;
      _pageReady = false;
      _steps = const ['打开统一身份认证页', '同步登录状态'];
      _step = 1;
      _stageTitle = '认证成功，正在同步登录状态…';
      _stageHint = '正在读取课表与学籍信息';
    });
    try {
      await ref.read(sessionProvider.notifier).loginWithSso(map);
      if (!mounted) return;
      // 认证成功的及时反馈：灵动岛通知，回首页后数据在后台继续同步
      showInkNotice(
        context,
        '课表、成绩与考试数据正在后台同步',
        title: '认证成功',
        tone: InkTone.success,
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      // 回跳瞬间可能先读到旧 Cookie；允许短暂重试，连续失败再提示
      _failures++;
      if (_failures >= 3) {
        _poll?.cancel();
        _poll = null;
        setState(() {
          _submitting = false;
          _done = false;
          _pageReady = true;
          _steps = const ['打开统一身份认证页'];
          _step = 0;
          _error = '统一身份认证未生效，请重新登录一次';
        });
        return;
      }
      setState(() {
        _submitting = false;
        _done = false;
        _pageReady = true;
        _steps = const ['打开统一身份认证页'];
        _step = 0;
      });
      _startPoll();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _loadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                InkSpacing.s,
                InkSpacing.s,
                InkSpacing.l,
                InkSpacing.s,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    icon: const Icon(AppIcons.back, size: 20),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: InkSpacing.xs),
                  Expanded(
                    child: Text('统一身份认证', style: context.tsSection),
                  ),
                  if (_submitting)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            if (_progress < 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: InkSpacing.l),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(InkRadius.pill),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                    minHeight: 2,
                    color: scheme.primary,
                    backgroundColor: context.ink.hairline,
                  ),
                ),
              ),
            if (_hintVisible)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  InkSpacing.l,
                  0,
                  InkSpacing.s,
                  InkSpacing.s,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(InkRadius.control),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          AppIcons.info,
                          size: 15,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '校园网直连体验更佳，公网通道延迟较高。建议先在校园网内完成一次数据同步，之后校外使用会更快。',
                          style: context.tsCaption,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭提示',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: const Icon(AppIcons.close, size: 14),
                        onPressed: () => setState(() => _hintVisible = false),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  // 首帧就绪前盖住 WebView：既遮住 Chromium 自带的
                  // ERR_TUNNEL_CONNECTION_FAILED 错误页，也避免白屏干等。
                  if (!_pageReady)
                    Positioned.fill(
                      child: _StageCover(
                        title: _stageTitle,
                        hint: _stageHint,
                        steps: _steps,
                        activeStep: _step,
                      ),
                    ),
                  if (_error != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: scheme.surface,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(InkSpacing.xxl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(AppIcons.cloudOff,
                                    size: 40,
                                    color: context.ink.danger),
                                const SizedBox(height: InkSpacing.m),
                                Text(
                                  '认证页加载失败',
                                  style: context.tsBodyStrong,
                                ),
                                const SizedBox(height: InkSpacing.xs),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: context.tsCaption,
                                ),
                                const SizedBox(height: InkSpacing.l),
                                FilledButton(
                                  onPressed: () {
                                    setState(() => _error = null);
                                    _prepare();
                                  },
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 登录过程遮罩：呼吸光环 + 分步进度 + 提示语。
class _StageCover extends StatefulWidget {
  const _StageCover({
    required this.title,
    required this.hint,
    required this.steps,
    required this.activeStep,
  });

  final String title;
  final String hint;
  final List<String> steps;
  final int activeStep;

  @override
  State<_StageCover> createState() => _StageCoverState();
}

class _StageCoverState extends State<_StageCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = context.ink;
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(InkSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    FadeTransition(
                      opacity: Tween<double>(begin: 0.10, end: 0.24).animate(
                        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
                      ),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        AppIcons.lock,
                        size: 24,
                        color: scheme.primary,
                      ),
                    ),
                    SizedBox(
                      width: 66,
                      height: 66,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: InkSpacing.l),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: context.tsBodyStrong,
              ),
              const SizedBox(height: InkSpacing.xs),
              Text(
                widget.hint,
                textAlign: TextAlign.center,
                style: context.tsCaption,
              ),
              if (widget.steps.length > 1) ...[
                const SizedBox(height: InkSpacing.xl),
                for (var i = 0; i < widget.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i < widget.activeStep)
                          Icon(
                            AppIcons.success,
                            size: 16,
                            color: scheme.primary,
                          )
                        else if (i == widget.activeStep)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          )
                        else
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: ink.hairline),
                            ),
                          ),
                        const SizedBox(width: InkSpacing.s),
                        Text(
                          widget.steps[i],
                          style: context.tsCaption.copyWith(
                            color: i <= widget.activeStep
                                ? scheme.onSurface
                                : ink.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
