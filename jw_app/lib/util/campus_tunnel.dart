import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/jw_client.dart';
import '../api/usage_api.dart';
import '../providers/session_provider.dart';
import 'app_log.dart';
import 'network_info.dart';
import 'server_config.dart';
import 'tls_pin.dart';
import 'webview_proxy.dart';

/// 隧道 WebSocket 子协议：国内直连端口强制要求，Cloudflare 通道原样回显。
const String wsProtocol = 'haipan-v1';

/// 校外教务通道：本地 CONNECT 代理 → WebSocket → 校园网后端 → jw/authserver。
///
/// 手机在公网时，WebView 和 Dio 的教务请求先到 127.0.0.1 的本地代理，
/// 再由这里经 Cloudflare Tunnel 送到飞牛（校园网内），由后端原样转发 TCP，
/// 因此统一认证的验证码、跳转和 Cookie 全部保持原样。
class CampusTunnel {
  CampusTunnel(this._xh);

  final String Function() _xh;

  /// 会话里还没有学号时（校外首次登录）由用户填写，仅用于设备认证。
  String _fallbackXh = '';

  void setFallbackXh(String xh) => _fallbackXh = xh.trim();

  String get _currentXh {
    final xh = _xh().trim();
    return xh.isNotEmpty ? xh : _fallbackXh;
  }

  ServerSocket? _server;
  final Set<Socket> _sockets = {};
  final Set<WebSocket> _ws = {};
  Future<void>? _startFuture;
  int? _port;

  /// 复用通道：一条 WebSocket 承载多条教务 TCP 流，省掉每次 CONNECT 的握手。
  late final _MuxTunnel _mux = _MuxTunnel(_connectMux);

  bool get isRunning => _server != null;
  int? get port => _port;

  /// 本次自适应是否判定为「需要公网通道」。
  /// 校园网直连为 false —— 公网准入名单只对通道用户生效。
  bool _public = false;
  bool get isPublicNetwork => _public || isRunning;

  /// 仅放行教务相关域名，和后端白名单保持一致。
  static const Map<String, Set<int>> _targets = {
    'jw.gdou.edu.cn': {80, 443},
    'authserver.gdou.edu.cn': {80, 443},
  };

  /// 网络自适应：校内直连教务即可，校外（直连不通）自动启用通道，
  /// 并把 Dio 与 WebView 的教务请求切到本地代理。返回是否启用了通道。
  ///
  /// [xh] 用于启动期（此时会话 Provider 可能仍在构建），避免反向读取会话。
  /// [warm] 是否顺手预热：登录页自己会立刻发真实请求，此时预热只会抢隧道带宽。
  Future<bool> adapt(JwClient client, {String? xh, bool warm = true}) async {
    // 等客户端读完持久化的通道模式，避免刚启动时误建隧道
    await client.ready;
    // 官方 WebVPN 通道下所有请求都走 wfw 反代，不需要本地隧道
    if (client.wfwMode) {
      _public = false;
      return false;
    }
    final known = (xh ?? '').trim();
    if (known.isNotEmpty) _fallbackXh = known;
    // 没有学号无法做设备认证，等登录页补录后再启用
    if (_fallbackXh.isEmpty) {
      _public = false;
      return false;
    }
    if (isRunning) {
      _public = true;
      client.setProxyPort(_port!);
      await WebViewProxy.set(_port!);
      // 已有通道时顺手预热一次（30s 内不重复），省掉后续首次握手
      if (warm) unawaited(client.warmUp());
      return true;
    }
    // 移动数据下直连校园网必然失败，直接建通道，省掉每次 4s 的探测等待；
    // Wi-Fi 仍先试直连，校内网络可以零通道使用。
    if (await NetworkInfo.isCellularOnly()) {
      _public = true;
      final p = await ensureStarted();
      client.setProxyPort(p, force: true);
      await WebViewProxy.set(p);
      AppLog.d('通道', '移动数据环境，直接启用通道 :$p');
      if (warm) unawaited(client.warmUp());
      return true;
    }
    if (await _directReachable()) {
      _public = false;
      return false;
    }
    _public = true;
    final p = await ensureStarted();
    // 新建通道后强制换连接池：旧端口留下的 socket 已不可用
    client.setProxyPort(p, force: true);
    await WebViewProxy.set(p);
    AppLog.d('通道', '校外环境，已自动启用通道 :$p');
    // 提前建好 TCP + TLS + 隧道 WebSocket，页面真正请求时直接复用连接
    if (warm) unawaited(client.warmUp());
    return true;
  }

