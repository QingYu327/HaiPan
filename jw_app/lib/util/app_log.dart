import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量应用日志：区分模块/页面(tag)，支持按保留天数自动清理。
/// 内存最新在前 + 写入应用私有目录 app.log；捕获 Flutter/平台/未捕获异常。
class AppLog {
  AppLog._();

  static const int _max = 2000;
  static const String _retKey = 'log_retention_days';
  static const String _detKey = 'log_detail';

  /// 保留天数（默认 7 天），超过的日志自动清理
  static int retentionDays = 7;

  /// 是否输出详细（调试级）日志。
  /// true=调试级（全部 D/W/E）；false=查看级（仅 W/E，过滤细节 D）。
  static bool debugDetail = true;

  // 最新在前（_entries[0] 最新）
  static final List<String> _entries = [];
  static File? _file;

  /// 学号等长数字串脱敏：保留前 2 后 2，中间用 * 代替。
  /// 日志、导出、界面展示统一走这里，避免任何学号以明文落盘或外发。
  static String mask(String text) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(
      RegExp(r'(?<!\d)(\d{6,20})(?!\d)'),
      (m) {
        final s = m.group(1)!;
        if (s.length <= 4) return s;
        return '${s.substring(0, 2)}${'*' * (s.length - 4)}'
            '${s.substring(s.length - 2)}';
      },
    );
  }

  /// 只脱敏正文，保留 `时间 [级别] [模块]` 前缀（时间里的微秒不能被误伤）
  static String _maskLine(String line) {
    final m = RegExp(r'^(\S+\s+\[[DWE]\]\s+\[[^\]]*\]\s*)([\s\S]*)$')
        .firstMatch(line);
    if (m == null) return mask(line);
    return '${m.group(1)}${mask(m.group(2) ?? '')}';
  }

  /// 在 runApp 前调用；读取保留天数、加载历史日志、捕获异常。
  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/app.log');
      if (_file!.existsSync()) {
        final s = await _file!.readAsString();
        if (s.isNotEmpty) {
          // 旧版本日志里可能已有明文，读取时统一脱敏一次
          _entries.addAll(
            s
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .map(_maskLine),
          );
        }
      }
    } catch (_) {
      // 目录不可用时仅保留内存日志
    }
    try {
      final p = await SharedPreferences.getInstance();
      retentionDays = p.getInt(_retKey) ?? 7;
      debugDetail = p.getBool(_detKey) ?? true;
    } catch (_) {}
    _prune();
    await _persist();

    FlutterError.onError = (details) {
      e('Flutter', '${details.exception}\n${details.stack ?? ''}');
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (err, st) {
      e('Platform', '$err\n$st');
      return true;
    };
  }

  static void d(String tag, String msg) {
    // 查看级（非调试级）时过滤掉细节 D 日志
    if (!debugDetail) return;
    _add('D', tag, msg);
  }
  static void w(String tag, String msg) => _add('W', tag, msg);
  static void e(String tag, String msg) => _add('E', tag, msg);

  /// 设置是否输出详细（调试级）日志并持久化
  static Future<void> setDetail(bool on) async {
    debugDetail = on;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_detKey, on);
    } catch (_) {}
    // 开关变化本身也留痕（关闭时仍写入，便于事后确认当前级别）
    _add('D', '日志', '输出详细日志 → ${on ? '开启（调试级）' : '关闭（仅警告/错误）'}');
  }

  static void _add(String lvl, String tag, String msg) {
    final now = DateTime.now().toLocal();
    // 落盘前统一脱敏：任何调用方即使传入学号，也不会以明文写入日志
    _entries.insert(
        0, '${now.toIso8601String()} [$lvl] [$tag] ${mask(msg)}'.trim());
    _prune();
    _persist();
  }

  static DateTime _cutoff() =>
      DateTime.now().subtract(Duration(days: retentionDays));

  static void _prune() {
    _entries.removeWhere((l) {
      final t = DateTime.tryParse(l.split(' ').first);
      return t != null && t.isBefore(_cutoff());
    });
    if (_entries.length > _max) {
      _entries.removeRange(_max, _entries.length);
    }
  }

  static Future<void> _persist() async {
    try {
      await _file?.writeAsString(
          (_entries.isEmpty) ? '' : '${_entries.join('\n')}\n',
          flush: true);
    } catch (_) {}
  }

  /// 设置日志保留天数并立即清理
  static Future<void> setRetention(int days) async {
    retentionDays = days < 1 ? 1 : days;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_retKey, retentionDays);
    } catch (_) {}
    final before = _entries.length;
    _prune();
    _persist();
    final removed = before - _entries.length;
    _add(
      'D',
      '日志',
      '保留天数 → $retentionDays 天${removed > 0 ? '（清理 $removed 条过期日志）' : ''}',
    );
  }

  /// 原始日志条目（最新在前），供页面解析为卡片展示
  static List<String> get entries => _entries;

  /// 导出反馈日志到应用私有目录，返回文件绝对路径（供 FileProvider 共享）。
  /// 导出内容仍是脱敏后的条目；[extraInfo] 为自动采集的机型/系统等信息，
  /// 写在文件头部，用户只需描述问题本身，不必再手填环境。
  static Future<String?> exportForFeedback({
    Map<String, String>? extraInfo,
  }) async {
    try {
      final dir = await getApplicationSupportDirectory();
      // 只保留最近一份导出，避免反复反馈堆积文件
      for (final f in dir.listSync()) {
        final name = f.path.split(Platform.pathSeparator).last;
        if (f is File && name.startsWith('haipan-feedback-')) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name = 'haipan-feedback-${now.year}${two(now.month)}${two(now.day)}'
          '-${two(now.hour)}${two(now.minute)}${two(now.second)}.txt';
      final file = File('${dir.path}/$name');
      final buf = StringBuffer()
        ..writeln('海畔 App 反馈日志')
        ..writeln('导出时间：${now.toIso8601String()}')
        ..writeln('日志条数：${_entries.length}');
      if (extraInfo != null && extraInfo.isNotEmpty) {
        buf
          ..writeln('--- 设备与环境（自动采集） ---')
          ..writeAll(
            extraInfo.entries.map((e) => '${e.key}：${e.value}\n'),
          );
      }
      buf.writeln('---');
      // 内存里最新在前，落盘按时间正序便于阅读
      for (final line in _entries.reversed) {
        buf.writeln(line);
      }
      await file.writeAsString(buf.toString(), flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    _entries.clear();
    try {
      if (_file != null) await _file!.writeAsString('', flush: true);
    } catch (_) {}
    // 一并删除反馈导出的附件，避免「清除日志」后私有目录里仍残留
    try {
      final dir = await getApplicationSupportDirectory();
      for (final f in dir.listSync()) {
        final name = f.path.split(Platform.pathSeparator).last;
        if (f is File && name.startsWith('haipan-feedback-')) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}