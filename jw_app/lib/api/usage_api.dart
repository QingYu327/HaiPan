import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/app_log.dart';
import '../util/secure_store.dart';
import '../util/server_config.dart';
import '../util/tls_pin.dart';

/// 服务端明确拒绝（白名单未放行 / 设备换绑）：属于业务结果，不能当网络错误处理。
class AccessDeniedException implements Exception {
  AccessDeniedException(this.code, this.message);

  /// `not_allowed` 或 `device_mismatch`
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// 使用人数与访问控制（开发者账号可见统计入口）
class UsageTracker {
  UsageTracker._();

  static const String ownerXh = '202411413203'; // 仅此人可见统计入口

  // 云端受控功能（与 Worker/服务端一致）：
  // 更新用黑名单（update，名单内屏蔽更新）
  // APP 准入用白名单（app，默认禁止，仅名单内可完整使用）
  static const String featureUpdate = 'update';
  static const String featureApp = 'app';
  // /gates 返回的键
  static const String gateUpdateBlock = 'updateBlock';
  static const String gateApp = 'app';

  /// 上次成功查询到的 APP 准入结果（按学号缓存，离线时回退，默认禁止）。
  /// 必须按学号隔离，否则 A 允许、B 未允许时离线会继承 A 的权限。
  static String _appCacheKey(String xh) => 'usage.app_allowed.${xh.trim()}';

  static Future<bool?> _readAppCache(String xh) async {
    final p = await SharedPreferences.getInstance();
    final key = _appCacheKey(xh);
    return p.containsKey(key) ? p.getBool(key) : null;
  }

