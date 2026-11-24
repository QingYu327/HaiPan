import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/data_providers.dart';
import '../../providers/session_provider.dart';
import '../../theme/ink_tokens.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_panel.dart';

/// 云端准入未开放时的整页提示：默认拒绝，等待管理员在名单中开通。
class AccessDeniedPage extends ConsumerWidget {
  const AccessDeniedPage({super.key});

  Future<void> _recheck(BuildContext context, WidgetRef ref) async {
    ref.invalidate(appAccessProvider);
    try {
      final ok = await ref.read(appAccessProvider.future);
      if (!context.mounted) return;
      showInkToast(context, ok ? '权限已开通，欢迎使用' : '仍未开通，请联系管理员');
    } catch (_) {
      if (context.mounted) showInkToast(context, '校验失败，请检查网络', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.scheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(InkSpacing.xl),
            child: InkGlassPanel(
              padding: const EdgeInsets.all(InkSpacing.xl),
              borderRadius: BorderRadius.circular(InkRadius.card),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(AppIcons.lock, size: 30, color: cs.error),
                    ),
                  ),
                  const SizedBox(height: InkSpacing.l),
                  Text(
                    '使用权限未开放',
                    textAlign: TextAlign.center,
                    style: context.tsBodyStrong.copyWith(
                      fontSize: InkTextStyles.title.fontSize,
                    ),
                  ),
                  const SizedBox(height: InkSpacing.m),
                  Text(
                    '拒绝原因：当前账号不在使用名单内。\n请联系管理员开通后再次校验。',
                    textAlign: TextAlign.center,
                    style: context.tsSecondary,
                  ),
                  const SizedBox(height: InkSpacing.xl),
                  FilledButton(
                    onPressed: () => _recheck(context, ref),
                    child: const Text('重新校验'),
                  ),
                  const SizedBox(height: InkSpacing.s),
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(sessionProvider.notifier).logout(),
                    child: const Text('退出登录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 准入校验中的占位：只显示一个轻量的进度指示。
class AccessChecking extends StatelessWidget {
  const AccessChecking({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}
