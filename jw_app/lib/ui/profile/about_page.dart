import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/update_api.dart';
import '../../providers/settings_provider.dart';
import '../../theme/ink_tokens.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

/// 应用级原生通道：读取安装包版本名与构建号
const _appChannel = MethodChannel('cn.gdou.xiuhong/app');

/// 关于页面：开发者信息
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  int _taps = 0;
  String? _build;

  /// 构建号（原生读取失败时显示占位）
  String get _buildLabel => _build ?? '—';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await _appChannel.invokeMapMethod<String, dynamic>(
        'appInfo',
      );
      final build = info?['build'] as String?;
      if (mounted && build != null && build.isNotEmpty) {
        setState(() => _build = build);
      }
    } catch (_) {
      // 非 Android 或通道不可用时静默降级
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    return InkPageScaffold(
      showBack: true,
      title: '关于',
      children: [
        // 应用展示卡（图标 + 名称 + 版本）
        InkCard(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(InkSpacing.xs + 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cs.primary,
                    width: InkStroke.emphasized,
                  ),
                ),
                child: const CircleAvatar(
                  radius: 48,
                  backgroundImage: AssetImage('assets/app_icon.png'),
                ),
              ),
              const SizedBox(height: InkSpacing.l),
              Text('海畔', style: context.tsSection),
              const SizedBox(height: InkSpacing.xs),
              Text('应用版本 v$appVersion', style: context.tsSecondary),
              const SizedBox(height: 2),
              Text('构建版本 $_buildLabel', style: context.tsSecondary),
              const SizedBox(height: InkSpacing.m),
              // 卡片内的彩色小标签
              const Wrap(
                alignment: WrapAlignment.center,
                spacing: InkSpacing.s,
                runSpacing: InkSpacing.s,
                children: [
                  _TagChip(label: '课表同步', color: Color(0xFF4FA8F5)),
                  _TagChip(label: '成绩查询', color: Color(0xFF2FBF8F)),
                  _TagChip(label: '考试提醒', color: Color(0xFFF09A3E)),
                  _TagChip(label: '离线可用', color: Color(0xFF8B7BF7)),
                ],
              ),
            ],
          ),
        ),
        const InkSectionHeader(title: '开发者'),
        // 作者信息卡
        InkCard(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundImage: AssetImage('assets/author_avatar.png'),
              ),
              const SizedBox(width: InkSpacing.l),
              Text('睡醒的夜猫子', style: context.tsBodyStrong),
            ],
          ),
        ),
        const InkSectionHeader(title: '应用信息'),
        InkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              InkSettingTile(
                title: '应用名称',
                trailing: Text('海畔', style: context.tsBodyStrong),
              ),
              // 连续点击版本可开关「调试」隐藏入口
              InkSettingTile(
                title: '应用版本',
                trailing: Text('v$appVersion', style: context.tsBodyStrong),
                onTap: _onVersionTap,
              ),
              InkSettingTile(
                title: '构建版本',
                trailing: Text(_buildLabel, style: context.tsBodyStrong),
                showDivider: false,
              ),
            ],
          ),
        ),
        const InkSectionHeader(title: '技术栈'),
        InkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              InkSettingTile(
                title: '开发框架',
                trailing: Text('Flutter · Dart', style: context.tsBodyStrong),
              ),
              InkSettingTile(
                title: '状态管理',
                trailing: Text('Riverpod', style: context.tsBodyStrong),
              ),
              InkSettingTile(
                title: '网络与会话',
                trailing: Text('Dio · Cookie', style: context.tsBodyStrong),
              ),
              InkSettingTile(
                title: '本地存储',
                trailing: Text(
                  'SharedPreferences',
                  style: context.tsBodyStrong,
                ),
              ),
              InkSettingTile(
                title: '加密与随机数',
                trailing: Text(
                  'PointyCastle · UUID',
                  style: context.tsBodyStrong,
                ),
              ),
              InkSettingTile(
                title: '系统能力',
                trailing: Text(
                  'Kotlin 原生通道 · WebView',
                  style: context.tsBodyStrong,
                ),
                showDivider: false,
              ),
            ],
          ),
        ),
        const InkSectionHeader(title: '开源许可'),
        InkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              InkSettingTile(
                title: '海畔',
                subtitle: 'GNU General Public License v3.0',
                trailing: Text('GPL-3.0', style: context.tsBodyStrong),
              ),
              InkSettingTile(
                title: 'Flutter · Dart',
                subtitle: 'UI 框架与语言运行时',
                trailing: Text('BSD-3-Clause', style: context.tsSecondary),
              ),
              InkSettingTile(
                title: 'Riverpod',
                subtitle: '状态管理',
                trailing: Text('MIT', style: context.tsSecondary),
              ),
              InkSettingTile(
                title: 'Dio · cookie_jar',
                subtitle: '网络请求与 Cookie 会话',
                trailing: Text('MIT', style: context.tsSecondary),
              ),
              InkSettingTile(
                title: 'PointyCastle',
                subtitle: 'RSA 加密',
                trailing: Text('Bouncy Castle', style: context.tsSecondary),
              ),
              InkSettingTile(
                title: 'SharedPreferences · PathProvider',
                subtitle: '本地存储与路径',
                trailing: Text('BSD-3-Clause', style: context.tsSecondary),
              ),
              InkSettingTile(
                title: 'uuid · Cupertino Icons',
                subtitle: '随机数与图标资源',
                trailing: Text('MIT', style: context.tsSecondary),
              ),
              InkSettingTile(
                title: 'WebView Flutter',
                subtitle: '统一身份认证登录',
                trailing: Text('BSD-3-Clause', style: context.tsSecondary),
                showDivider: false,
              ),
            ],
          ),
        ),
        const InkSectionHeader(title: '免责声明'),
        InkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(AppIcons.shield, size: 18, color: cs.primary),
                  const SizedBox(width: InkSpacing.s),
                  Text('数据与隐私', style: context.tsBodyStrong),
                ],
              ),
              const SizedBox(height: InkSpacing.m),
              Text(
                '本应用不会将任何账号、密码、成绩或个人信息存储到服务器，'
                '仅在设备本地缓存登录状态与教务数据；登录通过学校'
                '统一身份认证完成，本应用仅提供登录链接入口。',
                style: context.tsSecondary.copyWith(height: 1.65),
              ),
              const SizedBox(height: InkSpacing.s),
              Text(
                '所有教务数据均来自学校系统，展示结果仅供参考，'
                '请以学校官方发布为准。',
                style: context.tsSecondary.copyWith(height: 1.65),
              ),
            ],
          ),
        ),
        const SizedBox(height: InkSpacing.l),
      ],
    );
  }

  void _onVersionTap() {
    _taps++;
    if (_taps >= 5) {
      ref.read(settingsProvider.notifier).toggleDebugEntry();
      _taps = 0;
      final on = ref.read(settingsProvider).showDebug;
      showInkToast(context, on ? '已开启调试入口' : '已关闭调试入口');
    } else {
      setState(() {});
    }
  }
}

/// 彩色小标签：浅色底 + 同色文字，随主题自动淡化
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: InkSpacing.m,
        vertical: InkSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(InkRadius.pill),
      ),
      child: Text(
        label,
        style: context.tsCaption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
