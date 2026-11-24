import 'dart:async';
import 'dart:io' show HttpClient, Platform;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../util/app_log.dart';

/// 会话过期异常：任何数据接口返回登录页 HTML / 302 时抛出
class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([this.message = '登录已过期，请重新登录']);
  @override
  String toString() => message;
}

/// 正方教务返回的 flag!=1 业务失败
class JwBusinessException implements Exception {
  final String message;
  JwBusinessException(this.message);
  @override
  String toString() => message;
}

/// Dio + 持久化 Cookie 会话（正方教务：纯 Cookie 鉴权，无 token/CSRF）
class JwClient {
  static const base = 'https://jw.gdou.edu.cn';

  final Dio dio = Dio(BaseOptions(
    baseUrl: base,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    followRedirects: true,
    // 桌面 UA，避免服务端按移动端降级
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0',
    },
  ));

  PersistCookieJar? _jar;
  final _ready = Completer<void>();

  /// 会话过期回调（由 sessionProvider 注入，负责跳登录页）
  void Function()? onSessionExpired;

  /// 连接失败兜底：启用校外通道后重试一次（由启动流程注入）
  Future<bool> Function()? onConnectionError;

  JwClient() {
    dio.interceptors.add(InterceptorsWrapper(
      onResponse: _detectSessionExpired,
      onError: (e, handler) async {
        // 302 被拦截时（followRedirects=false 的探针除外）也视为会话过期
        if (e.response?.statusCode == 302) {
          final path = e.requestOptions.path;
          if (!path.contains('login')) {
            return handler.reject(DioException(
              requestOptions: e.requestOptions,
              error: SessionExpiredException(),
            ));
          }
        }
        // 校外直连失败：试着切到通道后再请求一次
        final fallback = onConnectionError;
        final connectionFailed =
            e.type == DioExceptionType.connectionError ||
                e.type == DioExceptionType.connectionTimeout;
        if (fallback != null &&
            connectionFailed &&
            e.requestOptions.extra['tunnelRetry'] != true) {
          try {
            e.requestOptions.extra['tunnelRetry'] = true;
            if (await fallback()) {
              final resp = await dio.fetch<dynamic>(e.requestOptions);
              return handler.resolve(resp);
            }
          } catch (err) {
            AppLog.w('通道', '连接失败兜底未成功：$err');
          }
        }
        handler.next(e);
      },
    ));
    _init();
  }

  Future<void> _init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _jar = PersistCookieJar(
        storage: FileStorage('${dir.path}${Platform.pathSeparator}cookies'),
      );
      dio.interceptors.add(CookieManager(_jar!));
    } finally {
      _ready.complete();
    }
  }

  Future<void> get ready => _ready.future;

  /// 响应为登录页 HTML 即会话过期（Dio 默认跟随 302，最终拿到登录页 200）
  void _detectSessionExpired(Response response, ResponseInterceptorHandler handler) async {
    if (response.requestOptions.extra[_kWarmUp] == true) {
      return handler.next(response);
    }
    final path = response.requestOptions.path;
    final isLoginPage = path.contains('login') || path.contains('slogin');
    final data = response.data;
    if (!isLoginPage && data is String && data.contains('login_slogin')) {
      AppLog.w('网络', '会话过期，路径：$path');
      return handler.reject(DioException(
        requestOptions: response.requestOptions,
        error: SessionExpiredException(),
      ));
    }
    handler.next(response);
  }

  /// 把包装了 SessionExpiredException 的 DioException 解包重抛
  Never _rethrowUnwrapped(DioException e) {
    final err = e.error;
    if (err is SessionExpiredException) throw err;
    throw e;
  }

  /// 数据 POST：正方 $.post 自动带 X-Requested-With + Referer
  Future<Response> postData(
    String path,
    Map<String, dynamic> data, {
    String? referer,
    ResponseType? responseType,
  }) async {
    await ready;
    try {
      final resp = await dio.post(
        path,
        data: data,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: responseType,
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': ?referer,
          },
        ),
      );
      AppLog.d('网络', 'POST $path → ${resp.statusCode}');
      return resp;
    } on DioException catch (e) {
      AppLog.e('网络', 'POST $path 失败：$e');
      _rethrowUnwrapped(e);
    }
  }

  Future<Response> getHtml(String path,
      {Map<String, dynamic>? query, bool followRedirects = true}) async {
    await ready;
    try {
      final resp = await dio.get(
        path,
        queryParameters: query,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: followRedirects,
          validateStatus: (s) => s != null && s < 400 || s == 302,
        ),
      );
      AppLog.d('网络', 'GET $path → ${resp.statusCode}');
      return resp;
    } on DioException catch (e) {
      AppLog.e('网络', 'GET $path 失败：$e');
      _rethrowUnwrapped(e);
    }
  }

  /// 登录态探针：请求一个需要登录的页面，302 → 未登录
  Future<bool> probeLoggedIn() async {
    await ready;
    try {
      final resp = await dio.get(
        '/kbcx/xskbcx_cxXsgrkbIndex.html',
        queryParameters: {'gnmkdm': 'N2151', 'layout': 'default'},
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      // 302 → 登录页；200 且内容是登录页（历史 cookie 残留场景）
      if (resp.statusCode == 302) {
        AppLog.d('网络', '登录态探针：302 未登录');
        return false;
      }
      final data = resp.data;
      if (data is String && data.contains('login_slogin')) {
        AppLog.d('网络', '登录态探针：返回登录页');
        return false;
      }
      AppLog.d('网络', '登录态探针：已登录');
      return true;
    } on DioException catch (e) {
      // 网络异常不能误判为未登录
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        rethrow;
      }
      return false;
    }
  }

  Future<void> clearCookies() async {
    await ready;
    await _jar?.deleteAll();
  }

  /// 注入外部登录（统一身份认证 WebView）拿到的 Cookie。
  Future<void> saveCookies(Map<String, String> cookies) async {
    await ready;
    final uri = Uri.parse(base);
    // 学校下发的是会话 Cookie（无 expires）；显式给 30 天有效期，
    // 保证进程被杀/重启后 JSESSIONID 仍能从本地恢复。
    final expires = DateTime.now().add(const Duration(days: 30));
    final list = cookies.entries
        .where((e) => e.key.trim().isNotEmpty)
        .map((e) => Cookie(e.key, e.value)
          ..domain = uri.host
          ..path = '/'
          ..expires = expires)
        .toList();
    await _jar?.saveFromResponse(uri, list);
  }

  int? _proxyPort;
  DateTime? _warmAt;

  /// 校外通道启用后，教务请求改走本地 CONNECT 代理（127.0.0.1:port）。
  ///
  /// 端口未变时直接返回：重建 adapter 会丢掉整个连接池，而公网隧道下每条
  /// 连接都要重新做 TCP + TLS + WebSocket 握手（RTT 1s 时非常明显）。
  void setProxyPort(int port) {
    if (_proxyPort == port) return;
    _proxyPort = port;
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final c = HttpClient()
          ..connectionTimeout = const Duration(seconds: 15)
          // 空闲连接保留 90s：翻页/切页间隙不断开，省掉重连握手
          ..idleTimeout = const Duration(seconds: 90)
          // 限制单域名并发连接，避免一次开多条隧道互相抢带宽
          ..maxConnectionsPerHost = 3;
        c.findProxy = (_) => 'PROXY 127.0.0.1:$port';
        return c;
      },
    );
    AppLog.d('通道', '教务请求改走本地隧道 :$port');
  }

  /// 预热：经本地代理对教务首页发一次轻量请求，让 TCP + TLS + 隧道
  /// WebSocket 提前建好并留在连接池里（90s 空闲期），用户翻页时不用再等握手。
  /// 失败静默；30s 内不重复预热，避免兜底重试时反复触发。
  Future<void> warmUp() async {
    final at = _warmAt;
    if (at != null && DateTime.now().difference(at) < const Duration(seconds: 30)) {
      return;
    }
    _warmAt = DateTime.now();
    final sw = Stopwatch()..start();
    try {
      await dio
          .get<dynamic>(
            '/',
            options: Options(
              responseType: ResponseType.plain,
              followRedirects: true,
              // 预热不关心内容，任何状态码都算成功连接
              validateStatus: (_) => true,
              extra: {_kWarmUp: true},
            ),
          )
          .timeout(const Duration(seconds: 20));
      AppLog.d('通道', '通道预热完成 ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      AppLog.d('通道', '通道预热失败（忽略）${sw.elapsedMilliseconds}ms：$e');
    }
  }

  /// 预热请求的标记：跳过会话过期判定，避免把登录页响应误判为掉登录。
  static const String _kWarmUp = 'warmUp';
}

final jwClientProvider = Provider<JwClient>((ref) {
  final client = JwClient();
  ref.onDispose(client.dio.close);
  return client;
});
