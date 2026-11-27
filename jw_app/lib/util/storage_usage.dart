import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地占用分类：设置入口与「本地占用」详情页共用同一套统计口径，
/// 避免入口显示的值和详情页总数不一致。
class StorageBucket {
  final String name;
  final int bytes;
  const StorageBucket(this.name, this.bytes);
}

class StorageReport {
  final List<StorageBucket> buckets;
  final int total;
  const StorageReport(this.buckets, this.total);
}

/// 扫描应用私有目录 + SharedPreferences，按用途细分占用。
///
/// 分类尽量贴近用户能理解的对象：
/// 课表缓存 / 成绩考试缓存 / 设置与配对 / 登录会话 / 日志 /
/// 背景图片 / 网页与系统缓存 / 其他文件。
Future<StorageReport> computeStorageUsage() async {
  // 要扫描的根目录：Android 用包目录（覆盖 files / cache / code_cache /
  // app_webview / shared_prefs 等），其他平台逐个加入支持目录。
  final roots = <Directory>[];
  void addRoot(Directory? d) {
    if (d == null) return;
    final p = d.path;
    final sep = Platform.pathSeparator;
    if (roots.any((r) => p == r.path || p.startsWith('${r.path}$sep'))) {
      return;
    }
    roots.removeWhere((r) => r.path.startsWith('$p$sep'));
    roots.add(d);
  }

  try {
    final support = await getApplicationSupportDirectory();
    if (Platform.isAndroid || Platform.isIOS) addRoot(support.parent);
    addRoot(support);
  } catch (_) {}
  try {
    addRoot(await getApplicationDocumentsDirectory());
  } catch (_) {}
  try {
    addRoot(await getApplicationCacheDirectory());
  } catch (_) {}
  try {
    addRoot(await getTemporaryDirectory());
  } catch (_) {}

  int logs = 0;
  int images = 0;
  int session = 0;
  int web = 0;
  int system = 0;
  int other = 0;
  int prefsBytes = 0;

  for (final root in roots) {
    try {
      await for (final f in root.list(recursive: true, followLinks: false)) {
        if (f is! File) continue;
        int len;
        try {
          len = await f.length();
        } catch (_) {
          continue;
        }
        final path = f.path.replaceAll('\\', '/');
        final name = path.split('/').last;
        if (path.contains('/shared_prefs/')) {
          // SharedPreferences 内部按键前缀再细分，先记录文件总大小
          prefsBytes += len;
        } else if (name.toLowerCase().endsWith('.log') ||
            name.startsWith('haipan-feedback-')) {
          logs += len;
        } else if (path.contains('/files/backgrounds/')) {
          images += len;
        } else if (path.contains('/cookies/') || name == 'cookies') {
          session += len;
        } else if (path.contains('/app_webview/') ||
            path.contains('/.webview/') ||
            path.contains('/webview/')) {
          web += len;
        } else if (path.contains('/cache/') ||
            path.contains('/code_cache/')) {
          system += len;
        } else {
          other += len;
        }
      }
    } catch (_) {}
  }

  // SharedPreferences 按键前缀细分；文件头/转义开销归入「设置与配对」。
  int timetable = 0;
  int scores = 0;
  int settingsEst = 0;
  try {
    final p = await SharedPreferences.getInstance();
    for (final k in p.getKeys()) {
      final size = k.length + _valueBytes(p.get(k));
      if (k.startsWith('cache_timetable_')) {
        timetable += size;
      } else if (k.startsWith('cache_')) {
        scores += size;
      } else {
        settingsEst += size;
      }
    }
  } catch (_) {}

  final accounted = timetable + scores + settingsEst;
  int settings;
  if (prefsBytes <= 0) {
    // 拿不到落盘文件时不用内存估算值，避免总数虚高
    timetable = 0;
    scores = 0;
    settings = 0;
  } else if (accounted > prefsBytes) {
    final ratio = prefsBytes / accounted;
    timetable = (timetable * ratio).floor();
    scores = (scores * ratio).floor();
    settings = prefsBytes - timetable - scores;
  } else {
    settings = settingsEst + (prefsBytes - accounted);
  }

  final buckets = <StorageBucket>[
    if (timetable > 0) StorageBucket('课表缓存', timetable),
    if (scores > 0) StorageBucket('成绩/考试缓存', scores),
    if (settings > 0) StorageBucket('设置与配对', settings),
    if (session > 0) StorageBucket('登录会话', session),
    if (logs > 0) StorageBucket('日志', logs),
    if (images > 0) StorageBucket('背景图片', images),
    if (web > 0) StorageBucket('网页数据', web),
    if (system > 0) StorageBucket('系统缓存', system),
    if (other > 0) StorageBucket('其他文件', other),
  ];
  return StorageReport(buckets, buckets.fold(0, (s, b) => s + b.bytes));
}

/// SharedPreferences 值的 UTF-8 字节数近似（中文按真实字节计，避免低估）
int _valueBytes(Object? v) {
  if (v == null) return 0;
  if (v is String) return utf8.encode(v).length;
  if (v is List<String>) {
    return v.fold<int>(0, (s, e) => s + utf8.encode(e).length);
  }
  return v.toString().length;
}
