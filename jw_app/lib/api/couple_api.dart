import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/couple_models.dart';
import '../util/app_log.dart';

/// 情侣课表局域网配对与同步。
///
/// 不经过后端：发起方临时开一个本地 HTTP 服务，加入方通过 UDP 发现后
/// 用 6 位码 + X25519/AES-GCM 建立加密通道，互换课表快照。
/// 后续同步使用配对时保存的共享密钥，在同一局域网内直连。
class CoupleApi {
  CoupleApi._();

  static const _pairKeyPref = 'couple.lan.pair';
  static const _devicePref = 'couple.lan.device_id';
  static const _pairUdpPort = 39711;
  static const _syncUdpPort = 39712;
  static const _pairTtl = Duration(minutes: 10);

  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aes = AesGcm.with256bits();

  static HttpServer? _pairServer;
  static RawDatagramSocket? _pairUdp;
  static Timer? _pairTimer;
  static String? _pairCode;
  static String? _hostNonce;
  static String? _pairIp;
  static SimpleKeyPair? _hostKeyPair;
  static List<CoupleCourse> _hostCourses = const [];
  static DateTime? _pairExpires;

  static HttpServer? _syncServer;
  static RawDatagramSocket? _syncUdp;
  static List<CoupleCourse> _syncCourses = const [];
  static Future<void>? _syncStarting;

  static String? _deviceId;

  // ---------------- 发起配对 ----------------

