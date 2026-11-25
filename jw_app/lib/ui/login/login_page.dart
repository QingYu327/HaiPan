import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/auth_api.dart';
import '../../api/cas_auth.dart';
import '../../api/jw_client.dart';
import '../../api/usage_api.dart';
import '../../providers/session_provider.dart';
import '../../theme/ink_page_transition.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../../util/campus_tunnel.dart';
import '../../util/webview_proxy.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';
import 'sso_login_page.dart';

/// 登录页：自建原生表单直连学校统一身份认证接口，不再先渲染网页。
/// 认证失败或需要特殊验证方式时，可退回内嵌网页登录。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.showGuestButton = true});

  /// 从页面内「去登录」进入时不再显示游客按钮。
  final bool showGuestButton;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  /// 入场动画压到 200ms：登录页是用户最急着操作的界面，先给可点击的稳定画面，
  /// 再用极轻的上浮淡入补一点质感，不做慢速铺陈。
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..forward();

  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _mfaCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  bool _busy = false;
  bool _opening = false;
  bool _obscure = true;
  bool _networkReady = false;
  bool _needCaptcha = false;
  bool _captchaLoading = false;
  Uint8List? _captchaBytes;
  /// 提示统一走灵动岛：赋值即弹通知，页面内不再用小字承载错误/提示。
  /// 只保留 setter，传 null 表示清空（页面已无小字错误位）。
  set _error(String? v) {
    if (v == null || v.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showInkNotice(context, v, title: '登录', tone: InkTone.danger);
    });
  }

  /// 多因子验证：密码已通过，等短信 / 企业微信验证码
  bool _needMfa = false;
  bool _mfaSending = false;
  bool _mfaSent = false;
  String _mfaType = '4';

  /// 验证码预检结果缓存：同一学号 2 分钟内不重复请求，省一次往返
  String _captchaCheckedFor = '';
  DateTime? _captchaCheckedAt;

  @override
  void initState() {
    super.initState();
    _userCtrl.text = ref.read(sessionProvider).savedUsername;
    WidgetsBinding.instance.addPostFrameCallback((_) => _preload());
  }

  /// 预检：之前登录过时提前建立通道并判断该设备是否需要验证码，
  /// 让「全新设备第一次登录」的验证码输入框在第一屏就出现。
  Future<void> _preload() async {
    if (!mounted) return;
    final username = _userCtrl.text.trim();
    if (username.isEmpty) return;
    final cas = ref.read(casAuthProvider);
    final sw = Stopwatch()..start();
    try {
      // 认证中心公网可达：直连拉登录页与「探测校内/校外 + 建隧道」并行，
      // 校外时不用先等 4s 直连探测超时。
      Object? netError;
      await (_networkReady ? Future<void>.value() : _configureNetwork(username))
          .catchError((Object e) {
        netError = e;
      });
      if (netError != null) throw netError!;
      if (!cas.prepared) await _ensurePrepare(cas);
      final need = await cas.checkNeedCaptcha(username);
      _captchaCheckedFor = username;
      _captchaCheckedAt = DateTime.now();
      AppLog.d('登录', '登录预检完成 ${sw.elapsedMilliseconds}ms（需验证码=$need）');
      if (need && mounted && !_needCaptcha) {
        setState(() => _needCaptcha = true);
        await _loadCaptcha();
        _codeFocus.requestFocus();
      } else if (!need && _needCaptcha && mounted) {
        setState(() {
          _needCaptcha = false;
          _captchaBytes = null;
          _codeCtrl.clear();
        });
      }
    } catch (e) {
      // 预检失败不打扰用户，提交时会再次判断并给出明确提示
      AppLog.d('登录', '验证码预检跳过：$e');
    }
  }

  /// 校外自动建通道：校内直连，校外经本地隧道访问认证中心与教务。
  Future<void> _configureNetwork(String xh) async {
    final tunnel = ref.read(campusTunnelProvider);
    if (xh.isNotEmpty) tunnel.setFallbackXh(xh);
    final sw = Stopwatch()..start();
    try {
      final used = await tunnel.adapt(ref.read(jwClientProvider), xh: xh, warm: false);
      final port = tunnel.port;
      if (used) {
        // 只截取学号做一次轻量准入校验：不传账号密码、不建完整登录态，
        // 服务端按学号返回放行结果。网络异常时不拦，交给后续真实请求判断。
        final authXh = xh.trim().isNotEmpty
            ? xh.trim()
            : ref.read(sessionProvider).savedUsername.trim();
        if (authXh.isNotEmpty) {
          try {
            await UsageTracker.checkAllowed(authXh);
          } on AccessDeniedException catch (e) {
            // 服务端明确拒绝：直接按未授权处理，不能降级成网络错误
            throw AuthException(e.message);
          } on DioException catch (e) {
            final s = e.response?.statusCode;
            if (s == 403 || s == 409) {
              throw AuthException(_tunnelError(e));
            }
            AppLog.w('登录', '准入校验跳过：$e');
          } catch (e) {
            // 校验接口不可达时不拦登录，交给后续真实请求判断
            AppLog.w('登录', '准入校验跳过：$e');
          }
        }
        if (port != null) ref.read(casAuthProvider).setProxyPort(port, force: true);
      }
      _networkReady = true;
      AppLog.d('登录', '网络通道就绪 ${sw.elapsedMilliseconds}ms（隧道=$used）');
    } on AccessDeniedException catch (e) {
      throw AuthException(e.message);
    } on AuthException {
      // 业务错误（未授权/换绑）原样上抛，不能被下面统一改写成“网络失败”
      rethrow;
    } catch (e) {
      AppLog.e('登录', '网络通道准备失败：$e');
      throw AuthException(_tunnelError(e));
    }
  }

  /// 认证登录页直连失败时补建通道再重试一次。
  Future<void> _ensurePrepare(CasAuthApi cas) async {
    if (cas.prepared) return;
    try {
      await cas.prepare();
    } on DioException catch (e) {
      if (!_isNetwork(e)) rethrow;
      AppLog.w('登录', '认证页直连失败，启用校外通道后重试：${e.message}');
      final xh = _userCtrl.text.trim();
      final tunnel = ref.read(campusTunnelProvider);
      if (xh.isNotEmpty) tunnel.setFallbackXh(xh);
      final port = await tunnel.ensureStarted();
      await WebViewProxy.set(port);
      ref.read(jwClientProvider).setProxyPort(port);
      cas.setProxyPort(port);
      _networkReady = true;
      await cas.prepare();
    }
  }

  Future<void> _loadCaptcha() async {
    final cas = ref.read(casAuthProvider);
    if (mounted) {
      setState(() {
        _captchaLoading = true;
        _codeCtrl.clear();
      });
    }
    try {
      if (!cas.prepared) await _ensurePrepare(cas);
      final bytes = await cas.captchaImage();
      if (!mounted) return;
      setState(() {
        _captchaBytes = bytes;
        _captchaLoading = false;
      });
    } catch (e) {
      AppLog.w('登录', '验证码加载失败：$e');
      if (!mounted) return;
      setState(() => _captchaLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_needMfa) {
      await _verifyMfa();
      return;
    }
    final username = _userCtrl.text.trim();
    final password = _pwdCtrl.text;
    if (username.isEmpty) {
      setState(() => _error = '请输入学号');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    if (_needCaptcha && _codeCtrl.text.trim().isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final cas = ref.read(casAuthProvider);
    try {
      // 换了学号才清认证会话：同一设备同一账号保留「已信任」Cookie
      final savedUser = ref.read(sessionProvider).savedUsername;
      if (savedUser.isNotEmpty && savedUser != username) {
        await cas.clearCookies();
      }
      final sw = Stopwatch()..start();
      // 先把通道定下来再拉认证页：隧道未就绪时并发拉取必然失败重试，
      // 反而在高延迟链路上多开几条连接（日志里五条并发、21 秒才就绪）。
      Object? netError;
      await (_networkReady
              ? Future<void>.value()
              : _configureNetwork(username))
          .catchError((Object e) {
        netError = e;
      });
      if (netError != null) throw netError!;
      await _ensurePrepare(cas);
      AppLog.d('登录', '通道+认证页就绪 ${sw.elapsedMilliseconds}ms');
      // 预检已确认过的同一学号（2 分钟内）不再重复请求验证码检查
      final checkedRecently =
          _captchaCheckedFor == username &&
          _captchaCheckedAt != null &&
          DateTime.now().difference(_captchaCheckedAt!) <
              const Duration(minutes: 2);
      if (!_needCaptcha && !checkedRecently) {
        var need = false;
        try {
          need = await cas.checkNeedCaptcha(username);
          _captchaCheckedFor = username;
          _captchaCheckedAt = DateTime.now();
        } catch (e) {
          AppLog.d('登录', '验证码检查失败（忽略）：$e');
        }
        if (need) {
          if (mounted) {
            setState(() {
              _needCaptcha = true;
              _busy = false;
              _error = '该设备首次登录需要验证码，请填写后重试';
            });
          }
          await _loadCaptcha();
          if (mounted) _codeFocus.requestFocus();
          return;
        }
        // 服务端已不再要求验证码（设备已被信任）：收起验证码输入
        if (!need && _needCaptcha && mounted) {
          setState(() {
            _needCaptcha = false;
            _captchaBytes = null;
            _codeCtrl.clear();
          });
          AppLog.d('登录', '服务端已信任此设备，无需验证码');
        }
      }

      final swLogin = Stopwatch()..start();
      final cookies = await cas.login(
        username: username,
        password: password,
        captcha: _needCaptcha ? _codeCtrl.text.trim() : '',
      );
      AppLog.d('登录', '密码校验 ${swLogin.elapsedMilliseconds}ms');
      await ref.read(sessionProvider.notifier).loginWithSso(cookies);
      AppLog.d('登录', '原生统一身份认证登录成功，总耗时 ${sw.elapsedMilliseconds}ms');
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } on MfaRequiredException catch (e) {
      AppLog.w('登录', '账号密码通过，需要多因子验证：${e.userId}');
      if (!mounted) return;
      setState(() {
        _needMfa = true;
        _mfaType = e.defaultType;
        _mfaSent = false;
        _mfaCtrl.clear();
        _needCaptcha = false;
        _captchaBytes = null;
        _error = null;
      });
      showInkNotice(
        context,
        '账号密码已验证，请选择验证方式后获取验证码',
        title: '多因子验证',
        tone: InkTone.info,
      );
      // 不再自动发码：由用户选验证方式后手动点击「获取验证码」
    } on AuthException catch (e) {
      AppLog.w('登录', '登录失败：${e.message}');
      if (!mounted) return;
      if (_isNoPermission(e.message)) {
        _handleNoPermission();
        return;
      }
      setState(() => _error = e.message);
      if (_needCaptcha) unawaited(_loadCaptcha());
    } catch (e) {
      AppLog.e('登录', '登录异常：$e');
      if (!mounted) return;
      final msg = _friendly(e);
      if (_isNoPermission(msg)) {
        _handleNoPermission();
        return;
      }
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 服务端拒绝：学号不在 APP 准入白名单（403 not_allowed）
  static bool _isNoPermission(String msg) =>
      msg.contains('白名单') ||
      msg.contains('无权限') ||
      msg.contains('not_allowed');

  /// 非白名单：自建页只提示失败，不弹学号窗口。
  /// 学号窗口只在认证网页里、没有任何其他拦截手段时才使用。
  void _handleNoPermission() {
    showInkNotice(
      context,
      '当前学号未获授权，无法登录',
      title: '无权限登录',
      tone: InkTone.danger,
    );
  }

  /// 发送多因子验证码（企业微信 / 短信）
  Future<void> _sendMfaCode() async {
    if (_mfaSending) return;
    setState(() {
      _mfaSending = true;
      _error = null;
    });
    try {
      final msg = await ref.read(casAuthProvider).sendMfaCode(_mfaType);
      if (!mounted) return;
      setState(() => _mfaSent = true);
      showInkNotice(context, msg, title: '多因子验证', tone: InkTone.info);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      AppLog.e('登录', '发送验证码失败：$e');
      if (mounted) setState(() => _error = '验证码发送失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _mfaSending = false);
    }
  }

  /// 提交多因子验证码并完成登录
  Future<void> _verifyMfa() async {
    if (!_mfaSent) {
      setState(() => _error = '请先选择验证方式并点击「获取验证码」');
      return;
    }
    final code = _mfaCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请输入验证码');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cas = ref.read(casAuthProvider);
      final cookies = await cas.submitMfa(code);
      await ref.read(sessionProvider.notifier).loginWithSso(cookies);
      AppLog.d('登录', '多因子验证登录成功');
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } on AuthException catch (e) {
      AppLog.w('登录', '多因子验证失败：${e.message}');
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      AppLog.e('登录', '多因子验证异常：$e');
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static bool _isNetwork(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        (e.type == DioExceptionType.unknown && e.error is SocketException);
  }

  /// 通道设备认证失败时给可读文案（409 换绑 / 403 白名单）
  String _tunnelError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final code = body is Map ? '${body['error'] ?? ''}' : '';
      if (code == 'device_mismatch' || status == 409) {
        return '该学号已绑定其他设备，请先在网页登录或联系管理员重置';
      }
      if (code == 'not_allowed' || status == 403) {
        return '该学号未加入白名单，暂无法校外登录';
      }
      if (_isNetwork(e)) return '网络连接失败，请检查网络后重试';
      if (status != null) return '登录通道异常（$status），请稍后重试';
    }
    return '网络连接失败，请检查网络后重试';
  }

  String _friendly(Object e) {
    if (e is AuthException) return e.message;
    if (e is AccessDeniedException) return e.message;
    if (e is DioException) return _tunnelError(e);
    return '登录失败，请稍后重试';
  }

  Future<void> _openSso({bool wfw = false}) async {
    if (_opening) return;
    setState(() => _opening = true);
    final ok = await Navigator.of(context)
        .push<bool>(InkPageRoute(builder: (_) => SsoLoginPage(wfw: wfw)));
    if (!mounted) return;
    setState(() => _opening = false);
    if (ok == true && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _codeCtrl.dispose();
    _mfaCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: InkSpacing.xxl,
              vertical: InkSpacing.xxl,
            ),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _entrance,
                curve: InkMotion.standard,
              ),
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.02), end: Offset.zero)
                    .animate(
                      CurvedAnimation(
                        parent: _entrance,
                        curve: InkMotion.standard,
                      ),
                    ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: InkSpacing.xxxl),
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/app_icon.png',
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: InkSpacing.l),
                    Text(
                      '海畔',
                      textAlign: TextAlign.center,
                      style: context.tsDisplay,
                    ),
                    const SizedBox(height: InkSpacing.xxxl),
                    _formCard(),
                    const SizedBox(height: InkSpacing.s),
                    TextButton(
                      onPressed: _opening || _busy ? null : () => _openSso(),
                      child: Text(_opening ? '正在打开认证网页…' : '使用认证网页登录'),
                    ),
                    if (widget.showGuestButton) ...[
                      const SizedBox(height: InkSpacing.xs),
                      OutlinedButton(
                        onPressed: () =>
                            ref.read(sessionProvider.notifier).enterGuest(),
                        child: const Text('以游客身份浏览'),
                      ),
                    ],
                    const SizedBox(height: InkSpacing.l),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formCard() {
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InkIconBadge(icon: AppIcons.shield, tone: InkTone.info),
              const SizedBox(width: InkSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('统一身份认证', style: context.tsBodyStrong),
                    const SizedBox(height: 2),
                    Text('使用学号与密码直接登录教务', style: context.tsCaption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: InkSpacing.l),
          TextField(
            controller: _userCtrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(
              labelText: '学号',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            onEditingComplete: () => FocusScope.of(context).nextFocus(),
            onTapOutside: (_) {
              FocusScope.of(context).unfocus();
            },
          ),
          const SizedBox(height: InkSpacing.m),
          TextField(
            controller: _pwdCtrl,
            obscureText: _obscure,
            textInputAction: _needCaptcha
                ? TextInputAction.next
                : TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscure ? '显示密码' : '隐藏密码',
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) {
              if (_needCaptcha) {
                _codeFocus.requestFocus();
              } else {
                _submit();
              }
            },
          ),
          if (_needMfa) ...[
            const SizedBox(height: InkSpacing.m),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '4', label: Text('企业微信')),
                ButtonSegment(value: '3', label: Text('短信')),
              ],
              selected: {_mfaType},
              showSelectedIcon: false,
              onSelectionChanged: (_mfaSending || _busy)
                  ? null
                  : (v) {
                      // 只切换方式，验证码由用户主动点击发送
                      setState(() {
                        _mfaType = v.first;
                        _mfaSent = false;
                        _error = null;
                      });
                    },
            ),
            const SizedBox(height: InkSpacing.m),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _mfaCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _verifyMfa(),
                  ),
                ),
                const SizedBox(width: InkSpacing.m),
                SizedBox(
                  width: 104,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: (_mfaSending || _busy)
                        ? null
                        : () => _sendMfaCode(),
                    child: _mfaSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _mfaSent ? '重新发送' : '获取验证码',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                  ),
                ),
              ],
            ),
          ],
          if (_needCaptcha) ...[
            const SizedBox(height: InkSpacing.m),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    focusNode: _codeFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: InkSpacing.m),
                _captchaBox(),
              ],
            ),
          ],
          const SizedBox(height: InkSpacing.l),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_needMfa ? '验证并登录' : '登录'),
          ),
        ],
      ),
    );
  }

  Widget _captchaBox() {
    final empty = _captchaBytes == null || _captchaBytes!.isEmpty;
    return GestureDetector(
      onTap: _captchaLoading ? null : _loadCaptcha,
      child: Container(
        width: 104,
        height: 52,
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.ink.cardFill,
          borderRadius: BorderRadius.circular(InkRadius.control),
          border: Border.all(color: context.ink.hairline),
        ),
        child: empty
            ? (_captchaLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('点击获取', style: context.tsCaption))
            : Image.memory(
                _captchaBytes!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
      ),
    );
  }
}
