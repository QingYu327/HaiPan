import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'jw_client.dart';

/// 登录/鉴权失败（可读的中文文案）
class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// 会话操作：登录已由统一身份认证 WebView 完成，这里只负责登出。
class AuthApi {
  final JwClient client;
  AuthApi(this.client);

  /// 登出（本地清 Cookie + 服务端登出）
  ///
  /// 真实退出地址取自教务首页 `jwglxt_index.js`：
  /// `/logout?t=<毫秒时间戳>&login_type=`（本校部署里 `_systemPath` 为空）。
  /// 实测未登录访问返回 302 → `/xtgl/login_slogin.html`；
  /// 旧的 `/xtgl/login_xxlc.html` 只是普通业务页，有会话时返回 200 但不会注销，
  /// 服务端在线记录会残留，导致重新登录时提示重复登录。
  Future<void> logout() async {
    try {
      await client.dio.get('/logout',
          queryParameters: {
            't': DateTime.now().millisecondsSinceEpoch,
            'login_type': '',
          },
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 500,
          ));
    } catch (_) {
      // 服务端登出失败不阻塞本地登出
    }
    await client.clearCookies();
  }
}

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(jwClientProvider));
});
