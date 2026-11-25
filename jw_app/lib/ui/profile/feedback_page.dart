import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/update_api.dart' show appVersion;
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

/// 意见反馈：邮件提交。按钮会自动导出运行日志并作为附件。
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  static const _appChannel = MethodChannel('cn.gdou.xiuhong/app');

  static const String email = 'xiuhong0327@163.com';

  static const String subjectTemplate = '【海畔反馈】问题简述';

  /// 只让用户简单描述问题：机型、系统、版本等由 App 自动采集并写进导出日志
  static const String bodyTemplate = '问题描述：\n';

  bool _busy = false;

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showInkToast(context, '$label已复制');
  }

  /// 自动采集反馈所需的设备/系统信息，写入导出日志头部，
  /// 用户不必再手动填写机型、系统版本这类难记的内容。
  Future<Map<String, String>> _collectDeviceInfo() async {
    final info = <String, String>{'App 版本': 'v$appVersion'};
    try {
      final d = await _appChannel.invokeMethod<Map>('deviceInfo');
      if (d != null) {
        void put(String label, String key) {
          final v = '${d[key] ?? ''}'.trim();
          if (v.isNotEmpty && v != 'null') info[label] = v;
        }

        put('厂商', 'manufacturer');
        put('品牌', 'brand');
        put('机型', 'model');
        put('设备代号', 'device');
        put('Android 版本', 'release');
        put('SDK', 'sdk');
        put('CPU 架构', 'abi');
        put('屏幕分辨率', 'screen');
        put('屏幕密度', 'density');
        put('应用版本号', 'version');
        put('构建号', 'build');
        put('语言', 'locale');
        put('时区', 'timezone');
      }
    } catch (_) {
      // 原生通道不可用时保留基础信息
    }
    final os = Platform.operatingSystem;
    if (os.isNotEmpty) info['系统'] = os;
    final osVersion = Platform.operatingSystemVersion;
    if (osVersion.isNotEmpty) info['系统版本'] = osVersion;
    return info;
  }

  /// 导出日志 → 调起邮件客户端并带上附件；失败时退回纯 mailto。
  Future<void> _sendWithLog() async {
    if (_busy) return;
    AppLog.w('反馈', '点击「导出日志并发送邮件」');
    setState(() => _busy = true);
    final deviceInfo = await _collectDeviceInfo();
    final logPath = await AppLog.exportForFeedback(extraInfo: deviceInfo);
    AppLog.w('反馈', '日志导出：${logPath ?? '失败'}');
    var ok = false;
    if (logPath != null) {
      try {
        ok = await _appChannel.invokeMethod<bool>('sendFeedbackMail', {
              'to': email,
              'subject': subjectTemplate,
              'body': '$bodyTemplate\n\n日志文件：见附件',
              'path': logPath,
            }) ??
            false;
      } catch (_) {
        // 通道不可用则走 mailto 兜底
      }
    }
    var fallback = false;
    if (!ok) {
      final uri = 'mailto:$email'
          '?subject=${Uri.encodeComponent(subjectTemplate)}'
          '&body=${Uri.encodeComponent(bodyTemplate)}';
      try {
        fallback = await _appChannel.invokeMethod<bool>(
              'openMailto',
              {'uri': uri},
            ) ??
            false;
      } catch (_) {
        // 忽略，按失败提示
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    AppLog.w('反馈', '邮件拉起：附件=$ok 兜底=$fallback');
    if (!ok && fallback) {
      showInkToast(context, '日志导出失败，请在邮件中手动添加日志');
    } else if (!ok && !fallback) {
      showInkToast(context, '未找到邮件客户端，请复制邮箱后手动发送', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkPageScaffold(
      showBack: true,
      title: '意见反馈',
      children: [
        InkCard(
          tone: InkTone.info,
          child: Text(
            '简单描述遇到的问题即可，手机型号、系统版本等信息会自动写入日志。'
            '点击下方按钮会导出日志并作为邮件附件。',
            style: context.tsBody,
          ),
        ),
        const InkSectionHeader(title: '反馈邮箱'),
        _CopyCard(
          text: email,
          copyLabel: '邮箱',
          emphasize: true,
          onCopy: () => _copy(email, '邮箱'),
        ),
        const InkSectionHeader(title: '邮件主题'),
        _CopyCard(
          text: subjectTemplate,
          copyLabel: '主题',
          onCopy: () => _copy(subjectTemplate, '主题'),
        ),
        const InkSectionHeader(title: '信息描述模板'),
        _CopyCard(
          text: bodyTemplate,
          copyLabel: '模板',
          onCopy: () => _copy(bodyTemplate, '模板'),
        ),
        const SizedBox(height: InkSpacing.l),
        FilledButton.icon(
          onPressed: _busy ? null : _sendWithLog,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(AppIcons.mail, size: 20),
          label: Text(_busy ? '正在导出日志…' : '导出日志并发送邮件'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
        ),
        const SizedBox(height: InkSpacing.l),
      ],
    );
  }
}

/// 内容卡：文本可选中，右上角提供复制。
class _CopyCard extends StatelessWidget {
  const _CopyCard({
    required this.text,
    required this.copyLabel,
    required this.onCopy,
    this.emphasize = false,
  });

  final String text;
  final String copyLabel;
  final VoidCallback onCopy;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            text,
            style: emphasize
                ? context.tsBodyStrong.copyWith(
                    color: context.scheme.primary,
                    letterSpacing: 0.2,
                  )
                : context.tsBody,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(AppIcons.copy, size: 16),
              label: Text('复制$copyLabel'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
    );
  }
}