  /// 校内网络下教务 443 可直连；校外被拒或超时即视为需要通道。
  ///
  /// 只缓存「校外」结论 10 分钟：校外时这个探测必然等满 4s 超时，
  /// 而 adapt 会被启动流程和连接失败兜底反复调用；校内直连很快，无需缓存。
  /// 缺点是从校外换回校内时最多多用 10 分钟通道（功能不受影响）。
  Future<bool> _directReachable() async {
    final at = _directAt;
    if (at != null &&
        _directOk == false &&
        DateTime.now().difference(at) < _directTtl) {
      return false;
    }
    // 合并并发探测：启动期多处同时 adapt 时，不要各等 4s
    final pending = _directProbe;
    if (pending != null) return pending;
    final probe = _probeDirect();
    _directProbe = probe;
    try {
      return await probe;
    } finally {
      if (identical(_directProbe, probe)) _directProbe = null;
    }
  }

  Future<bool> _probeDirect() async {
    bool ok;
    try {
      final s = await Socket.connect(
        'jw.gdou.edu.cn',
        443,
        // 校内到教务是同网段握手，正常在 100ms 内完成；1.8s 足够覆盖弱 Wi-Fi，
        // 校外则尽快失败切通道（原来 4s 让每次冷启动最多白等 4 秒）。
        timeout: const Duration(milliseconds: 1800),
      );
      s.destroy();
      ok = true;
    } catch (_) {
      ok = false;
    }
    _directOk = ok;
    _directAt = DateTime.now();
    return ok;
  }

  static const Duration _directTtl = Duration(minutes: 10);
  bool? _directOk;
  DateTime? _directAt;
  Future<bool>? _directProbe;

  /// 现场复核校内直连（绕过 10 分钟缓存）。
  /// 用于「被判定为校外、但准入拒绝」时纠偏：确实在校内就应当放行。
  Future<bool> probeCampusNow() => _probeDirect();

  /// 启动本地代理（重复调用返回同一端口）。
  Future<int> ensureStarted() async {
    if (_server != null) return _port!;
    final pending = _startFuture;
    if (pending != null) {
      await pending;
      return _port!;
    }
    final f = _start();
    _startFuture = f;
    try {
      await f;
    } finally {
      if (identical(_startFuture, f)) _startFuture = null;
    }
    return _port!;
  }

