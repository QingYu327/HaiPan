import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../theme/ink_tokens.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_page.dart';

/// 首次启动的功能引导页：介绍主要功能，点击"开始使用"后进入登录
class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget item(IconData icon, String title, String subtitle, bool last) {
      return InkSettingTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        iconTone: InkTone.info,
        showDivider: !last,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            InkSpacing.xxl,
            InkSpacing.xl,
            InkSpacing.xxl,
            InkSpacing.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: InkSpacing.xxl),
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              'assets/app_icon.png',
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: InkSpacing.l),
                        Text(
                          '海畔',
                          textAlign: TextAlign.center,
                          style: context.tsTitle,
                        ),
                        const SizedBox(height: InkSpacing.xs),
                        Text(
                          '把课表、成绩与考试装进口袋',
                          textAlign: TextAlign.center,
                          style: context.tsSecondary,
                        ),
                        const SizedBox(height: InkSpacing.xxl),
                        InkCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              item(
                                AppIcons.notifications,
                                '提醒与直达',
                                '上课、考试提醒，点通知直接看课程与考场',
                                false,
                              ),
                              item(
                                AppIcons.widget,
                                '桌面小组件',
                                '仅课表 / 课表 + 考试两种组件，随桌面大小自适应',
                                false,
                              ),
                              item(
                                AppIcons.grade,
                                '成绩与学业',
                                '成绩构成、绩点与通识拓展学分一目了然',
                                false,
                              ),
                              item(
                                AppIcons.shield,
                                '隐私保护',
                                '学号全程脱敏，教务数据只保存在本机',
                                true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: InkSpacing.l),
              FilledButton(
                onPressed: () =>
                    ref.read(settingsProvider.notifier).setOnboardingDone(),
                child: const Text('开始使用'),
              ),
              const SizedBox(height: InkSpacing.s),
              Text(
                '首次使用需登录教务系统，数据仅保存在本机',
                textAlign: TextAlign.center,
                style: context.tsCaption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
