import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../util/build_info.dart';

/// 当前安装包的版本信息（以原生 appInfo 为准，避免与构建号漂移）
String get appVersion => BuildInfo.version;
int get appBuild => BuildInfo.build;
String get appVersionLabel => BuildInfo.label;

/// GitHub 发布仓库（owner/repo）：公开仓库只放文档与主要源码，APK 走 Release
const githubRepo = 'QingYu327/HaiPan';

/// GitHub 加速镜像前缀（默认使用；下载失败时回退直连）
const defaultGhMirror = 'https://v6.gh-proxy.org/';

/// 一次更新检查的结果。
///
/// 把「是否有更新」和「Release 是否就是当前构建」显式分开：
/// 首页只根据 [hasUpdate] 决定弹窗，更新页用 [isCurrent] 展示发布说明。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.version,
    required this.notes,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.hasUpdate,
    required this.isCurrent,
  });

  /// Release tag 去掉 v 前缀，如 1.0.1+4145
  final String version;
  final String notes;
  final String releaseUrl;
  final String downloadUrl;

  /// 服务端存在比当前安装包更高的版本
  final bool hasUpdate;

  /// 服务端最新 Release 就是当前安装的构建
  final bool isCurrent;

  static const UpdateCheckResult none = UpdateCheckResult(
    version: '',
    notes: '',
    releaseUrl: '',
    downloadUrl: '',
    hasUpdate: false,
    isCurrent: false,
  );
}

/// GitHub Release 检查更新（公共仓库，无需鉴权；
/// 注意不要在客户端嵌入 token，APK 可被反编译）
class UpdateApi {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.github.com',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Accept': 'application/vnd.github+json'},
  ));

  Future<UpdateCheckResult> checkLatest() async {
    // 运行版本从安装包读取；首次调用时等待读取完成
    await BuildInfo.ensureLoaded();
    final currentVersion = BuildInfo.version;
    final currentBuild = BuildInfo.build;

    late final Map<String, dynamic> data;
    try {
      final resp = await _dio.get('/repos/$githubRepo/releases/latest');
      data = Map<String, dynamic>.from(resp.data as Map);
    } on DioException catch (e) {
      // 仓库还没有发布任何 Release 时 GitHub 返回 404，按“无更新”处理
      if (e.response?.statusCode == 404) return UpdateCheckResult.none;
      rethrow;
    }
    final tagName = '${data['tag_name'] ?? ''}'.trim();
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    if (version.isEmpty) return UpdateCheckResult.none;

    // 版本比对：先只比主版本数字段（忽略 +构建号），主版本相同再比构建号
    final pa = _numbers(version.split('+').first);
    final pb = _numbers(currentVersion.split('+').first);
    var newer = false;
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) {
        newer = x > y;
        break;
      }
    }
    if (!newer && _sameCore(version, currentVersion)) {
      newer = _buildOf(version) > currentBuild;
    }

    final notes = _notesOf(data);

    if (!newer) {
      // 只有 tag 与安装包完全一致时才返回发布说明，供更新页置灰展示
      final sameBuild = _sameCore(version, currentVersion) &&
          _buildOf(version) == currentBuild;
      if (!sameBuild) return UpdateCheckResult.none;
      return UpdateCheckResult(
        version: version,
        notes: notes,
        releaseUrl: '${data['html_url'] ?? ''}',
        downloadUrl: '',
        hasUpdate: false,
        isCurrent: true,
      );
    }

    final url = '${data['html_url'] ?? ''}';
    // 取 release assets 里的第一个 APK 直链
    var downloadUrl = '';
    try {
      final assets = data['assets'] as List? ?? [];
      for (final a in assets) {
        final asset = Map<String, dynamic>.from(a as Map);
        final name = '${asset['name'] ?? ''}'.toLowerCase();
        if (name.endsWith('.apk')) {
          downloadUrl = '${asset['browser_download_url'] ?? ''}';
          break;
        }
      }
    } catch (_) {}

    return UpdateCheckResult(
      version: version,
      notes: notes,
      releaseUrl: url,
      downloadUrl: downloadUrl,
      hasUpdate: true,
      isCurrent: false,
    );
  }

  String _notesOf(Map<String, dynamic> data) {
    var notes = '${data['body'] ?? ''}'.trim();
    if (notes.length > 800) notes = '${notes.substring(0, 800)}…';
    return notes;
  }
}

final updateApiProvider = Provider<UpdateApi>((ref) => UpdateApi());

/// 取版本号里的数字段（1.0.1+4143 → [1,0,1,4143]）
List<int> _numbers(String v) =>
    RegExp(r'\d+').allMatches(v).map((m) => int.parse(m.group(0)!)).toList();

/// 主版本是否相同（忽略构建号）
bool _sameCore(String a, String b) {
  final pa = _numbers(a.split('+').first);
  final pb = _numbers(b.split('+').first);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return false;
  }
  return true;
}

/// tag 里的构建号（v1.0.1+4143 → 4143），没有则 0
int _buildOf(String v) {
  final m = RegExp(r'\+(\d+)').firstMatch(v);
  return m == null ? 0 : int.parse(m.group(1)!);
}