  Future<void> _start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _port = server.port;
    AppLog.d('通道', '本地代理已启动 127.0.0.1:${server.port}');
    server.listen(
      _accept,
      onError: (Object e) {
        AppLog.e('通道', '本地代理异常：$e');
        stop();
      },
    );
  }

  void _accept(Socket socket) {
    _sockets.add(socket);
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    final header = <int>[];
    final pending = <int>[];
    _Tunnel? tunnel;
    var starting = false;
    var dead = false;

    late final StreamSubscription<Uint8List> sub;
    // Socket 流只能订阅一次：头解析、隧道数据必须共用这一个监听器
    sub = socket.listen(
      (data) {
        if (dead) return;
        final t = tunnel;
        if (t != null) {
          t.add(data);
          return;
        }
        if (starting) {
          // 建连期间被暂停的少量数据，等隧道就绪后再补发
          pending.addAll(data);
          return;
        }
        header.addAll(data);
        if (header.length > 16384) {
          dead = true;
          socket.destroy();
          return;
        }
        final end = _headerEnd(header);
        if (end < 0) return;
        starting = true;
        sub.pause();
        final head = String.fromCharCodes(header.sublist(0, end));
        final rest = header.sublist(end + 4);
        _startTunnel(socket, head, rest)
            .then((t) {
              if (dead) {
                t?.close();
                return;
              }
              if (t == null) {
                dead = true;
                _sockets.remove(socket);
                sub.cancel();
                _closeQuietly(socket);
                return;
              }
              tunnel = t;
              if (pending.isNotEmpty) {
                t.add(pending);
                pending.clear();
              }
              try {
                sub.resume();
              } catch (_) {
                t.close();
              }
            })
            .catchError((Object e) {
              AppLog.e('通道', '隧道异常：$e');
              dead = true;
              _sockets.remove(socket);
              sub.cancel();
              _closeQuietly(socket);
            });
      },
      onError: (Object _) {
        dead = true;
        _sockets.remove(socket);
        tunnel?.close();
        socket.destroy();
      },
      onDone: () {
        dead = true;
        _sockets.remove(socket);
        tunnel?.close();
        // 区分「谁先关」：这里是 App 自己断开；对端断开会在上游关闭流里打印
        AppLog.d('通道', '本端连接关闭（App 断开）');
      },
    );
  }

  int _headerEnd(List<int> b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  /// 解析代理请求并建好隧道；失败时已回写错误响应并返回 null。
  Future<_Tunnel?> _startTunnel(
    Socket socket,
    String head,
    List<int> rest,
  ) async {
    final lines = head.split('\r\n');
    final line = lines.first;
    final sw = Stopwatch()..start();
    String host;
    int targetPort;
    var needAck = false;
    var initial = rest;

    final connect = RegExp(
      r'^CONNECT\s+([^:\s]+):(\d+)\s+HTTP/1\.[01]$',
      caseSensitive: false,
    ).firstMatch(line);
    if (connect != null) {
      host = connect.group(1)!.toLowerCase();
      targetPort = int.parse(connect.group(2)!);
      needAck = true;
    } else {
      // 明文 http:// 请求：WebView 走代理时发送的是绝对 URI，
      // 需要还原成源站请求行再经隧道转发。
      final m = RegExp(
        r'^([A-Z]+)\s+https?://([^/\s:]+)(?::(\d+))?([^\s]*)\s+(HTTP/1\.[01])$',
        caseSensitive: false,
      ).firstMatch(line);
      if (m == null) {
        socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
        return null;
      }
      host = m.group(2)!.toLowerCase();
      targetPort = int.tryParse(m.group(3) ?? '') ?? 80;
      final path = (m.group(4) ?? '').isEmpty ? '/' : m.group(4)!;
      final rebuilt = <String>[
        '${m.group(1)!.toUpperCase()} $path ${m.group(5)}',
        ...lines.skip(1),
      ].join('\r\n');
      initial = <int>[...utf8.encode('$rebuilt\r\n\r\n'), ...rest];
    }

    if (!(_targets[host]?.contains(targetPort) ?? false)) {
      AppLog.w('通道', '拒绝非教务目标 $host:$targetPort');
      socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
      return null;
    }

    // 优先走复用通道：多条教务 TCP 流共用一条 WebSocket。
    // 复用不可用时自动回退到「一条连接一条隧道」的旧模式。
    final muxId = _mux.alloc();
    final muxOk = await _mux.open(
      muxId,
      host,
      targetPort,
      onData: (data) {
        try {
          socket.add(data);
        } catch (_) {}
      },
      onClose: () => _closeQuietly(socket),
    );
    if (muxOk) {
      if (needAck) socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
      if (initial.isNotEmpty) _mux.send(muxId, initial);
      AppLog.d(
        '通道',
        '复用建立 $host:$targetPort #$muxId（${sw.elapsedMilliseconds}ms）',
      );
      return _Tunnel(
        add: (data) => _mux.send(muxId, data),
        close: () => _mux.close(muxId),
      );
    }

    WebSocket ws;
    try {
      ws = await _open(host, targetPort);
    } catch (e) {
      AppLog.e('通道', '隧道建连失败 $host:$targetPort：$e');
      socket.write('HTTP/1.1 502 Bad Gateway\r\n\r\n');
      return null;
    }

    _ws.add(ws);
    if (needAck) socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    if (initial.isNotEmpty) ws.add(initial);

    var alive = true;
    ws.listen(
      (data) {
        if (!alive) return;
        try {
          if (data is List<int>) {
            socket.add(data);
          } else if (data is String) {
            socket.add(utf8.encode(data));
          }
        } catch (_) {
          alive = false;
        }
      },
      onDone: () {
        alive = false;
        _ws.remove(ws);
        _closeQuietly(socket);
      },
      onError: (Object _) {
        alive = false;
        _ws.remove(ws);
        _closeQuietly(socket);
      },
    );
    AppLog.d('通道', '已建立 $host:$targetPort');
    return _Tunnel(
      add: (data) {
        if (ws.readyState == WebSocket.open) ws.add(data);
      },
      close: () {
        _ws.remove(ws);
        try {
          ws.close();
        } catch (_) {}
      },
    );
  }

  /// 先让已排队的响应刷出再断开；直接 destroy 会丢掉「响应后立即关闭」的末尾数据。
  void _closeQuietly(Socket socket) {
    try {
      socket.flush().timeout(const Duration(seconds: 2)).whenComplete(() {
        try {
          socket.destroy();
        } catch (_) {}
      });
    } catch (_) {
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  Future<WebSocket> _open(String host, int port) async {
    Object? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final token = await UsageTracker.tokenFor(_currentXh);
        // 依次尝试当前入口与备用入口：任何一条可达即可建隧道
        for (final e in ServerConfig.ordered) {
          try {
            final ws = await WebSocket.connect(
              '${e.wsBase}?host=$host&port=$port',
              headers: {'authorization': 'Bearer $token'},
              protocols: const [wsProtocol],
              customClient: TlsPin.shared(),
            ).timeout(const Duration(seconds: 8));
            if (e.base != ServerConfig.activeBase) {
              AppLog.w('通道', '当前入口不可用，已切换到 ${e.base}');
              await ServerConfig.setActive(e.base);
            }
            return ws;
          } catch (err) {
            last = err;
          }
        }
      } catch (e) {
        last = e;
      }
      // 首次全部失败可能是会话过期，作废后重新认证再试一次
      if (attempt == 0) UsageTracker.invalidateSession();
    }
    throw StateError('$last');
  }

  /// 复用通道入口：与单连接模式共用设备认证，失败即回退旧模式。
  Future<WebSocket> _connectMux() async {
    final token = await UsageTracker.tokenFor(_currentXh);
    Object? last;
    for (final e in ServerConfig.ordered) {
      try {
        final ws = await WebSocket.connect(
          '${e.wsBase}-mux',
          headers: {'authorization': 'Bearer $token'},
          protocols: const [wsProtocol],
          customClient: TlsPin.shared(),
        ).timeout(const Duration(seconds: 8));
        if (e.base != ServerConfig.activeBase) {
          AppLog.w('通道', '当前入口不可用，已切换到 ${e.base}');
          await ServerConfig.setActive(e.base);
        }
        return ws;
      } catch (err) {
        // 白名单/换绑属于业务拒绝，换入口也一样，直接上抛
        if (err is AccessDeniedException) rethrow;
        last = err;
      }
    }
    throw StateError('$last');
  }

  Future<void> stop() async {
    _mux.dispose();
    for (final ws in _ws.toList()) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _ws.clear();
    for (final s in _sockets.toList()) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _sockets.clear();
    await _server?.close();
    _server = null;
    _port = null;
    AppLog.d('通道', '本地代理已停止');
  }
}

