import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前应用版本（与 pubspec.yaml version 保持一致）
const appVersion = '1.0.0';

/// GitHub 发布仓库（owner/repo）
const githubRepo = 'QingYu327/GDOU-APP';

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
    var version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    if (version.isEmpty) return ('', '', '', '');
    // 版本比对：仅按数字段比较，tag 可能带后缀（如 1.0.1-beta）
    bool newer(String a, String b) {
      final pa = RegExp(r'\d+').allMatches(a).map((m) => int.parse(m.group(0)!)).toList();
      final pb = RegExp(r'\d+').allMatches(b).map((m) => int.parse(m.group(0)!)).toList();
      for (var i = 0; i < pa.length || i < pb.length; i++) {
        final x = i < pa.length ? pa[i] : 0;
        final y = i < pb.length ? pb[i] : 0;
        if (x != y) return x > y;
      }
      return false;
    }

    if (!newer(version, appVersion)) {
      // 非更新版本：若与当前版本完全一致，返回其更新日志，
      // 供页面展示"当前版本更新日志 + 置灰按钮"；更旧版本视为无更新。
      if (version == appVersion) {
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
