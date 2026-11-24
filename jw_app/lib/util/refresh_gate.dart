import 'dart:async';

/// 后台自动刷新的并发闸门。
///
/// 公网隧道下每条 TCP 连接都要独占一条 WebSocket，RTT 常在 1s 以上，
/// 启动时多个页面 Provider 同时自动刷新会互相抢带宽、整体变慢。
/// 这里把「自动刷新」限制为最多 2 个并发，其余排队；
/// 手动刷新（下拉、重试、排名/空教室查询）不经过闸门，保证即时响应。
class RefreshGate {
  RefreshGate._(this._limit);

  static final RefreshGate instance = RefreshGate._(2);

  final int _limit;
  int _running = 0;
  final List<Completer<void>> _waiting = [];

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_running < _limit) {
      _running++;
      return Future<void>.value();
    }
    final c = Completer<void>();
    _waiting.add(c);
    return c.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // 直接把名额交给排队的任务，先减后加会短暂放行超额并发
      _waiting.removeAt(0).complete();
      return;
    }
    _running--;
  }
}
