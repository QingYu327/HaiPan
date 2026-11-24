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
  Future<void> logout() async {
    try {
      await client.dio.get('/xtgl/login_xxlc.html',
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s < 400,
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
