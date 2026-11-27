import 'package:flutter/services.dart';

/// 安装包自身的版本信息。
///
/// 版本号和构建号以原生 `appInfo` 读取的 versionName / versionCode 为准，
/// 不再在 Dart 源码里手写常量，避免“源码写 4144、安装包实际 4143”
/// 导致已经是最新版却提示更新。
class BuildInfo {
  BuildInfo._();

  static const MethodChannel _channel = MethodChannel('cn.gdou.xiuhong/app');

  /// 原生通道不可用时的兜底值；可通过
  /// `--dart-define=APP_VERSION=1.0.2 --dart-define=APP_BUILD=10` 覆盖。
  static const String _fallbackVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.2');
  static const int _fallbackBuild =
      int.fromEnvironment('APP_BUILD', defaultValue: 10);

  static String _version = _fallbackVersion;
  static int _build = _fallbackBuild;
  static bool _loaded = false;
  static Future<void>? _loading;

  static String get version => _version;
  static int get build => _build;
  static String get label => '$_version+$_build';

  /// 只读取一次；并发调用复用同一个 Future。
  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('appInfo');
      // versionName 在部分构建参数下可能带 +构建号，只保留主版本段
      final version = '${info?['version'] ?? ''}'.trim().split('+').first;
      final build = int.tryParse('${info?['build'] ?? ''}');
      if (version.isNotEmpty) _version = version;
      if (build != null && build > 0) _build = build;
    } catch (_) {
      // 非 Android 或通道不可用时保留兜底值
    } finally {
      _loaded = true;
      _loading = null;
    }
  }
}