final campusTunnelProvider = Provider<CampusTunnel>((ref) {
  final tunnel = CampusTunnel(() {
    final s = ref.read(sessionProvider);
    final xh = s.student.xh.trim();
    return xh.isNotEmpty ? xh : s.savedUsername.trim();
  });
  ref.onDispose(tunnel.stop);
  return tunnel;
});

/// 已建立的隧道流：统一封装单连接 WebSocket 与复用子流。
class _Tunnel {
  _Tunnel({required this.add, required this.close});

  final void Function(List<int>) add;
  final void Function() close;
}

/// WebSocket 多路复用客户端。
///
/// 公网高延迟下，每个 CONNECT 单独握手（TCP+TLS+WS）是主要开销；
/// 这里维持一条长连接，用 streamId 区分不同的教务 TCP 流。
/// 任何一步失败都会置为不可用并回退旧模式，不影响功能可用性。
class _MuxTunnel {
  _MuxTunnel(this._connect);

  final Future<WebSocket> Function() _connect;

  WebSocket? _ws;
  Future<void>? _connecting;
  final Map<int, void Function(List<int>)> _data = {};
  final Map<int, void Function()> _closed = {};
  /// 每条子流的建立时间：用于判断「连接到底是几秒后被谁关掉的」
  final Map<int, DateTime> _at = {};
  /// 还没收到首包的子流（用于区分「建流慢」还是「源站慢」）
  final Set<int> _first = {};
  DateTime? _pingAt;
  Timer? _ping;
  bool _off = false;
  DateTime? _offAt;
  int _next = 0;

  int alloc() {
    _next = _next >= 0xFFFFFFFF ? 1 : _next + 1;
    return _next;
  }

