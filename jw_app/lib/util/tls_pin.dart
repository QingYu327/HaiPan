import 'dart:io';

import 'package:pointycastle/digests/sha256.dart';

/// 自签入口的证书指纹固定。
///
/// 国内直连走「公网 IP + 高位端口」，没有域名就无法申请受信任证书，
/// 因此服务端用自签证书，客户端只认固定指纹（SHA-256，DER 编码）：
/// 不依赖系统 CA，也能挡住中间人换证书。服务端换证书后必须重新发版。
class TlsPin {
  TlsPin._();

  /// 服务端 data/tls/cert.pem 的 SHA-256 指纹（小写十六进制）。
  ///
  /// 有效期至 2036-11-21，轮换证书时同步更新并提升版本号。
  static const Set<String> fingerprints = {
    '7392fdcb488a6e99fe1efa6cc5221e3ab2ed60b1f4b4f446429c4df30257e877',
  };

  /// 供 HttpClient.badCertificateCallback 使用：返回 true 才继续握手。
  static bool check(X509Certificate cert, String host, int port) {
    try {
      final digest = SHA256Digest().process(cert.der);
      final hex = StringBuffer();
      for (final b in digest) {
        hex.write(b.toRadixString(16).padLeft(2, '0'));
      }
      return fingerprints.contains(hex.toString());
    } catch (_) {
      // 证书解析失败一律拒绝
      return false;
    }
  }

  /// 带指纹校验的 HttpClient（健康检查、入口同步、认证请求共用）。
  static HttpClient client() =>
      HttpClient()..badCertificateCallback = check;

  static HttpClient? _shared;

  /// 隧道 WebSocket 共用长连接客户端：WebSocket 存活期间不能关闭它。
  static HttpClient shared() => _shared ??= client();
}
