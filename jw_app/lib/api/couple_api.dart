import 'package:dio/dio.dart';

import '../models/couple_models.dart';
import 'usage_api.dart';

/// 情侣课表云端接口：配对码、状态、快照同步与解绑。
/// 只上传课名/星期/节次/地点/周次，不包含学号、姓名、教师或成绩。
class CoupleApi {
  CoupleApi._();

  static Future<String> createCode(String xh) async {
    final d = await _call('POST', '/pair/code', xh, data: const {});
    final code = '${d['code'] ?? ''}';
    if (code.isEmpty) throw const CoupleException('bad_response', '未获取到配对码');
    return code;
  }

  static Future<void> bind(String xh, String code) async {
    await _call('POST', '/pair/bind', xh, data: {'code': code});
  }

  static Future<CoupleStatus> status(String xh) async {
    final d = await _call('GET', '/pair/status', xh);
    return CoupleStatus(
      paired: d['paired'] == true,
      myUpdatedAt: _int(d['myUpdatedAt']),
      partnerUpdatedAt: _int(d['partnerUpdatedAt']),
    );
  }

  static Future<void> sync(String xh, List<CoupleCourse> courses) async {
    await _call('POST', '/pair/sync', xh, data: {
      'courses': [for (final c in courses) c.toJson()],
    });
  }

  static Future<CouplePartner> partner(String xh) async {
    final d = await _call('GET', '/pair/partner', xh);
    final list = <CoupleCourse>[];
    final raw = d['courses'];
    if (raw is List) {
      for (final x in raw) {
        if (x is Map) list.add(CoupleCourse.fromJson(Map<String, dynamic>.from(x)));
      }
    }
    return CouplePartner(courses: list, updatedAt: _int(d['updatedAt']));
  }

  static Future<void> unbind(String xh) async {
    await _call('DELETE', '/pair', xh);
  }

  static Future<Map<String, dynamic>> _call(
    String method,
    String path,
    String xh, {
    Object? data,
  }) async {
    try {
      final r = await UsageTracker.apiRequest(
        method,
        path,
        xh: xh,
        data: data,
      );
      final d = _map(r.data);
      if (d['ok'] == false) throw _error(d);
      return d;
    } on DioException catch (e) {
      final d = _map(e.response?.data);
      if (d['error'] != null) throw _error(d);
      rethrow;
    }
  }

  static CoupleException _error(Map<String, dynamic> d) {
    final code = '${d['error'] ?? 'unknown'}';
    final msg = switch (code) {
      'already_paired' => '当前账号已绑定，请先解除原有配对',
      'invalid_code' => '配对码无效或已过期',
      'too_many_attempts' => '错误次数过多，请 10 分钟后再试',
      'self_bind' => '不能绑定自己的配对码',
      'target_paired' => '对方已与其他账号配对',
      'not_paired' => '尚未完成配对',
      'not_allowed' => '当前账号未开通该功能',
      _ => '操作失败，请稍后重试',
    };
    return CoupleException(code, msg);
  }

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
}