  static Future<String> createCode(
    String xh,
    List<CoupleCourse> courses,
  ) async {
    await stopPairing();
    final code = (Random.secure().nextInt(900000) + 100000).toString();
    _pairCode = code;
    _hostNonce = _randomB64(18);
    _hostKeyPair = await _x25519.newKeyPair();
    _hostCourses = List.unmodifiable(courses);
    _pairExpires = DateTime.now().add(_pairTtl);
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _pairServer = server;
      server.listen(_handlePairRequest);
      _pairIp = await _localIp();
      final udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _pairUdpPort,
        reuseAddress: true,
      );
      _pairUdp = udp;
      udp.broadcastEnabled = true;
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = udp.receive();
        if (dg == null) return;
        if (utf8.decode(dg.data, allowMalformed: true) != 'HAIPAN-PAIR:$code') {
          return;
        }
        _replyPairProbe(udp, dg, code);
      });
      _pairTimer = Timer(_pairTtl, stopPairing);
      AppLog.d('局域网配对', '已发起配对，地址 ${_pairIp!}:${server.port}');
      return code;
    } catch (e) {
      AppLog.e('局域网配对', '启动失败：$e');
      await stopPairing();
      throw const CoupleException(
        'lan_start',
        '无法启动局域网配对，请检查网络后重试',
      );
    }
  }

  static Future<void> _replyPairProbe(
    RawDatagramSocket udp,
    Datagram dg,
    String code,
  ) async {
    final kp = _hostKeyPair;
    final nonce = _hostNonce;
    if (kp == null || nonce == null || _pairCode != code) return;
    try {
      final pub = await kp.extractPublicKey();
      final payload = jsonEncode({
        'ip': _pairIp,
        'port': _pairServer?.port ?? 0,
        'hostId': await _ensureDeviceId(),
        'pk': base64Encode(pub.bytes),
        'nonce': nonce,
      });
      udp.send(utf8.encode(payload), dg.address, dg.port);
    } catch (e) {
      AppLog.w('局域网配对', '回应发现请求失败：$e');
    }
  }

  static Future<void> _handlePairRequest(HttpRequest req) async {
    if (req.method != 'POST' || req.uri.path != '/pair') {
      await _json(req, 404, {'error': 'not_found'});
      return;
    }
    try {
      final body = await _readJson(req);
      final code = '${body['code'] ?? ''}';
      final expires = _pairExpires;
      if (_pairCode == null ||
          code != _pairCode ||
          expires == null ||
          expires.isBefore(DateTime.now())) {
        await _json(req, 403, {'error': 'invalid_code'});
        return;
      }
      final peerPk = base64Decode('${body['pk'] ?? ''}');
      final payload = base64Decode('${body['data'] ?? ''}');
      final peerId = '${body['deviceId'] ?? ''}';
      if (peerId.isEmpty || peerId == await _ensureDeviceId()) {
        await _json(req, 403, {'error': 'self_pair'});
        return;
      }
      final shared = await _x25519.sharedSecretKey(
        keyPair: _hostKeyPair!,
        remotePublicKey: SimplePublicKey(peerPk, type: KeyPairType.x25519),
      );
      final sessionKey = await _hkdf.deriveKey(
        secretKey: shared,
        nonce: utf8.encode('$code|$_hostNonce'),
        info: utf8.encode('haipan-lan-pair-v1'),
      );
      final clear = await _aes.decrypt(
        SecretBox.fromConcatenation(payload, nonceLength: 12, macLength: 16),
        secretKey: sessionKey,
      );
      final obj = jsonDecode(utf8.decode(clear));
      final map = obj is Map ? Map<String, dynamic>.from(obj) : <String, dynamic>{};
      final peerCourses = _parseCourses(map['courses']);
      final peerUpdatedAt = _int(map['updatedAt']);
      final pairKey = await _hkdf.deriveKey(
        secretKey: shared,
        nonce: utf8.encode(code),
        info: utf8.encode('haipan-lan-sync-v1'),
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final record = _LanPair(
        id: _pairIdFor(await _ensureDeviceId(), peerId),
        peerId: peerId,
        peerCourses: peerCourses,
        peerUpdatedAt: peerUpdatedAt > 0 ? peerUpdatedAt : now,
        myUpdatedAt: now,
        pairKey: base64Encode(await pairKey.extractBytes()),
      );
      await _savePair(record);
      _syncCourses = _hostCourses;

      final hostPayload = jsonEncode({
        'courses': [for (final c in _hostCourses) c.toJson()],
        'updatedAt': now,
      });
      final encrypted = await _aes.encrypt(
        utf8.encode(hostPayload),
        secretKey: sessionKey,
      );
      await _json(req, 200, {
        'ok': true,
        'data': base64Encode(encrypted.concatenation()),
      });
      AppLog.d('局域网配对', '配对成功');
      await stopPairing();
    } catch (e) {
      AppLog.e('局域网配对', '处理加入请求失败：$e');
      await _json(req, 400, {'error': 'pair_failed'});
    }
  }

  // ---------------- 加入配对 ----------------

  static Future<void> bind(
    String xh,
    String code,
    List<CoupleCourse> courses,
  ) async {
    final info = await _discoverPair(code);
    if (info == null) {
      throw const CoupleException(
        'not_found',
        '未找到配对设备，请确认双方在同一网络或热点下',
      );
    }
    final hostPk = base64Decode('${info['pk'] ?? ''}');
    final hostNonce = '${info['nonce'] ?? ''}';
    final ip = '${info['ip'] ?? ''}';
    final port = _int(info['port']);
    final hostId = '${info['hostId'] ?? ''}';
    if (hostPk.isEmpty || ip.isEmpty || port <= 0) {
      throw const CoupleException('bad_peer', '配对设备信息无效，请重试');
    }
    if (hostId == await _ensureDeviceId()) {
      throw const CoupleException('self_pair', '不能与自己配对');
    }

    final keyPair = await _x25519.newKeyPair();
    final pub = await keyPair.extractPublicKey();
    final shared = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(hostPk, type: KeyPairType.x25519),
    );
    final sessionKey = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('$code|$hostNonce'),
      info: utf8.encode('haipan-lan-pair-v1'),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = jsonEncode({
      'courses': [for (final c in courses) c.toJson()],
      'updatedAt': now,
    });
    final encrypted = await _aes.encrypt(
      utf8.encode(payload),
      secretKey: sessionKey,
    );

    final http = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await http.postUrl(Uri.parse('http://$ip:$port/pair'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'code': code,
        'deviceId': await _ensureDeviceId(),
        'pk': base64Encode(pub.bytes),
        'data': base64Encode(encrypted.concatenation()),
      }));
      final resp = await req.close();
      final raw = await utf8.decoder.bind(resp).join();
      final map = jsonDecode(raw);
      final body = map is Map ? Map<String, dynamic>.from(map) : <String, dynamic>{};
      if (resp.statusCode != 200 || body['ok'] != true) {
        throw const CoupleException('pair_failed', '配对失败，请重新生成配对码');
      }
      final clear = await _aes.decrypt(
        SecretBox.fromConcatenation(
          base64Decode('${body['data'] ?? ''}'),
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: sessionKey,
      );
      final obj = jsonDecode(utf8.decode(clear));
      final data = obj is Map ? Map<String, dynamic>.from(obj) : <String, dynamic>{};
      final pairKey = await _hkdf.deriveKey(
        secretKey: shared,
        nonce: utf8.encode(code),
        info: utf8.encode('haipan-lan-sync-v1'),
      );
      await _savePair(_LanPair(
        id: _pairIdFor(await _ensureDeviceId(), hostId),
        peerId: hostId,
        peerCourses: _parseCourses(data['courses']),
        peerUpdatedAt: _int(data['updatedAt']),
        myUpdatedAt: now,
        pairKey: base64Encode(await pairKey.extractBytes()),
      ));
      _syncCourses = List.unmodifiable(courses);
      AppLog.d('局域网配对', '已加入配对');
    } on CoupleException {
      rethrow;
    } catch (e) {
      AppLog.e('局域网配对', '加入失败：$e');
      throw const CoupleException(
        'pair_failed',
        '连接对方失败，请确认双方在同一网络后重试',
      );
    } finally {
      http.close(force: true);
    }
  }

  // ---------------- 状态与快照 ----------------

  static Future<CoupleStatus> status(String xh) async {
    final pair = await _loadPair();
    return CoupleStatus(
      paired: pair != null,
      myUpdatedAt: pair?.myUpdatedAt ?? 0,
      partnerUpdatedAt: pair?.peerUpdatedAt ?? 0,
    );
  }

  static Future<CouplePartner> partner(String xh) async {
    final pair = await _loadPair();
    return CouplePartner(
      courses: pair?.peerCourses ?? const [],
      updatedAt: pair?.peerUpdatedAt ?? 0,
    );
  }

  static Future<void> setMyCourses(List<CoupleCourse> courses) async {
    _syncCourses = List.unmodifiable(courses);
  }

  static Future<void> unbind(String xh) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_pairKeyPref);
    await stopSyncListener();
    await stopPairing();
  }

  // ---------------- 局域网同步 ----------------

  /// 页面展示已配对内容时调用：开启监听，等待对方发起同步。
  static Future<void> startSyncListener() async {
    if (_syncServer != null) return;
    final starting = _syncStarting;
    if (starting != null) return starting;
    final future = _startSyncListenerInner();
    _syncStarting = future;
    try {
      await future;
    } finally {
      _syncStarting = null;
    }
  }

  static Future<void> _startSyncListenerInner() async {
    final pair = await _loadPair();
    if (pair == null) return;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _syncServer = server;
      server.listen(_handleSyncRequest);
      final udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _syncUdpPort,
        reuseAddress: true,
        reusePort: true,
      );
      _syncUdp = udp;
      udp.broadcastEnabled = true;
      final ip = await _localIp();
      udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = udp.receive();
        if (dg == null) return;
        if (utf8.decode(dg.data, allowMalformed: true) !=
            'HAIPAN-SYNC:${pair.id}') {
          return;
        }
        final payload = jsonEncode({
          'ip': ip,
          'port': server.port,
          'deviceId': _deviceId,
        });
        udp.send(utf8.encode(payload), dg.address, dg.port);
      });
    } catch (e) {
      AppLog.w('局域网同步', '监听启动失败：$e');
    }
  }

  static Future<void> stopSyncListener() async {
    await _syncServer?.close(force: true);
    _syncServer = null;
    _syncUdp?.close();
    _syncUdp = null;
  }

  static Future<void> sync(String xh, List<CoupleCourse> courses) async {
    final pair = await _loadPair();
    if (pair == null) throw const CoupleException('not_paired', '尚未完成配对');
    _syncCourses = List.unmodifiable(courses);
    await startSyncListener();
    final info = await _discoverSync(pair.id);
    if (info == null) {
      throw const CoupleException(
        'no_peer',
        '未找到对方，请确认双方连接同一网络并打开情侣课表',
      );
    }
    final ip = '${info['ip'] ?? ''}';
    final port = _int(info['port']);
    if (ip.isEmpty || port <= 0) {
      throw const CoupleException('no_peer', '对方地址无效，请重试');
    }
    final key = SecretKeyData(base64Decode(pair.pairKey));
    final nonce = _randomB64(16);
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode('${pair.id}|$nonce'),
      secretKey: key,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = jsonEncode({
      'courses': [for (final c in courses) c.toJson()],
      'updatedAt': now,
    });
    final encrypted = await _aes.encrypt(utf8.encode(payload), secretKey: key);

    final http = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await http.postUrl(Uri.parse('http://$ip:$port/sync'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'pairId': pair.id,
        'nonce': nonce,
        'mac': base64Encode(mac.bytes),
        'data': base64Encode(encrypted.concatenation()),
      }));
      final resp = await req.close();
      final raw = await utf8.decoder.bind(resp).join();
      final map = jsonDecode(raw);
      final body = map is Map ? Map<String, dynamic>.from(map) : <String, dynamic>{};
      if (resp.statusCode != 200 || body['ok'] != true) {
        throw const CoupleException('sync_failed', '同步失败，请稍后重试');
      }
      final clear = await _aes.decrypt(
        SecretBox.fromConcatenation(
          base64Decode('${body['data'] ?? ''}'),
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: key,
      );
      final obj = jsonDecode(utf8.decode(clear));
      final data = obj is Map ? Map<String, dynamic>.from(obj) : <String, dynamic>{};
      await _savePair(pair.copyWith(
        peerCourses: _parseCourses(data['courses']),
        peerUpdatedAt: _int(data['updatedAt']),
        myUpdatedAt: now,
      ));
    } on CoupleException {
      rethrow;
    } catch (e) {
      AppLog.e('局域网同步', '同步失败：$e');
      throw const CoupleException('sync_failed', '同步失败，请确认双方在同一网络');
    } finally {
      http.close(force: true);
    }
  }

  static Future<void> _handleSyncRequest(HttpRequest req) async {
    if (req.method != 'POST' || req.uri.path != '/sync') {
      await _json(req, 404, {'error': 'not_found'});
      return;
    }
    try {
      final pair = await _loadPair();
      if (pair == null) {
        await _json(req, 403, {'error': 'not_paired'});
        return;
      }
      final body = await _readJson(req);
      if ('${body['pairId'] ?? ''}' != pair.id) {
        await _json(req, 403, {'error': 'bad_pair'});
        return;
      }
      final nonce = '${body['nonce'] ?? ''}';
      final key = SecretKeyData(base64Decode(pair.pairKey));
      final mac = await Hmac.sha256().calculateMac(
        utf8.encode('${pair.id}|$nonce'),
        secretKey: key,
      );
      if ('${body['mac'] ?? ''}' != base64Encode(mac.bytes)) {
        await _json(req, 403, {'error': 'bad_mac'});
        return;
      }
      final clear = await _aes.decrypt(
        SecretBox.fromConcatenation(
          base64Decode('${body['data'] ?? ''}'),
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: key,
      );
      final obj = jsonDecode(utf8.decode(clear));
      final data = obj is Map ? Map<String, dynamic>.from(obj) : <String, dynamic>{};
      final now = DateTime.now().millisecondsSinceEpoch;
      await _savePair(pair.copyWith(
        peerCourses: _parseCourses(data['courses']),
        peerUpdatedAt: _int(data['updatedAt']),
        myUpdatedAt: now,
      ));
      final payload = jsonEncode({
        'courses': [for (final c in _syncCourses) c.toJson()],
        'updatedAt': now,
      });
      final encrypted = await _aes.encrypt(utf8.encode(payload), secretKey: key);
      await _json(req, 200, {
        'ok': true,
        'data': base64Encode(encrypted.concatenation()),
      });
    } catch (e) {
      AppLog.e('局域网同步', '处理同步请求失败：$e');
      await _json(req, 400, {'error': 'sync_failed'});
    }
  }

  // ---------------- 发现 ----------------

  static Future<Map<String, dynamic>?> _discoverPair(String code) async {
    final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    udp.broadcastEnabled = true;
    final completer = Completer<Map<String, dynamic>?>();
    final sub = udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = udp.receive();
      if (dg == null) return;
      try {
        final decoded = jsonDecode(utf8.decode(dg.data));
        if (decoded is Map && decoded['pk'] != null && !completer.isCompleted) {
          completer.complete(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // 忽略非本协议广播
      }
    });
    for (final target in await _broadcastTargets()) {
      udp.send(utf8.encode('HAIPAN-PAIR:$code'), target, _pairUdpPort);
    }
    final result = await completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => null,
    );
    await sub.cancel();
    udp.close();
    return result;
  }

  static Future<Map<String, dynamic>?> _discoverSync(String pairId) async {
    final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    udp.broadcastEnabled = true;
    final completer = Completer<Map<String, dynamic>?>();
    final sub = udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = udp.receive();
      if (dg == null) return;
      try {
        final decoded = jsonDecode(utf8.decode(dg.data));
        if (decoded is Map && decoded['port'] != null && !completer.isCompleted) {
          completer.complete(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // 忽略非本协议广播
      }
    });
    for (final target in await _broadcastTargets()) {
      udp.send(utf8.encode('HAIPAN-SYNC:$pairId'), target, _syncUdpPort);
    }
    final result = await completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => null,
    );
    await sub.cancel();
    udp.close();
    return result;
  }

  // ---------------- 停止与清理 ----------------

  static Future<void> cancelPairing() => stopPairing();

  static Future<void> stopPairing() async {
    _pairTimer?.cancel();
    _pairTimer = null;
    await _pairServer?.close(force: true);
    _pairServer = null;
    _pairUdp?.close();
    _pairUdp = null;
    _pairCode = null;
    _hostNonce = null;
    _hostKeyPair = null;
    _hostCourses = const [];
    _pairExpires = null;
    _pairIp = null;
  }

  static Future<void> stopAll() async {
    await stopPairing();
    await stopSyncListener();
  }

  // ---------------- 存储 ----------------

  static Future<_LanPair?> _loadPair() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_pairKeyPref);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _LanPair.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      AppLog.w('情侣课表', '本地配对数据损坏：$e');
    }
    return null;
  }

  static Future<void> _savePair(_LanPair pair) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_pairKeyPref, jsonEncode(pair.toJson()));
  }

  static Future<String> _ensureDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_devicePref);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await p.setString(_devicePref, id);
    }
    _deviceId = id;
    return id;
  }

  static String _pairIdFor(String a, String b) {
    final list = [a, b]..sort();
    return '${list[0]}:${list[1]}';
  }

  static List<CoupleCourse> _parseCourses(Object? raw) {
    final out = <CoupleCourse>[];
    if (raw is List) {
      for (final x in raw) {
        if (x is Map) {
          out.add(CoupleCourse.fromJson(Map<String, dynamic>.from(x)));
        }
      }
    }
    return out;
  }

  static Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
    final ip = await _localIp();
    final parts = ip.split('.');
    if (parts.length == 4) {
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}.255';
      if (subnet != ip) targets.add(InternetAddress(subnet));
    }
    return targets;
  }

  static Future<String> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final name in ['wlan0', 'ap0', 'wlan1', 'eth0']) {
        for (final it in interfaces) {
          if (it.name != name) continue;
          for (final address in it.addresses) {
            if (!address.isLoopback && !address.address.startsWith('169.254')) {
              return address.address;
            }
          }
        }
      }
      for (final it in interfaces) {
        for (final address in it.addresses) {
          if (!address.isLoopback && !address.address.startsWith('169.254')) {
            return address.address;
          }
        }
      }
    } catch (_) {
      // 无网络接口时退回本机地址
    }
    return '127.0.0.1';
  }

  static String _randomB64(int bytes) {
    final seed = Random.secure();
    final data = List<int>.generate(bytes, (_) => seed.nextInt(256));
    return base64Encode(data);
  }

  static int _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  }

  static Future<void> _json(
    HttpRequest req,
    int status,
    Map<String, dynamic> body,
  ) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }
}

