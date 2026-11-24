import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 下载新版本 APK 并调用系统安装（原生 FileProvider 通道）
class ApkInstaller {
  static const _ch = MethodChannel('cn.gdou.xiuhong/install');

  /// 下载前清理旧的更新安装包，避免残留占空间
  static Future<void> cleanupOldApks() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final stale = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('海畔_update_'));
      for (final f in stale) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<void> downloadAndInstall(
    String url,
    String filename, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$filename');
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 300),
    ));
    // 覆盖下载前先清旧包（文件名相同的会直接覆盖，无需处理）
    await cleanupOldApks();
    await dio.download(url, file.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
      if (total > 0) onProgress?.call(received / total);
    });
    await _ch.invokeMethod('install', {'path': file.path});
  }

  /// 中断进行中的下载（传与 downloadAndInstall 相同的 cancelToken）
  static void cancel(CancelToken? token) {
    try {
      token?.cancel('下载已取消');
    } catch (_) {}
  }
}