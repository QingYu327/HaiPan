import 'dart:async';
import 'dart:convert';

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
  const SsoLoginPage({super.key, this.wfw = false});

  /// true = 走学校官方 WebVPN（wfw）通道，校外免自建隧道。
  final bool wfw;

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

  /// 官方 WebVPN 通道的第一段：CAS 登录后把票据交给 wfw 根，建立 WFWSESSID。
  /// 注意 service 必须是 wfw 根（不是教务 sso），否则票据回跳会落在校外不可达的
  /// 裸 jw 域上。
  String get _wfwEntry =>
      'https://authserver.gdou.edu.cn/authserver/login'
      '?service=https%3A%2F%2Fwfw.gdou.edu.cn%2F';

  /// 官方通道第二段：让网关渲染**经 wfw 代理的认证页**并建立教务子会话。
  /// 该页表单 action 是相对的 `/authserver/login`，浏览器提交时正好落在
  /// `wfw.gdou.edu.cn/authserver/...`，`Path=/authserver` 的会话 Cookie 才生效。
  static const _wfwJwEntry = 'https://wfw.gdou.edu.cn/https://jw.gdou.edu.cn';

  /// 官方通道入口：直接从教务入口进网关。
  /// 实测该页下发的 service 是 `wfw/https://jw.gdou.edu.cn/sso/jziotlogin`，
  /// 登录票据回跳后仍留在网关内，不再跳出到 jw 绝对地址。
  static final _jwDomain = Uri.parse(JwClient.base);
  static final _wfwOrigin = Uri.parse('${JwClient.wfwBase}/');

  /// 官方通道下，登录成功回到微门户首页后自动再进一次教务入口
  /// （wfw 需要借此建立教务子会话），只尝试一次。
  bool _wfwReentered = false;

  /// 官方通道二次登录页（wfw 已登录后教务又要求认证）只自动填一次
  bool _wfwAutoFilled = false;

  /// WebView 里用户输入过的账号密码（仅内存，用于官方通道二次登录自动填充）
  String _savedUser = '';
  String _savedPwd = '';

  String get _startEntry => widget.wfw ? _wfwEntry : _entry;

  late final WebViewController _controller;
  Timer? _poll;
  Timer? _loadTimer;
  double _progress = 0;
  bool _submitting = false;
  bool _done = false;

  /// 页面已销毁：WebView 回调、轮询与定时器可能在退出转场期间才回来，
  /// 统一用这个标记让它们立即退出，避免 setState / 读控制器时踩到已销毁状态。
  bool _disposed = false;
  bool _tunnelTried = false;
  int _failures = 0;
  String? _error;

  /// 当前应加载的入口（校内直连 jw；校外经隧道打开 authserver）
  String _loadUrl = '';

  /// 最近一次主框架加载的 URL（仅用于日志定位）
  String _lastUrl = '';

  /// 日志用短 URL：只保留 host+path，丢掉可能含 ticket 的查询串
  static String _briefUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return '${u.host}${u.path}';
  }

  /// 是否为「登录成功后跳回教务」的页面：带 ticket 的 /sso/ 入口或教务内页。
  /// 首次进入的 /sso/jziotlogin（无 ticket）不算，否则一进来就提示“登录成功”。
  bool _isPostLoginJw(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (widget.wfw) {
      // 登录成功后回跳的是网关内的教务地址，两种形态都要认：
      // 1) 前缀式回跳 /https://jw.gdou.edu.cn/sso/jziotlogin?ticket=...
      // 2) 原路径直通 /xtgl/index_initMenu.html
      if (uri.host != JwClient.wfwHost || url.contains('authserver')) {
        return false;
      }
      final path = uri.path;
      if (path.contains('/https://jw.gdou.edu.cn')) {
        if (path.contains('/sso/')) {
          return uri.queryParameters.containsKey('ticket');
        }
        return true;
      }
      // 入口页 dl_loginForward.html 也是 /xtgl/ 路径，含 login 的一律不算
      if (path.toLowerCase().contains('login')) return false;
      return path.startsWith('/xtgl/') || path.startsWith('/kbcx/');
    }
    if (uri.host != _jwDomain.host) return false;
    if (uri.path.startsWith('/sso/')) {
      return uri.queryParameters.containsKey('ticket');
    }
    return true;
  }

  /// 跳回教务后保持加载遮罩，直到登录态同步完成（或超时兜底）。
  void _holdCoverForJw() {
    _enterTimer?.cancel();
    if (mounted) {
      setState(() {
        _enteringJw = true;
        _pageReady = false;
        _steps = const ['打开统一身份认证页', '进入教务系统'];
        _step = 1;
        _stageTitle = '登录成功，正在进入教务系统…';
        _stageHint = '教务页面加载需要几秒，请稍候';
      });
    }
    AppLog.d('通道', '已跳回教务系统，加载完成前保持遮罩');
    // 兜底：页面长时间不响应时先放开遮罩，不让用户一直被盖住
    _enterTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted || _done) return;
      AppLog.w('通道', '教务页面等待超时，先展示页面');
      setState(() {
        _enteringJw = false;
        _pageReady = true;
      });
    });
  }

  /// 首帧是否已正常渲染。未就绪时用遮罩盖住 WebView，
  /// 避免把 Chromium 的 ERR_TUNNEL_CONNECTION_FAILED 错误页给用户看到。
  bool _pageReady = false;

  /// 本次加载是否已经遇到主框架错误（错误页也会触发 onPageFinished）。
  bool _loadFailed = false;

  /// 隧道建立后的加载重试次数
  int _retryCount = 0;

  /// 登录后已按票据跳回教务、但教务页面仍在加载：遮罩继续保持，
  /// 避免用户对着空白 WebView 干等。
  bool _enteringJw = false;
  Timer? _enterTimer;

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
      // 登录页输入内容回传到 Dart：wfw 二次认证页面是新文档，JS 变量不跨页面
      ..addJavaScriptChannel(
        'HpCred',
        onMessageReceived: (msg) {
          if (_disposed) return;
          final s = msg.message;
          if (s.startsWith('u:')) {
            _savedUser = s.substring(2);
          } else if (s.startsWith('p:')) {
            _savedPwd = s.substring(2);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (!mounted) return;
            setState(() {
              _progress = p / 100;
              // 进入教务后进度条到 100 也不收遮罩，等登录态同步完成再收
              if (p >= 100 &&
                  !_loadFailed &&
                  _error == null &&
                  !_enteringJw) {
                _pageReady = true;
              }
            });
          },
          onPageStarted: (url) {
            _loadFailed = false;
            _lastUrl = url;
            AppLog.d('通道', '认证页开始加载：${_briefUrl(url)}');
            if (mounted) setState(() => _pageReady = false);
            // 登录成功跳回教务：保持遮罩直到教务页加载完并同步登录态
            if (!_done && _isPostLoginJw(url)) _holdCoverForJw();
            _maybePoll(url);
          },
          onPageFinished: (url) {
            _loadTimer?.cancel();
            _maybePoll(url, loaded: true);
            _logPageTip();
            if (widget.wfw) {
              // 官方通道：记录页面状态，识别登录页 / 多因子 / 教务页
              unawaited(_inspectWfwPage(url));
            } else {
              unawaited(_maybeReenterJw(url));
            }
            if (!mounted || _submitting) return;
            if (!_loadFailed && _error == null && !_enteringJw) {
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
            if (widget.wfw) {
              // 官方通道没有隧道可切，直接静默重试
              _retryAfterTunnel(e.description);
              return;
            }
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
    if (_disposed) return;
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
        _enteringJw = false;
        _wfwReentered = false;
        _wfwAutoFilled = false;
        _steps = const ['打开统一身份认证页'];
        _step = 0;
        _stageTitle = '正在打开统一身份认证…';
        _stageHint = widget.wfw
            ? '官方 WebVPN 通道，校外可直接访问'
            : '首次连接可能需要几秒，请稍候';
        _loadUrl = _startEntry;
      });
    }
    _loadTimer?.cancel();
    _enterTimer?.cancel();
    if (widget.wfw) {
      // 官方通道本身就是校外访问入口，不需要自建隧道
      await _controller.loadRequest(Uri.parse(_loadUrl));
      return;
    }
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
    if (_disposed) return;
    if (widget.wfw) return; // 官方通道无需隧道
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
      setState(() => _error = widget.wfw
          ? '官方通道连接失败，请检查网络后重试'
          : '校园通道连接超时，请检查网络后重试');
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
  ///
  /// 输入框放在独立 StatefulWidget 里，由它自己释放控制器：
  /// 对话框 pop 后仍有约 120ms 退场动画，若在这里立刻 dispose，
  /// 退场中的 TextField 会用到已释放的 TextEditingController 而抛框架异常。
  Future<String?> _askXh() {
    return showDialog<String>(
      context: context,
      builder: (_) => const _XhDialog(),
    );
  }

  /// 读取认证页的错误提示（账号/密码/验证码错误等），只写日志不改 UI
  Future<void> _logPageTip() async {
    if (_disposed) return;
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

  void _maybePoll(String url, {bool loaded = false}) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (widget.wfw) {
      // 只有真正落到网关内的教务页面才轮询登录态，网关首页不算
      if (!loaded) return;
      if (_isPostLoginJw(url)) {
        unawaited(_pollWhenReady());
      }
      return;
    }
    // 回到教务域名后开始轮询；跳过 /sso/ 中转页，
    // 避免读到上一轮残留的 JSESSIONID 造成误判。
    if (uri.host == _jwDomain.host && !uri.path.startsWith('/sso/')) {
      _startPoll();
    }
  }

  /// 官方通道下 wfw 会把认证页直接渲染在教务路径上，
  /// 只有页面里已经没有登录表单时，才说明真正进入了教务。
  Future<void> _pollWhenReady() async {
    if (!mounted || _poll != null || _done || _submitting) return;
    bool hasForm;
    try {
      final v = await _controller.runJavaScriptReturningResult(
        "(function(){var p=document.querySelector('input[type=password]');"
        "var s=document.getElementById('pwdEncryptSalt');"
        "return (p||s)?1:0})()",
      );
      hasForm = v.toString().contains('1');
    } catch (_) {
      return;
    }
    if (hasForm) {
      // wfw 已登录但教务子会话要求再认证一次：用上一步记下的账号密码自动提交
      await _maybeAutoFillSubAuth();
      return;
    }
    if (!mounted || _done || _poll != null) return;
    _startPoll();
  }

  /// 官方通道页面诊断 + 记录账号密码（仅内存，用于二次登录自动填充）
  Future<void> _inspectWfwPage(String url) async {
    if (_disposed) return;
    try {
      await _controller.runJavaScript(
        "(function(){if(window.__hpHook)return;window.__hpHook=1;"
        "document.addEventListener('input',function(e){var t=e.target;"
        "if(!t||!t.name)return;"
        "if(t.type==='password'){window.__hpPwd=t.value;"
        "try{HpCred.postMessage('p:'+t.value)}catch(_){}}"
        "else if(t.name==='username'){window.__hpUser=t.value;"
        "try{HpCred.postMessage('u:'+t.value)}catch(_){}}},true);})()",
      );
    } catch (_) {}
    String flags = '-';
    try {
      final v = await _controller.runJavaScriptReturningResult(
        "(function(){var b=(document.body&&document.body.innerHTML)||'';"
        "return (document.querySelector('input[type=password]')?1:0)+'|'+"
        "(b.indexOf('reAuthParams')>=0?1:0)+'|'+"
        "((b.indexOf('index_initMenu')>=0||b.indexOf('教学管理信息服务平台')>=0)?1:0)+"
        "'|'+(document.title||'')})()",
      );
      flags = v.toString();
      if (flags.length >= 2 && flags.startsWith('"') && flags.endsWith('"')) {
        flags = flags.substring(1, flags.length - 1);
      }
    } catch (_) {}
    AppLog.d('通道', '官方通道页面：${_briefUrl(url)} 密码框|多因子|教务=$flags');
    if (flags.startsWith('1|')) {
      await _maybeAutoFillSubAuth();
      return;
    }
    // 已经在教务页（教学管理信息服务平台）就不用再进一次入口
    final parts = flags.split('|');
    if (parts.length > 2 && parts[2] == '1') return;
    await _maybeReenterJw(url);
  }

  /// 官方通道二次登录：wfw 会话已建立，但教务子会话仍要再认证一次，
  /// 用第一步记录的账号密码自动填表提交，避免用户重复输入。
  Future<void> _maybeAutoFillSubAuth() async {
    if (_disposed) return;
    if (!widget.wfw || _wfwAutoFilled) return;
    if (_savedUser.isEmpty || _savedPwd.isEmpty) return;
    bool filled = false;
    final user = jsonEncode(_savedUser);
    final pwd = jsonEncode(_savedPwd);
    try {
      final v = await _controller.runJavaScriptReturningResult(
        "(function(){"
        "if(document.querySelector('#reAuthUserId'))return 0;"
        "var u=document.querySelector('input[name=username]');"
        "var p=document.querySelector('input[name=password]');"
        "if(!u||!p)return 0;"
        "u.value=$user;p.value=$pwd;"
        "u.dispatchEvent(new Event('input',{bubbles:true}));"
        "p.dispatchEvent(new Event('input',{bubbles:true}));"
        "var b=document.querySelector('#login_submit')||"
        "document.querySelector('.login_btn')||"
        "document.querySelector('input[type=submit]')||"
        "document.querySelector('button[type=submit]');"
        "if(!b)return 0;b.click();return 1})()",
      );
      filled = v.toString().contains('1');
    } catch (_) {}
    if (!filled) return;
    _wfwAutoFilled = true;
    AppLog.d('通道', '官方通道教务子会话：已自动填入账号密码并提交');
  }

  /// 官方通道登录完成后通常回到 wfw 首页，此时再加载一次教务入口，
  /// 让 wfw 生成教务子会话；否则 Dio 侧探针仍会被判为未登录。
  Future<void> _maybeReenterJw(String url) async {
    if (!widget.wfw || _wfwReentered || _done) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != JwClient.wfwHost) return;
    // 只有停在网关首页（登录完成后常见的落点）才补进一次教务入口；
    // 其它页面（登录页、教务页）一律不动，避免把正在用的页面顶掉。
    if (uri.path != '/' && uri.path.isNotEmpty) return;
    if (!mounted || _wfwReentered || _done) return;
    _wfwReentered = true;
    AppLog.d('通道', '官方通道第一段已完成，进入教务入口建立子会话');
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted || _done) return;
      _controller.loadRequest(Uri.parse(_wfwJwEntry));
    });
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
      cookies = await WebViewCookieManager()
          .getCookies(domain: widget.wfw ? _wfwOrigin : _jwDomain);
    } catch (_) {
      return;
    }
    final map = <String, String>{
      for (final c in cookies) c.name: c.value,
    };
    final ready = widget.wfw
        ? map.isNotEmpty &&
            (_enteringJw || _isPostLoginJw(_lastUrl))
        : map.containsKey('JSESSIONID');
    if (!ready) return;

    _done = true;
    _poll?.cancel();
    _poll = null;
    _enterTimer?.cancel();
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
      if (widget.wfw) {
        await ref.read(sessionProvider.notifier).loginWithWfw(map);
      } else {
        await ref.read(sessionProvider.notifier).loginWithSso(map);
      }
      if (!mounted) return;
      // 认证成功的及时反馈：灵动岛通知，回首页后数据在后台继续同步
      showInkNotice(
        context,
        '课表、成绩与考试数据正在后台同步',
        title: widget.wfw ? '官方通道认证成功' : '认证成功',
        tone: InkTone.success,
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      // 回跳瞬间可能先读到旧 Cookie；允许短暂重试，连续失败再提示
      _failures++;
      // 已进入教务、遮罩还盖着：多给几次机会，避免把白屏提前放出来
      if (_enteringJw) {
        if (_failures >= 10) {
          AppLog.w('通道', '教务页面已加载，但登录态同步失败（$_failures 次）');
          _poll?.cancel();
          _poll = null;
          setState(() {
            _submitting = false;
            _done = false;
            _enteringJw = false;
            _pageReady = true;
            _steps = const ['打开统一身份认证页'];
            _step = 0;
          });
        } else {
          setState(() => _submitting = false);
        }
        return;
      }
      // 官方通道建立教务子会话需要几秒，多给几次机会
      if (_failures >= (widget.wfw ? 8 : 3)) {
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
    _disposed = true;
    // 让仍在飞的异步流程（登录同步、轮询）看到 done 后立刻返回
    _done = true;
    _poll?.cancel();
    _loadTimer?.cancel();
    _enterTimer?.cancel();
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

/// 统一的「填写学号」弹窗：原生登录页与认证网页共用。
Future<String?> askStudentId(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _XhDialog(),
  );
}

/// 校外首次进隧道时补填学号。
/// 控制器由本组件持有并在自身 dispose 里释放，避免对话框退场动画期间
/// 仍在使用已被页面提前销毁的 TextEditingController。
class _XhDialog extends StatefulWidget {
  const _XhDialog();

  @override
  State<_XhDialog> createState() => _XhDialogState();
}

class _XhDialogState extends State<_XhDialog> {
  final _ctrl = TextEditingController();
  String? _invalid;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (!RegExp(r'^\d{6,20}$').hasMatch(v)) {
      setState(() => _invalid = '请输入 6-20 位数字学号');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('填写学号'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('在校外使用统一身份认证需要建立校园通道，请先填写学号完成设备认证。'),
          const SizedBox(height: InkSpacing.m),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 20,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: '学号',
              counterText: '',
              errorText: _invalid,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('使用通道'),
        ),
      ],
    );
  }
}
