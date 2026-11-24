import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';

enum UpdateDownloadStatus { idle, running, success, failed }

/// 下载状态：页面只读，真正的下载由系统 DownloadManager 执行，
/// 因此退出更新页、切后台都不会中断，通知栏会持续显示进度。
class UpdateDownloadState {
  const UpdateDownloadState({
    this.status = UpdateDownloadStatus.idle,
    this.version = '',
    this.downloaded = 0,
    this.total = 0,
    this.error,
    this.fromCache = false,
  });

  final UpdateDownloadStatus status;
  final String version;
  final int downloaded;
  final int total;
  final String? error;

  /// 是否为恢复上一次未完成的下载（仅用于提示文案）
  final bool fromCache;

  double get progress {
    if (total > 0) return (downloaded / total).clamp(0.0, 1.0);
    return 0;
  }

  bool get active => status == UpdateDownloadStatus.running;
}

class UpdateDownloader {
  UpdateDownloader._();

  static final UpdateDownloader instance = UpdateDownloader._();

  static const MethodChannel _ch = MethodChannel('cn.gdou.xiuhong/install');
  static const String _kId = 'update.download_id';
  static const String _kVersion = 'update.download_version';

  final ValueNotifier<UpdateDownloadState> state =
      ValueNotifier(const UpdateDownloadState());

  int? _id;
  Timer? _timer;
  List<String> _candidates = const [];
  int _candidateIndex = 0;
  String _version = '';
  bool _resumed = false;

  /// 页面进入时调用：若上次下载仍在系统队列里，恢复进度与安装入口。
  Future<void> resume() async {
    if (_resumed) return;
    _resumed = true;
    final p = await SharedPreferences.getInstance();
    final id = p.getInt(_kId) ?? 0;
    if (id <= 0) return;
    final version = p.getString(_kVersion) ?? '';
    _id = id;
    _version = version;
    final q = await _query(id);
    if (q == null) {
      await _clearStored();
      return;
    }
    if (q.status == _statusSuccessful) {
      state.value = UpdateDownloadState(
        status: UpdateDownloadStatus.success,
        version: version,
        downloaded: q.downloaded,
        total: q.total,
        fromCache: true,
      );
    } else if (q.status == _statusRunning || q.status == _statusPending) {
      state.value = UpdateDownloadState(
        status: UpdateDownloadStatus.running,
        version: version,
        downloaded: q.downloaded,
        total: q.total,
        fromCache: true,
      );
      _startPolling();
    } else if (q.status == _statusFailed) {
      await _clearStored();
    }
  }

  /// 开始下载，按顺序尝试候选地址（镜像优先，失败回退直连）。
  Future<void> start(String version, List<String> urls) async {
    final list = urls.where((u) => u.isNotEmpty).toList();
    if (list.isEmpty) return;
    if (state.value.status == UpdateDownloadStatus.running) return;
    _candidates = list;
    _candidateIndex = 0;
    _version = version;
    state.value = UpdateDownloadState(
      status: UpdateDownloadStatus.running,
      version: version,
    );
    _resumed = true;
    await _enqueueCurrent();
  }

  Future<void> _enqueueCurrent() async {
    final url = _candidates[_candidateIndex];
    try {
      AppLog.d('更新', '系统下载开始：$url');
      final id = await _ch.invokeMethod<int>('startUpdateDownload', {
        'url': url,
        'filename': 'haipan_update.apk',
        'title': '海畔 v$_version',
      });
      if (id == null || id <= 0) throw StateError('下载任务创建失败');
      _id = id;
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kId, id);
      await p.setString(_kVersion, _version);
      _startPolling();
    } catch (e) {
      AppLog.w('更新', '$url 启动失败：$e');
      await _tryNext('下载启动失败');
    }
  }

  Future<void> _tryNext(String reason) async {
    _candidateIndex++;
    if (_candidateIndex < _candidates.length) {
      await _enqueueCurrent();
      return;
    }
    _timer?.cancel();
    state.value = UpdateDownloadState(
      status: UpdateDownloadStatus.failed,
      version: _version,
      error: reason,
    );
    await _clearStored();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      final id = _id;
      if (id == null) return;
      final q = await _query(id);
      if (q == null) {
        await _tryNext('下载任务已丢失');
        return;
      }
      final cur = state.value;
      if (q.status == _statusSuccessful) {
        _timer?.cancel();
        state.value = UpdateDownloadState(
          status: UpdateDownloadStatus.success,
          version: _version,
          downloaded: q.total > 0 ? q.total : q.downloaded,
          total: q.total,
        );
        AppLog.d('更新', '下载完成 v$_version');
        return;
      }
      if (q.status == _statusFailed) {
        _timer?.cancel();
        await _tryNext('下载失败');
        return;
      }
      state.value = UpdateDownloadState(
        status: UpdateDownloadStatus.running,
        version: _version,
        downloaded: q.downloaded,
        total: q.total,
        fromCache: cur.fromCache,
      );
    });
  }

  /// 下载完成后拉起系统安装器
  Future<bool> install() async {
    final id = _id;
    if (id == null) return false;
    try {
      final ok = await _ch.invokeMethod<bool>('installDownloaded', {'id': id});
      return ok == true;
    } catch (e) {
      AppLog.w('更新', '拉起安装失败：$e');
      return false;
    }
  }

  Future<void> cancel() async {
    final id = _id;
    _timer?.cancel();
    if (id != null) {
      try {
        await _ch.invokeMethod('cancelUpdateDownload', {'id': id});
      } catch (_) {}
    }
    _id = null;
    state.value = const UpdateDownloadState();
    await _clearStored();
    AppLog.d('更新', '下载已取消');
  }

  Future<void> _clearStored() async {
    _id = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kId);
    await p.remove(_kVersion);
  }

  Future<_DownloadQuery?> _query(int id) async {
    try {
      final r = await _ch
          .invokeMapMethod<String, dynamic>('queryUpdateDownload', {'id': id});
      if (r == null) return null;
      final status = (r['status'] as num?)?.toInt() ?? -1;
      if (status < 0) return null;
      return _DownloadQuery(
        status: status,
        downloaded: (r['downloaded'] as num?)?.toInt() ?? 0,
        total: (r['total'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class _DownloadQuery {
  const _DownloadQuery({
    required this.status,
    required this.downloaded,
    required this.total,
  });

  final int status;
  final int downloaded;
  final int total;
}

// DownloadManager 状态常量
const int _statusPending = 1;
const int _statusRunning = 2;
const int _statusSuccessful = 8;
const int _statusFailed = 16;