  /// 申请一条子流；返回 false 表示不可用，调用方应回退旧模式。
  Future<bool> open(
    int id,
    String host,
    int port, {
    required void Function(List<int>) onData,
    required void Function() onClose,
  }) async {
    if (_off) {
      final at = _offAt;
      if (at == null ||
          DateTime.now().difference(at) > const Duration(minutes: 3)) {
        _off = false;
      } else {
        return false;
      }
    }
    if (!await _ensure()) return false;
    _data[id] = onData;
    _closed[id] = onClose;
    _at[id] = DateTime.now();
    _first.add(id);
    final hostBytes = utf8.encode(host);
    final body = Uint8List(1 + hostBytes.length + 2);
    body[0] = hostBytes.length;
    body.setRange(1, 1 + hostBytes.length, hostBytes);
    ByteData.view(body.buffer).setUint16(1 + hostBytes.length, port);
    _send(1, id, body);
    return true;
  }

  void send(int id, List<int> data) => _send(2, id, data);

  void close(int id) {
    _data.remove(id);
    _closed.remove(id);
    _at.remove(id);
    _first.remove(id);
    _send(3, id, const []);
  }

  void dispose() {
    _ping?.cancel();
    _ping = null;
    final ws = _ws;
    _ws = null;
    _data.clear();
    _closed.clear();
    try {
      ws?.close();
    } catch (_) {}
  }

  Future<bool> _ensure() async {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) return true;
    final pending = _connecting;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
      return _ws?.readyState == WebSocket.open;
    }
    final f = _connectOnce();
    _connecting = f;
    try {
      await f;
    } finally {
      if (identical(_connecting, f)) _connecting = null;
    }
    return _ws?.readyState == WebSocket.open;
  }

  Future<void> _connectOnce() async {
    try {
      final ws = await _connect();
      _ws = ws;
      _off = false;
      _ping?.cancel();
      // 应用层心跳：Cloudflare 对空闲连接有回收，定期写一帧保持存活
      _ping = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_ws?.readyState == WebSocket.open) {
          _pingAt = DateTime.now();
          _send(4, 0, const []);
        }
      });
      ws.listen(
        _onMessage,
        onDone: () => _down(ws),
        onError: (Object _) => _down(ws),
        cancelOnError: true,
      );
      AppLog.d('通道', '复用隧道已连接');
      // 连上立刻打一次心跳，日志里能直接看到隧道端到端 RTT
      _pingAt = DateTime.now();
      _send(4, 0, const []);
    } catch (e) {
      AppLog.w('通道', '复用隧道不可用，回退逐连接模式：$e');
      _off = true;
      _offAt = DateTime.now();
    }
  }

  void _down(WebSocket ws) {
    if (!identical(_ws, ws)) return;
    _ping?.cancel();
    _ping = null;
    _ws = null;
    final closes = _closed.values.toList();
    _data.clear();
    _closed.clear();
    for (final c in closes) {
      try {
        c();
      } catch (_) {}
    }
  }

  void _onMessage(dynamic data) {
    if (data is! List<int> || data.length < 5) return;
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final type = bytes[0];
    final id = ByteData.sublistView(bytes).getUint32(1);
    if (type == 2) {
      final cb = _data[id];
      if (cb == null) return;
      final at = _at[id];
      if (at != null && _first.remove(id)) {
        AppLog.d(
          '通道',
          '首包 #$id（建流→首包 ${DateTime.now().difference(at).inMilliseconds}ms）',
        );
      }
      cb(bytes.sublist(5));
      return;
    }
    if (type == 5) {
      final at = _pingAt;
      if (at != null) {
        AppLog.d(
          '通道',
          '隧道心跳 RTT ${DateTime.now().difference(at).inMilliseconds}ms',
        );
        _pingAt = null;
      }
      return;
    }
    if (type == 3) {
      final cb = _closed.remove(id);
      _data.remove(id);
      final at = _at.remove(id);
      if (at != null) {
        AppLog.d(
          '通道',
          '上游关闭流 #$id（存活 ${DateTime.now().difference(at).inMilliseconds}ms）',
        );
      }
      if (cb != null) {
        try {
          cb();
        } catch (_) {}
      }
    }
  }

  void _send(int type, int id, List<int> payload) {
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) return;
    final frame = Uint8List(5 + payload.length);
    frame[0] = type;
    ByteData.view(frame.buffer).setUint32(1, id);
    frame.setRange(5, frame.length, payload);
    try {
      ws.add(frame);
    } catch (_) {}
  }
}
