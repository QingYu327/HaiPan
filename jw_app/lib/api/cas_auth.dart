import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, Platform;
import 'dart:math';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/app_log.dart';
import 'auth_api.dart' show AuthException;

/// 密码正确，但学校安全策略要求先完成多因子验证（短信 / 企业微信）。
class MfaRequiredException extends AuthException {
  MfaRequiredException({required this.userId, required this.defaultType})
      : super('需要多因子验证');

  final String userId;

  /// '4' = 企业微信验证码，'3' = 短信验证码
  final String defaultType;
}

/// 学校统一身份认证（金智 authserver）原生登录。
///
/// 与原 WebView 流程等价，只是把「渲染页面 → 输入 → 提交」改成直接走接口：
/// 1. GET 登录页，保留 CAS 会话（service 参数存在会话里，POST 不能再丢）
/// 2. checkNeedCaptcha 判断是否需要验证码，需要则拉取验证码图片
/// 3. encrypt.js 同款 AES-CBC 加密密码（随机 64 位前缀 + 随机 IV）
/// 4. POST 登录，跟随 302 回到教务，取出 jw 域 Cookie 交给会话层
class CasAuthApi {
  static const _base = 'https://authserver.gdou.edu.cn';
  static const _directService = 'https://jw.gdou.edu.cn/sso/jziotlogin';
  static const _jw = 'https://jw.gdou.edu.cn';

  static const _crypto = MethodChannel('cn.gdou.xiuhong/crypto');

  CookieJar? _jar;
  final Completer<void> _readyCompleter = Completer<void>();
  int? _proxyPort;

  CasAuthApi() {
    unawaited(_initJar());
  }