  static Future<void> _writeAppCache(String xh, bool allowed) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_appCacheKey(xh), allowed);
  }

  /// 供 UI 快速放行：有缓存值时直接返回，从未查询过返回 null
  static Future<bool?> cachedAppAllowed(String xh) => _readAppCache(xh);

  /// 计数器后端（GET 返回 {"count":N,"ids":[...]}）
  /// 入口可在调试页维护，默认取本地/云端下发的当前通道。
  static String get _backendUrl => ServerConfig.apiBase;

  /// 上报后端（POST JSON {"xh":"学号"}）
  static String get _postUrl => _backendUrl;

  /// 引导请求（注册/挑战/验签）不携带会话
  static final Dio _plain = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ))
    // 入口可能是 IP + 自签证书，用固定指纹放行
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: TlsPin.client,
    );

  static String? _token;
  static String? _tokenXh;
  static DateTime? _tokenExpiry;
  static Future<void>? _authFuture;
  static bool _restoreTried = false;

  // 会话令牌持久化：冷启动时直接复用，省去 注册/挑战/验签 三次往返
  static const _kToken = 'usage.token';
  static const _kTokenXh = 'usage.token_xh';
  static const _kTokenExp = 'usage.token_exp';

  static bool _fresh(String xh) =>
      _token != null &&
      _tokenXh == xh &&
      _tokenExpiry != null &&
      DateTime.now().isBefore(_tokenExpiry!);

  static void _clearSession() {
    _token = null;
    _tokenXh = null;
    _tokenExpiry = null;
    _restoreTried = false;
    SecureStore.del(_kToken);
    SecureStore.del(_kTokenXh);
    SecureStore.del(_kTokenExp);
  }

  /// 从安全存储恢复上次的会话（仅在内存中没有会话时尝试一次）
  static Future<void> _restoreSession(String xh) async {
    if (_restoreTried) return;
    _restoreTried = true;
    final savedXh = await SecureStore.get(_kTokenXh);
    final token = await SecureStore.get(_kToken);
    final exp = int.tryParse(await SecureStore.get(_kTokenExp) ?? '');
    if (savedXh != xh || token == null || token.isEmpty || exp == null) return;
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp);
    if (!DateTime.now().isBefore(expiry)) return;
    _token = token;
    _tokenXh = xh;
    _tokenExpiry = expiry;
    AppLog.d('认证', '复用本地会话（剩余 ${expiry.difference(DateTime.now()).inSeconds}s）');
  }

  /// 确保拿到该学号的会话：注册设备 → 取挑战码 → Keystore 签名 → 换会话令牌。
  static Future<void> _ensureSession(String xh) async {
    if (_fresh(xh)) return;
    await _restoreSession(xh);
    if (_fresh(xh)) return;
    final pending = _authFuture;
    if (pending != null) {
      await pending;
      if (_fresh(xh)) return;
    }
    final future = _authenticate(xh);
    _authFuture = future;
    try {
      await future;
    } finally {
      if (identical(_authFuture, future)) _authFuture = null;
    }
  }

  static Future<void> _authenticate(String xh) async {
    AppLog.d('认证', '开始设备认证：$xh');
    final pub = await DeviceAuth.publicKey();
    if (pub.isEmpty) throw StateError('设备密钥不可用');
    Object? last;
    // 任一入口可达即可完成认证；成功后把该入口设为当前入口
    for (final e in ServerConfig.ordered) {
      try {
        await _authenticateAt(e.base, xh, pub);
        if (e.base != ServerConfig.activeBase) {
          AppLog.w('认证', '当前入口不可达，已切换到 ${e.base}');
          await ServerConfig.setActive(e.base);
        }
        AppLog.d('认证', '设备认证成功：$xh');
        return;
      } catch (err) {
        // 业务拒绝（白名单/换绑）换入口也没用，直接抛给界面
        if (err is AccessDeniedException) rethrow;
        last = err;
      }
    }
    // 保留服务端的原始错误（如 409 device_mismatch），便于界面区分验证失败与网络失败
    if (last != null) throw last;
    throw StateError('设备认证失败');
  }

  /// 从服务端响应里取业务错误码（403 not_allowed / 409 device_mismatch）
  static AccessDeniedException? _deniedOf(Response<dynamic> r) {
    final d = r.data;
    if (d is! Map) return null;
    final code = '${d['error'] ?? d['code'] ?? ''}';
    if (code == 'not_allowed') {
      return AccessDeniedException('not_allowed', '该学号未开通公网通道，请使用校园网登录或联系管理员');
    }
    if (code == 'device_mismatch') {
      return AccessDeniedException(
          'device_mismatch', '该学号已绑定其他设备，请先在网页登录或联系管理员重置');
    }
    return null;
  }

  static Future<void> _authenticateAt(
      String base, String xh, String pub) async {
    // 幂等注册；已注册且公钥一致时服务端返回 200
    Response<dynamic> reg;
    try {
      reg = await _plain.post<dynamic>(
        '$base/device/register',
        data: {'xh': xh, 'publicKey': pub},
      );
    } on DioException catch (e) {
      final denied = e.response == null ? null : _deniedOf(e.response!);
      if (denied != null) throw denied;
      // 只看服务端明确给出的业务错误码；网关/限流返回的裸 403 不能当成名单拒绝，
      // 否则校园网或代理链路上的拦截会被误报成「未开通公网通道」。
      rethrow;
    }
    // 有的入口用 200 + error 字段表示拒绝
    final denied = _deniedOf(reg);
    if (denied != null) throw denied;
    final ch = await _plain.post<dynamic>(
      '$base/auth/challenge',
      data: {'xh': xh},
    );
    final challenge =
        ch.data is Map ? '${(ch.data as Map)['challenge'] ?? ''}' : '';
    if (challenge.isEmpty) throw StateError('未获取到挑战码');
    final signature = await DeviceAuth.sign(challenge);
    final verify = await _plain.post<dynamic>(
      '$base/auth/verify',
      data: {'xh': xh, 'challenge': challenge, 'signature': signature},
    );
    final data = verify.data;
    final token = data is Map ? '${data['token'] ?? ''}' : '';
    if (token.isEmpty) throw StateError('认证失败');
    final ttl = data is Map && data['expiresIn'] is num
        ? (data['expiresIn'] as num).toInt()
        : 1500;
    _token = token;
    _tokenXh = xh;
    // 提前 1 分钟过期，避免请求边界踩点
    _tokenExpiry = DateTime.now().add(Duration(seconds: ttl > 90 ? ttl - 60 : ttl));
    // 持久化会话，冷启动直接复用，避免每次启动都做三次认证握手
    await SecureStore.put(_kToken, token);
    await SecureStore.put(_kTokenXh, xh);
    await SecureStore.put(
      _kTokenExp,
      '${_tokenExpiry!.millisecondsSinceEpoch}',
    );
  }

  /// 携带会话的请求；401 时清空会话并自动重试一次。
  static Future<Response<dynamic>> _authed(
    String method,
    String path, {
    required String xh,
    Map<String, dynamic>? query,
    Object? data,
  }) async {
    Future<Response<dynamic>> once() async {
      await _ensureSession(xh);
      return _plain.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {'authorization': 'Bearer $_token'},
        ),
      );
    }

    try {
      return await once();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        _clearSession();
        return once();
      }
      rethrow;
    }
  }

  /// 是否为可查看统计数据的开发者账号
  static bool isOwner(String xh) => xh == ownerXh;

  /// 取当前会话令牌：校外隧道建连时使用，必要时自动完成设备认证。
  static Future<String> tokenFor(String xh) async {
    final id = xh.trim();
    if (id.isEmpty) throw StateError('缺少学号');
    await _ensureSession(id);
    final t = _token;
    if (t == null || t.isEmpty) throw StateError('会话不可用');
    return t;
  }

  /// 主动作废会话（隧道握手 401 时调用，下次会重新认证）。
  static void invalidateSession() => _clearSession();

  /// 上报一次该学号登录（去重由后端处理，失败静默）
  static Future<void> reportLogin(String xh) async {
    if (xh.trim().isEmpty) return;
    AppLog.d('统计', '上报登录学号 $xh');
    try {
      // 学号由会话令牌标识，不再重复放在请求体里外发
      final r = await _authed('POST', _postUrl, xh: xh.trim(), data: const {});
      AppLog.d(
          '统计', '上报成功 status=${r.statusCode} 返回=${r.data is Map ? r.data : ''}');
    } catch (e) {
      AppLog.e('统计', '上报失败：$e');
    }
  }

  /// 读取统计：count 为用户数，ids 为用户学号列表
  static Future<({int count, bool placeholder, List<String> ids})>
      fetchCount() async {
    if (_backendUrl.isNotEmpty) {
      try {
        final r = await _authed('GET', _backendUrl, xh: ownerXh);
        final d = r.data;
        if (d is Map && d['ids'] is List) {
          final ids = [
            for (final x in d['ids'] as List)
              if (x != null && x.toString().isNotEmpty) x.toString()
          ];
          AppLog.d('统计', '读取成功 count=${ids.length}');
          return (count: ids.length, placeholder: false, ids: ids);
        }
        AppLog.w('统计', '读取返回异常结构 $d');
      } catch (e) {
        AppLog.e('统计', '读取失败：$e');
      }
    }
    return (count: 0, placeholder: true, ids: const <String>[]);
  }

  /// 只按学号校验 APP 准入：会话令牌已绑定学号，请求体不携带任何登录态。
  /// 明确未放行时抛 [AccessDeniedException]；网络异常照常抛出，由调用方决定是否放行。
  static Future<bool> checkAllowed(String xh) async {
    final id = xh.trim();
    if (id.isEmpty) return false;
    if (id == ownerXh) return true;
    Response<dynamic> r;
    try {
      r = await _authed('GET', '$_backendUrl/gates', xh: id);
    } on DioException catch (e) {
      // 只有服务端明确返回业务错误码才算拒绝，其余按网络异常上抛
      final denied = e.response == null ? null : _deniedOf(e.response!);
      if (denied != null) throw denied;
      rethrow;
    }
    final denied = _deniedOf(r);
    if (denied != null) throw denied;
    final d = r.data;
    if (d is Map && d.containsKey(gateApp)) {
      if (d[gateApp] == true) return true;
      throw AccessDeniedException('not_allowed', '该学号未开通公网通道，请使用校园网登录或联系管理员');
    }
    // 结构不认识时不拦，交给后续真实请求判断
    return true;
  }

  /// 一次查询某学号的云端门控：
  /// 更新黑名单屏蔽 + APP 准入（默认禁止）。
  /// 网络失败时 APP 准入回退到上次成功结果（默认禁止），避免离线绕过。
  static Future<Map<String, bool>> fetchGates(String xh) async {
    final xh0 = xh.trim();
    final result = {
      gateUpdateBlock: false,
      gateApp: false,
    };
    if (xh0.isEmpty) return result;
    // 开发者恒有 APP 权限，且不受更新黑名单影响
    if (xh0 == ownerXh) {
      return {gateUpdateBlock: false, gateApp: true};
    }
    try {
      // 会话已绑定学号，不再用 URL 查询参数传学号（避免出现在访问日志里）
      final r = await _authed('GET', '$_backendUrl/gates', xh: xh0);
      final d = r.data;
      if (d is Map) {
        result[gateUpdateBlock] = d[gateUpdateBlock] == true;
        result[gateApp] = d[gateApp] == true;
        await _writeAppCache(xh0, result[gateApp]!);
        AppLog.d('风控', '学号$xh0 门控 $result');
        return result;
      }
    } catch (e) {
      AppLog.e('风控', '学号$xh0 门控查询失败：$e');
    }
    result[gateApp] = await _readAppCache(xh0) ?? false;
    return result;
  }

  /// 云端名单管理（仅管理员）：查询某功能某类型名单的学号列表。
  /// [block] 为 true 表示黑名单（更新），false 表示白名单（APP 准入）。
  static Future<({bool ok, List<String> list, String? error})>
      fetchPermList(String feature, {required bool block}) async {
    try {
      final r = await _authed(
        'GET',
        '$_backendUrl/perm',
        xh: ownerXh,
        query: {
          'feature': feature,
          'type': block ? 'block' : 'allow',
        },
      );
      final d = r.data;
      if (d is Map && d['ok'] == true && d['list'] is List) {
        return (
          ok: true,
          list: [for (final x in d['list'] as List) x.toString()],
          error: null,
        );
      }
      return (
        ok: false,
        list: const <String>[],
        error: d is Map ? '${d['error'] ?? '查询失败'}' : '查询失败',
      );
    } catch (e) {
      AppLog.e('风控', '名单查询失败：$e');
      return (ok: false, list: const <String>[], error: '$e');
    }
  }

  /// 运行设置（仅管理员）：设备自动换绑开关，默认开启。
  static Future<({bool ok, bool allowRebind, String? error})>
      fetchSettings() async {
    try {
      final r = await _authed('GET', '$_backendUrl/settings', xh: ownerXh);
      final d = r.data;
      if (d is Map && d['ok'] == true) {
        return (
          ok: true,
          allowRebind: d['allowRebind'] != false,
          error: null,
        );
      }
      return (ok: false, allowRebind: true, error: '读取失败');
    } catch (e) {
      AppLog.e('设置', '运行设置读取失败：$e');
      return (ok: false, allowRebind: true, error: '$e');
    }
  }

  /// 运行设置（仅管理员）：修改自动换绑开关。
  static Future<({bool ok, bool allowRebind, String? error})> setAllowRebind(
    bool allow,
  ) async {
    try {
      final r = await _authed(
        'POST',
        '$_backendUrl/settings',
        xh: ownerXh,
        data: {'allowRebind': allow},
      );
      final d = r.data;
      if (d is Map && d['ok'] == true) {
        AppLog.d('设置', '自动换绑 = ${d['allowRebind'] != false}');
        return (
          ok: true,
          allowRebind: d['allowRebind'] != false,
          error: null,
        );
      }
      return (ok: false, allowRebind: !allow, error: '保存失败');
    } catch (e) {
      AppLog.e('设置', '运行设置保存失败：$e');
      return (ok: false, allowRebind: !allow, error: '$e');
    }
  }

  /// 学号备注（仅管理员）：一次拉取全部备注，key 为完整学号。
  static Future<({bool ok, Map<String, String> notes, String? error})>
      fetchNotes() async {
    try {
      final r = await _authed('GET', '$_backendUrl/notes', xh: ownerXh);
      final d = r.data;
      if (d is Map && d['ok'] == true && d['notes'] is Map) {
        final notes = <String, String>{};
        (d['notes'] as Map).forEach((k, v) {
          if (v is String && v.trim().isNotEmpty) notes['$k'] = v.trim();
        });
        return (ok: true, notes: notes, error: null);
      }
      return (ok: true, notes: const <String, String>{}, error: null);
    } catch (e) {
      AppLog.e('统计', '备注读取失败：$e');
      return (ok: false, notes: const <String, String>{}, error: '$e');
    }
  }

  /// 学号备注（仅管理员）：写入或清空（空字符串表示删除）。
  static Future<bool> setNote(String xh, String note) async {
    try {
      final r = await _authed(
        'POST',
        '$_backendUrl/notes',
        xh: ownerXh,
        data: {'xh': xh.trim(), 'note': note.trim()},
      );
      final d = r.data;
      return d is Map && d['ok'] == true;
    } catch (e) {
      AppLog.e('统计', '备注保存失败：$e');
      return false;
    }
  }

  /// 云端名单管理（仅管理员）：对某功能某类型名单添加 / 移除学号。
  static Future<({bool ok, List<String> list, String? error})> managePermList({
    required String feature,
    required bool block,
    required String action,
    required String xh,
  }) async {
    if (!RegExp(r'^\d{6,20}$').hasMatch(xh)) {
      return (ok: false, list: const <String>[], error: '学号格式不正确');
    }
    try {
      final r = await _authed(
        'POST',
        '$_backendUrl/perm',
        xh: ownerXh,
        data: {
          'feature': feature,
          'type': block ? 'block' : 'allow',
          'action': action,
          'xh': xh.trim(),
        },
      );
      final d = r.data;
      if (d is Map && d['ok'] == true && d['list'] is List) {
        final list = [for (final x in d['list'] as List) x.toString()];
        AppLog.d('风控',
            '${block ? '黑名单' : '白名单'} $feature $action ${xh.trim()} 成功，当前共 ${list.length} 人');
        return (ok: true, list: list, error: null);
      }
      return (
        ok: false,
        list: const <String>[],
        error: d is Map ? '${d['error'] ?? '操作失败'}' : '操作失败',
      );
    } catch (e) {
      AppLog.e('风控', '名单操作失败：$e');
      return (ok: false, list: const <String>[], error: '$e');
    }
  }

  /// 云端下发公网通道入口（仅管理员）。逐个入口尝试，任一成功即止。
  /// [defaultUrl] 指定的入口会作为新客户端的默认入口。
  static Future<({bool ok, String? error})> saveTunnelEndpoints(
    List<Map<String, String>> endpoints, {
    String? defaultUrl,
  }) async {
    Object? last;
    for (final e in ServerConfig.ordered) {
      try {
        final r = await _authed(
          'POST',
          '${e.base}/tunnel/endpoints',
          xh: ownerXh,
          data: {
            'endpoints': endpoints,
            if (defaultUrl != null && defaultUrl.isNotEmpty)
              'default': defaultUrl,
          },
        );
        final d = r.data;
        if (d is Map && d['ok'] == true) {
          AppLog.d('通道', '入口配置已下发到 ${e.base}');
          return (ok: true, error: null);
        }
        return (
          ok: false,
          error: d is Map ? '${d['error'] ?? '保存失败'}' : '保存失败',
        );
      } catch (err) {
        last = err;
      }
    }
    return (ok: false, error: '$last');
  }
}

/// 设备密钥：私钥常驻 Android Keystore，Flutter 侧只能读取公钥和请求签名。
class DeviceAuth {
  DeviceAuth._();

  static const MethodChannel _ch = MethodChannel('cn.gdou.xiuhong/auth');
  static String? _publicKey;

  static Future<String> publicKey() async {
    final cached = _publicKey;
    if (cached != null) return cached;
    final value = await _ch.invokeMethod<String>('publicKey');
    _publicKey = value ?? '';
    return _publicKey!;
  }

  static Future<String> sign(String data) async {
    final value = await _ch.invokeMethod<String>('sign', {'data': data});
    return value ?? '';
  }
}

/// 读取使用人数与用户列表（placeholder=true 表示云端不可达，回退本地）
final usageCountProvider =
    FutureProvider<({int count, bool placeholder, List<String> ids})>((ref) {
  return UsageTracker.fetchCount();
});