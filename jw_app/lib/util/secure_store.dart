import 'package:flutter/services.dart';

/// Keystore 安全存储（对应原生 MainActivity 的 cn.gdou.xiuhong/secure 通道）。
/// 用于记住账号/密码等敏感信息（AES-256-GCM 加密后落盘，非明文）。
class SecureStore {
  SecureStore._();

  static const _ch = MethodChannel('cn.gdou.xiuhong/secure');

  static Future<void> put(String key, String value) async {
    try {
      await _ch.invokeMethod('put', {'key': key, 'value': value});
    } catch (_) {
      // 写入失败静默（无 Keystore 或非 Android 环境）
    }
  }

  static Future<String?> get(String key) async {
    try {
      return await _ch.invokeMethod<String>('get', {'key': key});
    } catch (_) {
      return null;
    }
  }

  static Future<void> del(String key) async {
    try {
      await _ch.invokeMethod('del', {'key': key});
    } catch (_) {}
  }
}