import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/ink_page_transition.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../login/login_page.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_dialog.dart';
import '../widgets/ink_page.dart';
import 'about_page.dart';
import 'debug_page.dart';
import 'favorite_rooms_page.dart';
import 'feedback_page.dart';
import 'ge_credit_page.dart';
import 'settings_page.dart';
import 'update_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final s = session.student;
    final settings = ref.watch(settingsProvider);
    // 年级：优先接口返回，否则按学号前 4 位推断
    final gradeLabel = s.njmc.isNotEmpty
        ? s.njmc
        : (s.xh.length >= 4 && int.tryParse(s.xh.substring(0, 4)) != null
              ? '${s.xh.substring(0, 4)}级'
              : '');
    // 学院：接口直取；缺失时取班级前缀中的"xx学院"
    var collegeLabel = s.jgmc;
    if (collegeLabel.isEmpty && s.bjmc.contains('学院')) {
      final idx = s.bjmc.indexOf('学院');
      collegeLabel = s.bjmc.substring(0, idx + 2);
    }

    final entries = <_Entry>[
      _Entry(
        AppIcons.settings,
        '设置',
        () => _push(context, const SettingsPage()),
      ),
      _Entry(
        AppIcons.room,
        '空教室查询',
        () => _push(context, const FavoriteRoomsPage()),
      ),
      _Entry(
        AppIcons.chartBar,
        '通识拓展学分',
        () => _push(context, const GeCreditPage()),
      ),
      // 检查更新：人人可见；黑名单用户点开显示无更新
      _Entry(AppIcons.update, '检查更新', () => _push(context, const UpdatePage())),
      _Entry(
        AppIcons.feedback,
        '意见反馈',
        () => _push(context, const FeedbackPage()),
      ),
      // 隐藏入口（调试）：任何用户，需连续点击版本号手动打开
      if (settings.showDebug)
        _Entry(AppIcons.debug, '调试', () => _push(context, const DebugPage())),
      _Entry(AppIcons.info, '关于', () => _push(context, const AboutPage())),
    ];

    // 学籍信息：每行用不同色调的图标，与下方统一主色的功能入口区分。
    final infoSpecs = <(IconData, String, String, InkTone)>[
      if (collegeLabel.isNotEmpty)
        (AppIcons.accountBalance, '院系', collegeLabel, InkTone.info),
      if (s.zymc.isNotEmpty) (AppIcons.book, '专业', s.zymc, InkTone.success),
      if (gradeLabel.isNotEmpty)
        (AppIcons.school, '年级', gradeLabel, InkTone.warning),
      if (s.bjmc.isNotEmpty) (AppIcons.groups, '班级', s.bjmc, InkTone.neutral),
    ];

    return InkPageScaffold(
      title: '我的',
      body: ListView(
        primary: false,
        padding: EdgeInsets.fromLTRB(
          0,
          InkSpacing.s,
          0,
          inkPagePadding(context).bottom,
        ),
        children: [
          _ProfileHeader(student: s),
          if (infoSpecs.isNotEmpty) ...[
            const InkSectionHeader(title: '学籍'),
            InkCard(
              padding: EdgeInsets.zero,
              // 学籍卡加一层极淡的信息色底，与功能栏的纯卡片外观区分。
              tone: InkTone.info,
              child: Column(
                children: [
                  for (var i = 0; i < infoSpecs.length; i++)
                    _infoTile(
                      context,
                      infoSpecs[i].$1,
                      infoSpecs[i].$2,
                      infoSpecs[i].$3,
                      infoSpecs[i].$4,
                      showDivider: i < infoSpecs.length - 1,
                    ),
                ],
              ),
            ),
          ],
          const InkSectionHeader(title: '功能'),
          InkCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  InkSettingTile(
                    title: entries[i].label,
                    icon: entries[i].icon,
                    iconTone: InkTone.info,
                    onTap: entries[i].onTap,
                    showDivider: i < entries.length - 1,
                  ),
              ],
            ),
          ),
          const SizedBox(height: InkSpacing.m),
          InkCard(
            padding: EdgeInsets.zero,
            child: session.status == SessionStatus.loggedIn
                ? InkSettingTile(
                    title: '退出登录',
                    icon: AppIcons.logout,
                    iconTone: InkTone.danger,
                    titleTone: InkTone.danger,
                    onTap: () => _confirmLogout(context, ref),
                    showDivider: false,
                  )
                : InkSettingTile(
                    title: '登录',
                    icon: AppIcons.login,
                    iconTone: InkTone.info,
                    onTap: () =>
                        _push(context, const LoginPage(showGuestButton: false)),
                    showDivider: false,
                  ),
          ),
          const SizedBox(height: InkSpacing.m),
          Center(
            child: Text(
              'Powered By XIUHONG',
              style: context.tsCaption.copyWith(
                letterSpacing: 0.6,
                color: context.ink.secondaryLabel,
              ),
            ),
          ),
          const SizedBox(height: InkSpacing.l),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    AppLog.d('页面', '从「我的」打开 ${page.runtimeType}');
    Navigator.push(context, InkPageRoute(builder: (_) => page));
  }

  /// 学籍信息行：右侧值限宽，避免长专业名挤压左侧标签。
  Widget _infoTile(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    InkTone tone, {
    required bool showDivider,
  }) {
    return InkSettingTile(
      title: label,
      icon: icon,
      iconTone: tone,
      showDivider: showDivider,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 210),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: context.tsBodyStrong,
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showInkDialog(
      context,
      title: '退出登录',
      message: '确定要退出当前账号吗？',
      confirmText: '退出',
      danger: true,
    );
    if (confirmed) {
      await ref.read(sessionProvider.notifier).logout();
    }
  }
}

/// 头部个人信息卡：头像在左，姓名/学号/班级在右，App 图标收尾。
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.student});

  final StudentInfo student;

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final name = student.xm.isNotEmpty ? student.xm : '同学';
    final xbLabel = student.xbLabel;
    final xh = student.xh;
    final bjmc = student.bjmc;

    return InkCard(
      padding: const EdgeInsets.all(InkSpacing.xl),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              name.characters.first,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: InkSpacing.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tsTitle,
                      ),
                    ),
                    if (xbLabel.isNotEmpty) ...[
                      const SizedBox(width: InkSpacing.s),
                      InkTag(text: xbLabel, tone: InkTone.info),
                    ],
                  ],
                ),
                if (xh.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(xh, style: context.tsSecondary),
                ],
                if (bjmc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    bjmc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tsSecondary,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: InkSpacing.s),
          ClipRRect(
            borderRadius: BorderRadius.circular(InkRadius.control),
            child: Image.asset(
              'assets/app_icon.png',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry {
  const _Entry(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}
