import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/session_provider.dart';
import '../../theme/ink_page_transition.dart';
import '../../theme/ink_tokens.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_page.dart';
import 'sso_login_page.dart';

/// 登录页：仅保留统一身份认证入口。
/// 上次登录过时，首次进入会自动打开认证页尝试静默续期（学校会话仍有效则无感登录）。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.showGuestButton = true});

  /// 从页面内「去登录」进入时不再显示游客按钮。
  final bool showGuestButton;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: InkMotion.normal,
  )..forward();

  bool _opening = false;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoRestore());
  }

  /// 冷启动会话过期但上次是 SSO 登录：自动打开认证页，
  /// 认证中心仍记得登录态时会直接回跳，无需再输账号密码。
  Future<void> _autoRestore() async {
    if (_autoTried || !mounted) return;
    _autoTried = true;
    final canSilent = await ref.read(sessionProvider.notifier).canSilentSso();
    if (canSilent && mounted) _openSso();
  }

  Future<void> _openSso() async {
    if (_opening) return;
    setState(() => _opening = true);
    final ok = await Navigator.of(context).push<bool>(
      InkPageRoute(builder: (_) => const SsoLoginPage()),
    );
    if (!mounted) return;
    setState(() => _opening = false);
    if (ok == true) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: InkSpacing.xxl,
              vertical: InkSpacing.xxl,
            ),
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _entrance,
                curve: InkMotion.standard,
              ),
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _entrance,
                  curve: InkMotion.standard,
                )),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: InkSpacing.xxxl),
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/app_icon.png',
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: InkSpacing.l),
                    Text(
                      '海畔',
                      textAlign: TextAlign.center,
                      style: context.tsDisplay,
                    ),
                    const SizedBox(height: InkSpacing.xxxl),
                    _SsoPanel(busy: _opening, onTap: _openSso),
                    if (widget.showGuestButton) ...[
                      const SizedBox(height: InkSpacing.l),
                      OutlinedButton(
                        onPressed: () =>
                            ref.read(sessionProvider.notifier).enterGuest(),
                        child: const Text('以游客身份浏览'),
                      ),
                    ],
                    const SizedBox(height: InkSpacing.l),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一身份认证入口卡片
class _SsoPanel extends StatelessWidget {
  const _SsoPanel({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InkIconBadge(icon: AppIcons.shield, tone: InkTone.info),
              const SizedBox(width: InkSpacing.m),
              Expanded(
                child: Text('统一身份认证', style: context.tsBodyStrong),
              ),
            ],
          ),
          const SizedBox(height: InkSpacing.l),
          FilledButton(
            onPressed: busy ? null : onTap,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('前往认证页'),
          ),
        ],
      ),
    );
  }
}
