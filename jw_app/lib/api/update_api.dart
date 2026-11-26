import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前应用版本（与 pubspec.yaml version 保持一致）
const appVersion = '1.0.1';

/// 当前构建号（与 pubspec.yaml 的 +N 一致），Release tag 形如 v1.0.1+4143
const appBuild = 4144;

/// 展示用完整版本号
const appVersionLabel = '$appVersion+$appBuild';

/// GitHub 发布仓库（owner/repo）：公开仓库只放文档与主要源码，APK 走 Release
const githubRepo = 'QingYu327/HaiPan';

/// GitHub 加速镜像前缀（默认使用；下载失败时回退直连）
const defaultGhMirror = 'https://v6.gh-proxy.org/';

/// GitHub Release 检查更新（公共仓库，无需鉴权；
/// 注意不要在客户端嵌入 token，APK 可被反编译）
class UpdateApi {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://api.github.com',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Accept': 'application/vnd.github+json'},
  ));

  /// 返回空串 = 已是最新；否则返回 (最新版本号, 发布说明, 发布页, APK 直链)
  Future<(String version, String notes, String url, String downloadUrl)>
      checkLatest() async {
    late final Map<String, dynamic> data;
    try {
      final resp = await _dio.get('/repos/$githubRepo/releases/latest');
      data = Map<String, dynamic>.from(resp.data as Map);
    } on DioException catch (e) {
      // 仓库还没有发布任何 Release 时 GitHub 返回 404，按“无更新”处理
      if (e.response?.statusCode == 404) return ('', '', '', '');
      rethrow;
    }
    final tagName = '${data['tag_name'] ?? ''}'.trim();
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    if (version.isEmpty) return ('', '', '', '');
    // 版本比对：先只比主版本数字段（忽略 +构建号），主版本相同再比构建号
    final pa = _numbers(version.split('+').first);
    final pb = _numbers(appVersion);
    var newer = false;
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) {
        newer = x > y;
        break;
      }
    }
    if (!newer && _sameCore(version, appVersion)) {
      newer = _buildOf(version) > appBuild;
    }

    if (!newer) {
      // 非更新版本：与当前构建一致时返回更新日志，供页面展示并置灰按钮
      if (_sameCore(version, appVersion) && _buildOf(version) == appBuild) {
        var notes = '${data['body'] ?? ''}'.trim();
        if (notes.length > 800) notes = '${notes.substring(0, 800)}…';
        return (version, notes, '', ''); // downloadUrl 空 → 按钮置灰
      }
      return ('', '', '', '');
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
    var notes = '${data['body'] ?? ''}'.trim();
    if (notes.length > 800) notes = '${notes.substring(0, 800)}…';
    return (version, notes, url, downloadUrl);
  }
}

final updateApiProvider = Provider<UpdateApi>((ref) => UpdateApi());

/// 该 Release 版本是否就是当前安装的构建
bool isCurrentRelease(String v) =>
    _sameCore(v, appVersion) && _buildOf(v) == appBuild;

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