class _LanPair {
  final String id;
  final String peerId;
  final List<CoupleCourse> peerCourses;
  final int peerUpdatedAt;
  final int myUpdatedAt;
  final String pairKey;

  const _LanPair({
    required this.id,
    required this.peerId,
    required this.peerCourses,
    required this.peerUpdatedAt,
    required this.myUpdatedAt,
    required this.pairKey,
  });

  _LanPair copyWith({
    List<CoupleCourse>? peerCourses,
    int? peerUpdatedAt,
    int? myUpdatedAt,
  }) =>
      _LanPair(
        id: id,
        peerId: peerId,
        peerCourses: peerCourses ?? this.peerCourses,
        peerUpdatedAt: peerUpdatedAt ?? this.peerUpdatedAt,
        myUpdatedAt: myUpdatedAt ?? this.myUpdatedAt,
        pairKey: pairKey,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'peerId': peerId,
        'peerCourses': [for (final c in peerCourses) c.toJson()],
        'peerUpdatedAt': peerUpdatedAt,
        'myUpdatedAt': myUpdatedAt,
        'pairKey': pairKey,
      };

  static _LanPair fromJson(Map<String, dynamic> json) => _LanPair(
        id: '${json['id'] ?? ''}',
        peerId: '${json['peerId'] ?? ''}',
        peerCourses: [
          for (final x in (json['peerCourses'] as List? ?? const []))
            if (x is Map) CoupleCourse.fromJson(Map<String, dynamic>.from(x)),
        ],
        peerUpdatedAt: _int(json['peerUpdatedAt']),
        myUpdatedAt: _int(json['myUpdatedAt']),
        pairKey: '${json['pairKey'] ?? ''}',
      );

  static int _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse('$v') ?? 0;
}
