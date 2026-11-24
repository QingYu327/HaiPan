import 'package:flutter/services.dart';

/// 当前网络类型（Android 原生读取 ConnectivityManager）
class NetworkInfo {
  NetworkInfo._();

  static const _channel = MethodChannel('cn.gdou.xiuhong/net');

  /// 是否仅移动数据（没有 Wi-Fi/有线）。
  /// 取不到网络信息时返回 false，让调用方按“可直连”处理。
  static Future<bool> isCellularOnly() async {
    try {
      final type = await _channel.invokeMethod<String>('networkType');
      return type == 'cellular';
    } catch (_) {
      return false;
    }
  }
}
