import 'package:flutter/services.dart';

/// 让系统 WebView 走本地隧道代理（AndroidX WebKit ProxyController）。
/// 只影响 WebView，不改变系统或其它应用的网络设置。
class WebViewProxy {
  WebViewProxy._();

  static const _channel = MethodChannel('cn.gdou.xiuhong/proxy');

  static Future<void> set(int port) async {
    try {
      await _channel.invokeMethod('setProxy', {
        'host': '127.0.0.1',
        'port': port,
      });
    } on MissingPluginException {
      // 非 Android 平台忽略
    } catch (_) {}
  }
}
