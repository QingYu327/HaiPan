import 'package:flutter/material.dart';

import '../../theme/ink_tokens.dart';
import 'app_icons.dart';

/// 仿 iOS 确认弹窗：居中、窄（≈270）、圆角 14，按钮等宽横排。
///
/// 只用于确认 / 危险操作；轻提示走 `showInkNotice`。
/// 危险项（删除、退出）把 [danger] 置 true，确认按钮使用朱砂色。
/// 进出场参考 Android 17：淡入 + 0.92→1 弹性缩放。
Future<bool> showInkDialog(
  BuildContext context, {
  required String title,
  String? message,
  String cancelText = '取消',
  String confirmText = '确定',
  bool danger = false,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '关闭',
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: InkMotion.normal,
    pageBuilder: (ctx, _, _) => _InkDialog(
      title: title,
      message: message,
      cancelText: cancelText,
      confirmText: confirmText,
      danger: danger,
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: InkMotion.standard,
        reverseCurve: Curves.easeInCubic,
      );
      // 缩放允许轻微越界，形成落定回弹；透明度单独走缓出曲线。
      final spring = CurvedAnimation(
        parent: animation,
        curve: InkMotion.spring,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(spring),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
}

class _InkDialog extends StatelessWidget {
  const _InkDialog({
    required this.title,
    required this.message,
    required this.cancelText,
    required this.confirmText,
    required this.danger,
  });

  final String title;
  final String? message;
  final String cancelText;
  final String confirmText;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = context.ink;
    final confirmColor = danger ? ink.danger : scheme.primary;

    return Center(
      child: Dialog(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          width: 270,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ink.hairline, width: InkStroke.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: InkTextStyles.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(
                height: InkStroke.hairline,
                thickness: InkStroke.hairline,
              ),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      child: _DialogAction(
                        label: cancelText,
                        color: scheme.onSurfaceVariant,
                        onTap: () => Navigator.pop(context, false),
                      ),
                    ),
                    SizedBox(
                      height: 24,
                      child: VerticalDivider(
                        width: InkStroke.hairline,
                        thickness: InkStroke.hairline,
                      ),
                    ),
                    Expanded(
                      child: _DialogAction(
                        label: confirmText,
                        color: confirmColor,
                        onTap: () => Navigator.pop(context, true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogAction extends StatelessWidget {
  const _DialogAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// 操作引导弹窗：图标 + 标题 + 说明 + 编号步骤，视觉与 [showInkDialog] 一致。
///
/// 用于「需要用户手动完成某些系统操作」的场景（如添加桌面小组件），
/// 返回 true 表示用户点了确认按钮。
Future<bool> showInkGuideDialog(
  BuildContext context, {
  required String title,
  String? message,
  IconData icon = AppIcons.widget,
  List<String> steps = const [],
  String cancelText = '取消',
  String confirmText = '知道了',
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '关闭',
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: InkMotion.normal,
    pageBuilder: (ctx, _, _) => _InkGuideDialog(
      title: title,
      message: message,
      icon: icon,
      steps: steps,
      cancelText: cancelText,
      confirmText: confirmText,
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: InkMotion.standard,
        reverseCurve: Curves.easeInCubic,
      );
      final spring = CurvedAnimation(
        parent: animation,
        curve: InkMotion.spring,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(spring),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
}

class _InkGuideDialog extends StatelessWidget {
  const _InkGuideDialog({
    required this.title,
    required this.message,
    required this.icon,
    required this.steps,
    required this.cancelText,
    required this.confirmText,
  });

  final String title;
  final String? message;
  final IconData icon;
  final List<String> steps;
  final String cancelText;
  final String confirmText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = context.ink;

    return Center(
      child: Dialog(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          width: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ink.hairline, width: InkStroke.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(InkRadius.control),
                      ),
                      child: Icon(icon, size: 24, color: scheme.primary),
                    ),
                    const SizedBox(height: InkSpacing.m),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: InkTextStyles.section.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: InkTextStyles.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (steps.isNotEmpty) ...[
                      const SizedBox(height: InkSpacing.m),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(InkSpacing.m),
                        decoration: BoxDecoration(
                          color: ink.groupedBackground,
                          borderRadius: BorderRadius.circular(
                            InkRadius.control,
                          ),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < steps.length; i++)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: i == steps.length - 1
                                      ? 0
                                      : InkSpacing.s,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 18,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: scheme.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${i + 1}',
                                        style: InkTextStyles.nano.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: InkSpacing.s),
                                    Expanded(
                                      child: Text(
                                        steps[i],
                                        style: InkTextStyles.caption.copyWith(
                                          color: scheme.onSurface,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(
                height: InkStroke.hairline,
                thickness: InkStroke.hairline,
              ),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      child: _DialogAction(
                        label: cancelText,
                        color: scheme.onSurfaceVariant,
                        onTap: () => Navigator.pop(context, false),
                      ),
                    ),
                    SizedBox(
                      height: 24,
                      child: VerticalDivider(
                        width: InkStroke.hairline,
                        thickness: InkStroke.hairline,
                      ),
                    ),
                    Expanded(
                      child: _DialogAction(
                        label: confirmText,
                        color: scheme.primary,
                        onTap: () => Navigator.pop(context, true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
