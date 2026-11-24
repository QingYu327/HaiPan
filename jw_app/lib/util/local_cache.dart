import 'package:shared_preferences/shared_preferences.dart';

/// 后台自动刷新的最小间隔：缓存仍在新鲜期内时，进页面只读缓存不发请求；
/// 下拉刷新、错误重试等手动操作始终强制走在线。
const Duration kCacheFreshTtl = Duration(minutes: 10);

/// 轻量本地缓存：用于数据离线可用（课表等）
class LocalCache {
  LocalCache._();

  static const _tsPrefix = 'cache_ts_';

  static Future<String?> read(String key) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(key);
  }

  static Future<void> write(String key, String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
    await p.setInt(
      '$_tsPrefix$key',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 缓存是否仍在新鲜期内；没有时间戳（老版本缓存）按过期处理
  static Future<bool> isFresh(
    String key, [
    Duration ttl = kCacheFreshTtl,
  ]) async {
    final p = await SharedPreferences.getInstance();
    final ts = p.getInt('$_tsPrefix$key');
    if (ts == null) return false;
    return DateTime.now().millisecondsSinceEpoch - ts < ttl.inMilliseconds;
  }

  static Future<void> remove(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(key);
    await p.remove('$_tsPrefix$key');
  }

  /// 按条件批量清理（如手动刷新后让成绩分项明细失效）
  static Future<void> removeWhere(bool Function(String key) test) async {
    final p = await SharedPreferences.getInstance();
    final keys = p
        .getKeys()
        .where((k) => !k.startsWith(_tsPrefix) && test(k))
        .toList();
    for (final k in keys) {
      await p.remove(k);
      await p.remove('$_tsPrefix$k');
    }
  }

  /// 清空全部业务数据缓存（切换账号时避免上一个账号的数据被展示）
  static Future<void> clearData() async {
    final p = await SharedPreferences.getInstance();
    final keys = p
        .getKeys()
        .where((k) => k.startsWith('cache_') && !k.startsWith(_tsPrefix))
        .toList();
    for (final k in keys) {
      await p.remove(k);
      await p.remove('$_tsPrefix$k');
    }
  }
}