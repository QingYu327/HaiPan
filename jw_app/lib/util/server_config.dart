import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'tls_pin.dart';

/// 一个公网入口（API + 隧道同源，换域名只改这里）。
class TunnelEndpoint {
  const TunnelEndpoint({
    required this.name,
    required this.base,
    this.isDefault = false,
  });

  final String name;

  /// 形如 https://api.example.com（不带路径和斜杠）
  final String base;

  /// 由云端下发的默认入口标记（仅管理端指定，本地缓存不参与判断）
  final bool isDefault;

  String get host => Uri.parse(base).host;

  /// wss://host/tunnel
  String get wsBase {
    final u = Uri.parse(base);
    return 'wss://${u.host}${u.hasPort ? ':${u.port}' : ''}/tunnel';
  }

  bool get valid => RegExp(r'^https://[A-Za-z0-9.\-]+(:\d+)?$').hasMatch(base);

  Map<String, dynamic> toJson() => {'name': name, 'base': base};

  factory TunnelEndpoint.fromJson(Map<String, dynamic> j) => TunnelEndpoint(
        name: (j['name'] ?? '').toString().trim(),
        base: (j['base'] ?? '').toString().trim().replaceFirst(
              RegExp(r'/+$'),
              '',
            ),
        isDefault: j['default'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is TunnelEndpoint && other.base == base;

  @override
  int get hashCode => base.hashCode;
}

/// 公网通道配置：本地缓存 + 云端下发 + 延迟探测。
///
/// 默认入口只是兜底；管理员在调试页维护入口列表后，客户端启动会从任意
/// 可达入口拉取配置并缓存，因此更换公网域名不再需要重新发版。
class ServerConfig {
  ServerConfig._();

  static const String defaultBase = 'https://api.example.com';
  static const _kList = 'server.endpoints';
  static const _kActive = 'server.active';
  static const _kAutoAt = 'server.auto_at';
  static const _kUserChoice = 'server.user_choice';

  /// 云端下发的默认入口（管理端统一调度；新装的启动入口不再写死在代码里）
  static String cloudDefault = '';

  /// 用户是否在通道页手动选过入口（手动选择优先于云端默认）
  static bool _userChoice = false;
  // 自动选路节流：10 分钟内不重复测速，避免频繁请求
  static const _autoIntervalMs = 10 * 60 * 1000;
  static bool _selecting = false;

  static List<TunnelEndpoint> endpoints = const [
    TunnelEndpoint(name: '主通道', base: defaultBase),
  ];

  static String activeBase = defaultBase;

  static TunnelEndpoint get active {
    for (final e in endpoints) {
      if (e.base == activeBase) return e;
    }
    return endpoints.first;
  }

  /// 当前入口优先，其余入口作为故障切换候选。
  static List<TunnelEndpoint> get ordered => [
        active,
        ...endpoints.where((e) => e.base != active.base),
      ];

  static String get apiBase => active.base;

  /// 启动时先读本地缓存，再异步从云端同步（失败静默）。
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kList);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .map((e) => TunnelEndpoint.fromJson(e as Map<String, dynamic>))
            .where((e) => e.valid && e.name.isNotEmpty)
            .toList();
        if (list.isNotEmpty) endpoints = list;
      }
      final saved = p.getString(_kActive) ?? '';
      activeBase = endpoints.any((e) => e.base == saved)
          ? saved
          : endpoints.first.base;
      _userChoice = p.getBool(_kUserChoice) ?? false;
    } catch (_) {
      // 缓存损坏时继续用默认入口
    }
    // 云端同步与自动选路都放后台，避免入口不可达时拖慢启动
    unawaited(refresh());
    unawaited(autoSelect());
  }

  /// 并行测速所有入口，自动切到最快的一条。
  ///
  /// 只有明显更优（当前不可达，或快 200ms 以上 / 快过 1.5 倍）才切换，
  /// 避免在延迟接近的入口之间来回抖动；手动切换的选择会尽量保留。
  static Future<void> autoSelect({bool force = false}) async {
    if (_selecting || endpoints.length < 2) return;
    _selecting = true;
    try {
      final p = await SharedPreferences.getInstance();
      final last = p.getInt(_kAutoAt) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!force && now - last < _autoIntervalMs) return;

      final results = await Future.wait([
        for (final e in endpoints) ping(e).then((ms) => (e, ms)),
      ]);
      final reachable = results.where((r) => r.$2 != null).toList()
        ..sort((a, b) => a.$2!.compareTo(b.$2!));
      if (reachable.isEmpty) return;

      final best = reachable.first;
      final current = results.firstWhere(
        (r) => r.$1.base == activeBase,
        orElse: () => (active, null),
      );
      final curMs = current.$2;
      // 云端指定的默认入口可达时保持不动，避免覆盖管理端的统一调度
      if (cloudDefault.isNotEmpty && activeBase == cloudDefault && curMs != null) {
        await p.setInt(_kAutoAt, now);
        return;
      }
      final bestMs = best.$2!;
      final better = curMs == null ||
          bestMs + 200 < curMs ||
          bestMs * 3 < curMs * 2;
      if (better && best.$1.base != activeBase) {
        await setActive(best.$1.base);
        AppLog.d(
          '通道',
          '自动选路：${best.$1.name} ${bestMs}ms 最优'
          '（原 ${current.$1.name} ${curMs ?? '不可达'}ms）',
        );
      }
      await p.setInt(_kAutoAt, now);
    } catch (_) {
      // 测速失败时保持当前入口
    } finally {
      _selecting = false;
    }
  }

  /// 从任意可达入口拉取最新配置；全部失败则保留本地配置。
  static Future<void> refresh() async {
    for (final e in ordered) {
      try {
        final data = await _getJson('${e.base}/tunnel/endpoints');
        final raw = data['endpoints'];
        if (raw is! List) continue;
        final list = <TunnelEndpoint>[];
        var defBase = '';
        for (final item in raw) {
          if (item is! Map) continue;
          final base = parseBase('${item['url'] ?? ''}');
          if (base == null) continue;
          final name = '${item['name'] ?? ''}'.trim();
          list.add(TunnelEndpoint(
            name: name.isEmpty ? Uri.parse(base).host : name,
            base: base,
            isDefault: item['default'] == true,
          ));
          if (item['default'] == true) defBase = base;
          if (list.length >= 6) break;
        }
        if (list.isEmpty) continue;
        endpoints = list;
        if (defBase.isNotEmpty) cloudDefault = defBase;
        if (!endpoints.any((x) => x.base == activeBase)) {
          activeBase = endpoints.first.base;
        }
        // 未手动选过入口时，采用云端指定的默认入口
        if (!_userChoice &&
            cloudDefault.isNotEmpty &&
            endpoints.any((e) => e.base == cloudDefault) &&
            activeBase != cloudDefault) {
          await setActive(cloudDefault);
        }
        await _persist();
        AppLog.d('通道', '入口配置已同步：${endpoints.length} 条');
        // 入口列表可能变化，按新列表重新选一次最快入口
        unawaited(autoSelect(force: true));
        return;
      } catch (_) {
        // 换下一个入口继续尝试
      }
    }
  }

  /// 探测入口可达性与延迟（毫秒，失败为 null）。
  static Future<int?> ping(TunnelEndpoint e) async {
    final sw = Stopwatch()..start();
    final client = TlsPin.client()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client
          .getUrl(Uri.parse('${e.base}/health'))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain<void>().timeout(const Duration(seconds: 6));
      // 只要能拿到 HTTP 响应就说明入口可达；5xx 视为异常
      if (res.statusCode >= 500) return null;
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> setActive(String base, {bool byUser = false}) async {
    if (!endpoints.any((e) => e.base == base)) return;
    activeBase = base;
    if (byUser) _userChoice = true;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kActive, base);
    if (byUser) await p.setBool(_kUserChoice, true);
    AppLog.d('通道', '当前入口切换为 $base');
  }

  /// 保存本地入口列表（云端下发成功后也会落到这里）。
  static Future<void> saveLocal(List<TunnelEndpoint> list) async {
    final seen = <String>{};
    final clean = <TunnelEndpoint>[];
    for (final e in list) {
      if (!e.valid || !seen.add(e.base)) continue;
      clean.add(e);
    }
    if (clean.isEmpty) return;
    endpoints = clean;
    if (!endpoints.any((e) => e.base == activeBase)) {
      activeBase = endpoints.first.base;
    }
    await _persist();
  }

  /// 把用户输入统一成 https://host[:port]。
  static String? parseBase(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    s = s
        .replaceFirst(RegExp(r'^wss://', caseSensitive: false), 'https://')
        .replaceFirst(RegExp(r'^ws://', caseSensitive: false), 'http://');
    final u = Uri.tryParse(s);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
    return 'https://${u.host}${u.hasPort ? ':${u.port}' : ''}';
  }

  static Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kList,
        jsonEncode([for (final e in endpoints) e.toJson()]),
      );
      await p.setString(_kActive, activeBase);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> _getJson(String url) async {
    final client = TlsPin.client()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final req =
          await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 5));
      final res = await req.close().timeout(const Duration(seconds: 6));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) return data;
      throw StateError('bad json');
    } finally {
      client.close(force: true);
    }
  }
}