  /// 认证 Cookie 落盘：学校「信任此设备」靠的就是这套会话 Cookie，
  /// 落盘后重启 App 仍能被识别为同一设备，不必反复验证码 / 多因子。
  Future<void> _initJar() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final path = '${dir.path}${Platform.pathSeparator}cas_cookies';
      _jar = PersistCookieJar(storage: FileStorage(path));
    } catch (e) {
      _jar = CookieJar();
      AppLog.w('登录', '认证 Cookie 持久化失败，退回内存存储：$e');
    } finally {
      _resetDio();
      _readyCompleter.complete();
    }
  }

  Future<void> get ready => _readyCompleter.future;

  /// 通知学校统一身份认证注销会话，再清本地 Cookie。
  /// 只清本地会让服务端保留在线记录，重新登录时出现重复登录。
  Future<void> logout() async {
    await ready;
    try {
      final resp = await _dio.get(
        '/authserver/logout',
        queryParameters: {'service': _base},
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: _acceptUnder500,
        ),
      );
      AppLog.d('登录', '已注销统一身份认证会话：HTTP ${resp.statusCode}');
    } catch (e) {
      AppLog.w('登录', '注销统一身份认证会话失败（继续本地清理）：$e');
    }
    await clearCookies();
  }

  /// 切换学号 / 退出登录时清空认证会话，避免复用上一个账号的 Cookie
  Future<void> clearCookies() async {
    await ready;
    // 作废旧登录页的在飞预检，并中断其请求：
    // 否则旧请求可能在清理后回写 Cookie / 登录页参数，导致重新登录时
    // 用上一会话的 execution、salt 提交，被认证中心判成「账号或密码错误」。
    _generation++;
    _prepareFuture = null;
    _resetDio();
    await _jar?.deleteAll();
    _prefetched = null;
    _prepared = false;
    _salt = '';
    _hidden.clear();
    _mfaPending = false;
    _mfaUser = '';
    _mfaType = '4';
    _mfaService = _directService;
    _mfaViewUrl = '';
    AppLog.d('登录', '已清空统一身份认证会话');
  }

  /// 认证会话代次：清理后递增，旧的异步结果不再回写状态。
  int _generation = 0;
  bool _dioInitialized = false;

  late Dio _dio = _build();

  Dio _build() {
    final d = Dio(BaseOptions(
      baseUrl: _base,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      followRedirects: true,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    ));
    d.httpClientAdapter = _adapterFor(_proxyPort);
    final jar = _jar;
    if (jar != null) d.interceptors.add(CookieManager(jar));
    _dioInitialized = true;
    return d;
  }

  /// 重建 Dio：强制断开旧的 keep-alive 连接并取消在飞请求。
  void _resetDio() {
    if (_dioInitialized) {
      try {
        _dio.close(force: true);
      } catch (_) {
        // 关闭失败不阻塞清理
      }
      _dioInitialized = false;
    }
    _dio = _build();
  }

  /// 校外环境由登录页在通道就绪后调用，后续请求经本地隧道访问认证中心。
  /// 传 null 表示改回直连（官方 WebVPN 模式走公网，不套隧道）。
  void setProxyPort(int? port, {bool force = false}) {
    if (_proxyPort == port && !force) return;
    _proxyPort = port;
    // 强制重建 adapter：隧道重启后旧连接池里的 socket 指向已关闭的本地端口，
    // 复用它们会直接 Connection refused（日志里 port=33408 那类失败）。
    _dio.httpClientAdapter = _adapterFor(port);
    AppLog.d('登录', port == null ? '认证请求改回直连' : '认证请求改走本地隧道 :$port');
  }

  /// 认证请求固定直连 authserver（校外时经本地隧道），连接池参数与教务侧一致。
  IOHttpClientAdapter _adapterFor(int? port) => IOHttpClientAdapter(
        createHttpClient: () {
          final c = HttpClient()
            ..connectionTimeout = const Duration(seconds: 15)
            // 空闲保留 120s：登录链路多次跳转尽量复用同一条连接
            ..idleTimeout = const Duration(seconds: 120)
            ..maxConnectionsPerHost = 6;
          c.findProxy = (_) =>
              port == null ? 'DIRECT' : 'PROXY 127.0.0.1:$port';
          return c;
        },
      );

  void dispose() => _dio.close(force: true);

  /// 登录页隐藏字段（execution / lt / dllt …）与密码盐
  final Map<String, String> _hidden = {};
  String _salt = '';
  bool _prepared = false;

  /// 多因子验证态：密码已通过，等验证码
  String _mfaUser = '';
  String _mfaType = '4';
  String _mfaService = _directService;

  /// 多因子页地址（提交验证码时作为 Referer，部分网关会校验）
  String _mfaViewUrl = '';

  /// prepare 阶段就遇到多因子页（上次验证未完成）
  bool _mfaPending = false;
  final Random _rand = Random.secure();
  String? _bfp;

  /// 认证会话仍然有效时，prepare 会直接拿到教务 Cookie，登录时直接复用
  Map<String, String>? _prefetched;

  static final _jwHost = Uri.parse(_jw).host;

  static bool _acceptUnder500(int? s) => s != null && s < 500;

  /// 多因子页面的公共判定（reAuthLoginView.do / 页面内 reAuthParams）
  static bool _isMfaPage(String url, String html) =>
      url.contains('reAuthLoginView.do') ||
      html.contains('reAuthParams') ||
      html.contains('多因子认证');

  /// 从多因子页解析验证参数并登记设备指纹
  Future<void> _captureMfa(String html, Uri uri, String fallbackUser) async {
    _mfaUser = RegExp(r'"reAuthUserId"\s*:\s*"([^"]+)"')
            .firstMatch(html)
            ?.group(1) ??
        fallbackUser;
    _mfaType = RegExp(r'"reAuthType"\s*:\s*"([34])"').firstMatch(html)?.group(1) ??
        '4';
    final service = RegExp(r'"serviceUrl"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1) ?? '';
    _mfaService =
        service.isEmpty ? _directService : _normalizeService(service);
    if (_mfaService.isEmpty) _mfaService = _directService;
    _mfaViewUrl = uri.toString();
    _mfaPending = true;
    await _sendBfp();
  }

  /// 登录页已解析且拿到密码盐才算可用（异常页面拿不到盐，需要重新拉取）
  bool get prepared => _prepared && _salt.isNotEmpty;

  /// 拉取认证登录页：建立 CAS 会话（service 绑定在会话上）并解析表单。
  ///
  /// 并发合并：登录页预检（_preload）和提交（_submit）可能同时触发 prepare，
  /// 隧道带宽有限，重复拉取会把首屏拖到 20 秒以上，这里只保留一个在飞请求。
  Future<void> prepare() {
    final running = _prepareFuture;
    if (running != null) return running;
    final f = _doPrepare();
    _prepareFuture = f;
    return f.whenComplete(() {
      if (identical(_prepareFuture, f)) _prepareFuture = null;
    });
  }

  Future<void>? _prepareFuture;

  Future<void> _doPrepare() async {
    await ready;
    final gen = _generation;
    final resp = await _dio.get(
      '/authserver/login',
      queryParameters: {'service': _directService},
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (gen != _generation) {
      AppLog.d('登录', '登录页预检结果已过期（会话已清理），丢弃');
      return;
    }
    final html = resp.data is String ? resp.data as String : '';
    // 认证中心会话未过期时，GET login 会直接带票据跳回教务
    if (resp.realUri.host == _jwHost) {
      _prefetched = await _jwCookies();
      _salt = '';
      _hidden.clear();
      _prepared = false;
      AppLog.d('登录', '认证会话仍然有效，直接复用教务 Cookie');
      return;
    }
    // 上一次多因子未完成时，GET login 会停在多因子页：直接把验证态接回来
    if (_isMfaPage(resp.realUri.toString(), html)) {
      _prefetched = null;
      await _captureMfa(html, resp.realUri, '');
      _prepared = false;
      _hidden.clear();
      _salt = '';
      AppLog.w('登录', '认证会话仍处于多因子验证态（type=$_mfaType）');
      return;
    }
    _parseLoginPage(html);
    _prepared = true;
    AppLog.d(
      '登录',
      '认证登录页已解析：salt=${_salt.isEmpty ? '无' : '有(${_salt.trim().length}位)'}, '
      'execution=${_hidden['execution'] ?? '-'}, lt=${_hidden['lt'] ?? '-'}',
    );
  }

  void _parseLoginPage(String html) {
    _prefetched = null;
    _mfaPending = false;
    _hidden.clear();
    _salt = '';
    // 用户名密码表单之后的隐藏域：execution、lt、_eventId、cllt、dllt…
    final start = html.indexOf('id="pwdFromId"');
    final scope = start >= 0 ? html.substring(start) : html;
    final end = scope.indexOf('</form>');
    final form = end > 0 ? scope.substring(0, end) : scope;

    for (final m in RegExp(r'<input[^>]*>').allMatches(form)) {
      final tag = m.group(0)!;
      if (!tag.contains('type="hidden"')) continue;
      final name = _attr(tag, 'name');
      final value = _attr(tag, 'value') ?? '';
      if (name == null || name.isEmpty) continue;
      _hidden[name] = value;
    }
    _salt = RegExp(r'id="pwdEncryptSalt"[^>]*value="([^"]*)"')
            .firstMatch(form)
            ?.group(1) ??
        '';
  }

  static String? _attr(String tag, String key) {
    return RegExp('$key="([^"]*)"').firstMatch(tag)?.group(1);
  }

  /// 是否需要验证码（全新设备 / 密码错误多次后会出现）。
  Future<bool> checkNeedCaptcha(String username) async {
    await ready;
    // 登录页还在拉取时先等它，避免同时占用隧道再开一条连接
    final running = _prepareFuture;
    if (running != null) {
      try {
        await running;
      } catch (_) {}
    }
    final resp = await _dio.get(
      '/authserver/checkNeedCaptcha.htl',
      queryParameters: {
        'username': username,
        '_': DateTime.now().millisecondsSinceEpoch,
      },
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final data = resp.data;
    if (data is Map) return data['isNeed'] == true;
    return false;
  }

  /// 验证码图片（JPEG/PNG 字节，直接给 Image.memory）
  Future<Uint8List> captchaImage() async {
    await ready;
    final resp = await _dio.get<List<int>>(
      '/authserver/getCaptcha.htl',
      queryParameters: {'ts': DateTime.now().millisecondsSinceEpoch},
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    return Uint8List.fromList(resp.data ?? const []);
  }

  /// 提交登录。成功返回 jw 域 Cookie；失败抛 [AuthException]（含服务端提示）。
  Future<Map<String, String>> login({
    required String username,
    required String password,
    String captcha = '',
  }) async {
    await ready;
    if (!prepared) await prepare();
    final pre = _prefetched;
    if (pre != null) {
      _prefetched = null;
      _prepared = false;
      if (pre.isNotEmpty) {
        AppLog.d('登录', '复用已认证会话，跳过密码提交');
        return pre;
      }
    }
    if (_mfaPending) {
      _mfaPending = false;
      throw MfaRequiredException(userId: _mfaUser, defaultType: _mfaType);
    }
    if (_salt.isEmpty) {
      // 盐由登录页下发，取不到时无法加密，让用户退回网页登录
      throw AuthException('认证页未下发加密参数，请使用网页登录');
    }
    final encrypted = await _encrypt(password);
    final data = <String, String>{
      'username': username,
      'password': encrypted,
      'captcha': captcha,
      '_eventId': _hidden['_eventId'] ?? 'submit',
      'cllt': _hidden['cllt'] ?? 'userNameLogin',
      'dllt': _hidden['dllt'] ?? 'generalLogin',
      'lt': _hidden['lt'] ?? '',
      'execution': _hidden['execution'] ?? 'e1s1',
    };
    AppLog.d('登录', '提交统一身份认证：$username（验证码 ${captcha.isEmpty ? '无' : '有'}）');

    // 必须带 service：认证中心按请求里的 service 生成票据，缺省会回到登录页
    final loginPath =
        '/authserver/login?service=${Uri.encodeComponent(_directService)}';
    final resp = await _dio.post(
      loginPath,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 500,
        headers: {
          'Origin': _base,
          'Referer': '$_base$loginPath',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        },
      ),
    );

    final raw = resp.data is String ? resp.data as String : '';
    AppLog.d(
      '登录',
      '认证回复：HTTP ${resp.statusCode} len=${raw.length} @${resp.realUri.path}'
      '${_locationOf(resp) == null ? '' : ' -> ${_briefUri(_locationOf(resp)!)}'}',
    );
    // Dart 的 HttpClient 不会为 POST 自动跟随 3xx，必须手动跟完再判断落点
    final (finalUri, html, status) = await _followRedirects(resp);
    final brief = html.replaceAll(RegExp(r'\s+'), ' ');
    AppLog.d(
      '登录',
      '认证落点：HTTP $status len=${html.length} @${finalUri.host}${finalUri.path}',
    );
    if (brief.isNotEmpty) {
      AppLog.d('登录', '认证回复片段：${brief.substring(0, min(160, brief.length))}');
    }
    // 密码正确，但学校要求多因子验证：把验证态留给登录页继续输入验证码
    if (_isMfaPage(finalUri.toString(), html)) {
      await _captureMfa(html, finalUri, username);
      AppLog.w(
        '登录',
        '账号密码已通过，需要多因子验证（type=$_mfaType, '
        'service=${_briefUri(_mfaService)}, view=${_briefUri(_mfaViewUrl)}）',
      );
      throw MfaRequiredException(userId: _mfaUser, defaultType: _mfaType);
    }
    if (finalUri.host == _jwHost) {
      final cookies = await _jwCookies();
      if (cookies.isEmpty) {
        throw AuthException('认证成功但未获取到教务会话，请重试');
      }
      AppLog.d('登录', '统一身份认证成功，回跳 ${finalUri.path}');
      AppLog.d(
        '登录',
        '票据落点内容：密码框=${html.contains('type="password"')} len=${html.length}，'
        'Cookie=${cookies.keys.join(',')}',
      );
      return cookies;
    }
    final msg = _errorText(html, finalUri);
    AppLog.w('登录', '统一身份认证失败：$msg @${finalUri.path}');
    throw AuthException(msg);
  }

  /// 手动跟随 3xx（Dio/Dart 对 POST 302 不自动跳转），返回落点、正文与状态码。
  Future<(Uri, String, int)> _followRedirects(Response resp) async {
    var uri = resp.realUri;
    var status = resp.statusCode ?? 0;
    var html = resp.data is String ? resp.data as String : '';
    var location = _locationOf(resp);
    var hops = 0;
    while (status >= 300 && status < 400 && location != null && location.isNotEmpty) {
      if (++hops > 8) break;
      final next = _upgradeHttp(uri.resolve(location));
      AppLog.d('登录', '跟随认证跳转：${_briefUri(next.toString())}');
      final r = await _dio.getUri(
        next,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          // 500 也要拿到落点，交给上层判断是否换下一个 service
          validateStatus: (s) => s != null && s < 600,
          headers: {'Referer': uri.toString()},
        ),
      );
      uri = r.realUri;
      status = r.statusCode ?? 0;
      html = r.data is String ? r.data as String : '';
      location = _locationOf(r);
    }
    return (uri, html, status);
  }

  static String? _locationOf(Response r) => r.headers.value('location');

  /// 学校跳转有时下发 `http://` 明文地址：直接升到 https。
  /// 否则要多走一跳 80 端口（日志里 `authserver.gdou.edu.cn:80 #4`），
  /// 而且会把认证会话 Cookie 暴露在明文链路上。
  static Uri _upgradeHttp(Uri u) {
    if (u.scheme != 'http') return u;
    if (!(u.host == 'gdou.edu.cn' || u.host.endsWith('.gdou.edu.cn'))) return u;
    return u.replace(scheme: 'https', port: u.port == 80 ? null : u.port);
  }

  /// 多因子页面里的 serviceUrl 可能带 `\/`、`\u0026` 转义或整段 URL 编码，
  /// 统一还原成可请求的地址；解析不出 http(s) 时返回空串。
  static String _normalizeService(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    s = s
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u003d', '=');
    if (s.startsWith('http%3A') || s.startsWith('https%3A')) {
      try {
        s = Uri.decodeComponent(s);
      } catch (_) {}
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) return '';
    return s;
  }

  /// 多因子相关接口是页面里的 AJAX 请求，补齐 XMLHttpRequest 头与 Referer
  Map<String, String> get _xhrHeaders => {
    'X-Requested-With': 'XMLHttpRequest',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Origin': _base,
    if (_mfaViewUrl.isNotEmpty) 'Referer': _mfaViewUrl,
  };

  static String _briefUri(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return '${u.host}${u.path}';
  }

  Future<String> _encrypt(String password) async {
    // 学校 encrypt.js 会先 trim 掉盐值空白，这里保持一致
    final salt = _salt.trim();
    if (salt.length < 16) {
      throw AuthException('认证页未下发有效加密参数，请使用官方通道登录');
    }
    final enc = await _crypto.invokeMethod<String>(
      'aesEncrypt',
      {'text': password, 'salt': salt},
    );
    if (enc == null || enc.isEmpty) {
      throw AuthException('密码加密失败，请重试');
    }
    return enc;
  }

  /// 设备指纹：多因子校验阶段认证中心会读取，失败不影响后续提交。
  Future<void> _sendBfp() async {
    _bfp ??= await _deviceFingerprint();
    try {
      await _dio.get(
        '/authserver/bfp/info',
        queryParameters: {'bfp': _bfp},
        options: Options(validateStatus: _acceptUnder500),
      );
    } catch (_) {}
  }

  /// 设备指纹固定化：随机生成后落盘复用。
  /// 每次启动都换新指纹会被认证中心当成「新设备」，从而反复要求验证码 / 多因子。
  Future<String> _deviceFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    var v = prefs.getString('cas.bfp') ?? '';
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(v)) {
      v = List.generate(32, (_) => _rand.nextInt(16).toRadixString(16)).join();
      await prefs.setString('cas.bfp', v);
    }
    return v;
  }

  /// 发送多因子验证码：[type] '4' 企业微信、'3' 短信。返回可读提示。
  Future<String> sendMfaCode(String type) async {
    await ready;
    if (_mfaUser.isEmpty) throw AuthException('验证会话已失效，请重新登录');
    _mfaType = type == '3' ? '3' : '4';
    // 切换验证方式失败不阻塞发码，部分会话沿用默认方式即可
    try {
      await _dio.post(
        '/authserver/reAuthCheck/changeReAuthType.do',
        data: {
          'isMultifactor': 'true',
          'reAuthType': _mfaType,
          'service': _mfaService,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          validateStatus: _acceptUnder500,
          headers: _xhrHeaders,
        ),
      );
    } catch (e) {
      AppLog.d('登录', '切换验证方式忽略：$e');
    }
    final resp = await _dio.post(
      '/authserver/dynamicCode/getDynamicCodeByReauth.do',
      data: {
        'userName': _mfaUser,
        'authCodeTypeName': _mfaType == '4'
            ? 'reAuthWChatDynamicCodeType'
            : 'reAuthDynamicCodeType',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        validateStatus: _acceptUnder500,
        headers: _xhrHeaders,
      ),
    );
    final body = resp.data is String ? resp.data as String : '';
    final brief = body.replaceAll(RegExp(r'\s+'), ' ');
    AppLog.d(
      '登录',
      '发送验证码（type=$_mfaType）：HTTP ${resp.statusCode}'
      '${brief.isEmpty ? '' : ' ${brief.substring(0, min(120, brief.length))}'}',
    );
    final fallback =
        _mfaType == '4' ? '企业微信验证码已发送，请查收' : '短信验证码已发送，请查收';
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        final ret = '${data['returnMessage'] ?? ''}'.trim();
        final mobile = '${data['mobile'] ?? ''}'.trim();
        if (ret.isNotEmpty) return mobile.isEmpty ? ret : '$ret $mobile';
      }
    } catch (_) {}
    if ((resp.statusCode ?? 200) >= 400) {
      throw AuthException('验证码发送失败，请稍后重试');
    }
    return fallback;
  }

  /// 提交多因子验证码，通过后换取教务 Cookie。
  Future<Map<String, String>> submitMfa(String code) async {
    await ready;
    if (_mfaUser.isEmpty) throw AuthException('验证会话已失效，请重新登录');
    final trimmed = code.trim();
    if (trimmed.isEmpty) throw AuthException('请输入验证码');
    await _sendBfp();
    final resp = await _dio.post(
      '/authserver/reAuthCheck/reAuthSubmit.do',
      data: {
        'service': _mfaService,
        'reAuthType': _mfaType,
        'isMultifactor': 'true',
        'password': '',
        'dynamicCode': trimmed,
        'uuid': '',
        'answer1': '',
        'answer2': '',
        'otpCode': '',
        'skipTmpReAuth': 'true',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        // 响应是 AJAX JSON，不会自带 302；换票要自己发起
        followRedirects: false,
        validateStatus: (s) => s != null && s < 600,
        headers: _xhrHeaders,
      ),
    );
    final body = resp.data is String ? resp.data as String : '';
    final brief = body.replaceAll(RegExp(r'\s+'), ' ');
    AppLog.d(
      '登录',
      '多因子提交回复：HTTP ${resp.statusCode} len=${body.length}'
      '${brief.isEmpty ? '' : ' 片段=${brief.substring(0, min(220, brief.length))}'}',
    );
    var codeVal = '';
    var msg = '';
    var redirect = '';
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        codeVal = '${data['code'] ?? ''}';
        msg = '${data['msg'] ?? data['message'] ?? ''}'.trim();
        for (final key in const [
          'url',
          'redirectUrl',
          'redirectURL',
          'redirectUri',
          'reAuthUrl',
          'serviceUrl',
        ]) {
          final v = data[key];
          if (v is String && _normalizeService(v).isNotEmpty) {
            redirect = _normalizeService(v);
            break;
          }
        }
      }
    } catch (_) {}
    if (codeVal == 'reAuth_failed' || codeVal == 'reAuth_unauthorized') {
      throw AuthException(msg.isNotEmpty ? msg : '验证码错误或已过期，请重新输入');
    }
    if ((resp.statusCode ?? 0) >= 400) {
      throw AuthException(msg.isNotEmpty ? msg : '多因子验证失败，请重试');
    }

    // MFA 通过后只做一次换票：票据受众固定为教务 sso（服务端若下发 redirect 则优先）。
    // 之前按候选 service 逐个探测，一次失败要把整条链路重走一遍，光重试就是 10s+。
    final redirectSvc = _normalizeService(redirect);
    final svc = redirectSvc.isNotEmpty ? redirectSvc : _directService;
    final url = '$_base/authserver/login?service=${Uri.encodeComponent(svc)}';
    var last = '';
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final r = await _dio.getUri(
          Uri.parse(url),
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 600,
            headers: {
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              if (_mfaViewUrl.isNotEmpty) 'Referer': _mfaViewUrl,
            },
          ),
        );
        final (uri, html, status) = await _followRedirects(r);
        last = 'HTTP $status @${uri.host}${uri.path}';
        AppLog.d('登录', '多因子换票（第 $attempt 次）：→ $last');
        if (_isMfaPage(uri.toString(), html)) {
          last = '仍需多因子验证 @${uri.path}';
          break;
        }
        if (uri.host == _jwHost) {
          final cookies = await _jwCookies();
          if (cookies.isNotEmpty) {
            _mfaPending = false;
            AppLog.d('登录', '多因子验证通过，统一身份认证成功');
            AppLog.d(
              '登录',
              '票据落点内容：密码框=${html.contains('type="password"')} '
              'len=${html.length}，Cookie=${cookies.keys.join(',')}',
            );
            return cookies;
          }
          last = '教务会话为空 @${uri.path}';
        }
      } catch (e) {
        last = '$e';
        AppLog.w('登录', '多因子换票失败（第 $attempt 次）：$e');
      }
    }
    throw AuthException('多因子验证未生效（$last），请重新登录');
  }

  Future<Map<String, String>> _jwCookies() async {
    await ready;
    return _cookiesAt(Uri.parse('$_jw/'));
  }

  /// 读取指定域名的 Cookie（官方通道成功后会话落在 wfw 域）
  Future<Map<String, String>> _cookiesAt(Uri uri) async {
    await ready;
    final list = await _jar!.loadForRequest(uri);
    return {
      for (final c in list)
        if (c.name.isNotEmpty && c.value.isNotEmpty) c.name: c.value,
    };
  }

  /// 从失败页提取可读提示（认证中心主题把错误放在 #showErrorTip / #msg）
  String _errorText(String html, Uri uri) {
    final patterns = [
      RegExp(r'id="showErrorTip"[^>]*>([\s\S]*?)</span>'),
      RegExp(r'id="msg"[^>]*>([\s\S]*?)</(?:div|span)>'),
      RegExp(r'class="errors"[^>]*>([\s\S]*?)</div>'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(html);
      if (m == null) continue;
      final text = m
          .group(1)!
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (text.isNotEmpty) {
        if (text.contains('用户名或者密码有误') ||
            text.contains('用户名或密码错误') ||
            text.contains('密码错误')) {
          return '$text（如密码已确认无误，请改用官方通道登录）';
        }
        return text;
      }
    }
    if (html.contains('非常用')) {
      return '该账号在当前网络不常用，请确认学号与密码，或改用官方通道';
    }
    if (html.contains('锁定') || html.contains('冻结')) {
      return '账号已被临时锁定，请等待 15 分钟后再试';
    }
    if (html.contains('captcha')) {
      return '学号或密码不正确，或验证码已失效，请重试';
    }
    if (uri.host == Uri.parse(_base).host) {
      return '登录失败，请检查学号与密码';
    }
    return '登录失败，请稍后重试';
  }
}

final casAuthProvider = Provider<CasAuthApi>((ref) {
  final api = CasAuthApi();
  ref.onDispose(api.dispose);
  return api;
});
