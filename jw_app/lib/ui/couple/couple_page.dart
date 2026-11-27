import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/couple_api.dart';
import '../../models/couple_models.dart';
import '../../providers/data_providers.dart';
import '../../providers/session_provider.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ink_dialog.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

/// 情侣课表：6 位配对码建立一对一绑定，仅同步课名/时间/地点/周次。
class CouplePage extends ConsumerStatefulWidget {
  const CouplePage({super.key});

  @override
  ConsumerState<CouplePage> createState() => _CouplePageState();
}

class _CouplePageState extends ConsumerState<CouplePage> {
  static const _nickKey = 'couple.nickname';
  static const _betaKey = 'couple.beta_closed';


  final _codeCtrl = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  CoupleStatus? _status;
  String _nickname = 'TA';
  String? _code;
  Timer? _codeTimer;
  Timer? _pairPoll;
  int _codeLeft = 0;
  bool _betaClosed = false;
  bool _codeDialogOpen = false; // 配对码弹窗是否仍在前台

  @override
  void initState() {
    super.initState();
    _loadNickname();
    _loadBetaDismissed();
    _refresh();
  }

  @override
  void dispose() {
    _codeTimer?.cancel();
    _pairPoll?.cancel();
    CoupleApi.stopAll();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNickname() async {
    final p = await SharedPreferences.getInstance();
    final name = p.getString(_nickKey);
    if (mounted && name != null && name.trim().isNotEmpty) {
      setState(() => _nickname = name.trim());
    }
  }

  Future<void> _loadBetaDismissed() async {
    final p = await SharedPreferences.getInstance();
    final closed = p.getBool(_betaKey) ?? false;
    if (mounted && closed) setState(() => _betaClosed = true);
  }

  Future<void> _closeBeta() async {
    setState(() => _betaClosed = true);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_betaKey, true);
  }

  String get _xh => ref.read(sessionProvider).student.xh.trim();

  Future<bool> _refresh({
    bool forceSync = false,
    bool fromPull = false,
  }) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      if (_xh.isEmpty) throw const CoupleException('no_login', '请先登录后再使用情侣课表');
      var status = await CoupleApi.status(_xh);
      if (status.paired) {
        final timetable = await ref.read(timetableProvider.future);
        final mine = coupleCoursesOf(timetable.courses);
        await CoupleApi.setMyCourses(mine);
        await CoupleApi.startSyncListener();
        if (forceSync) {
          await CoupleApi.sync(_xh, mine);
          AppLog.d('情侣课表', '已同步我的课表 ${mine.length} 门');
          // 同步会写入新的更新时刻，重读状态让页面上的时间戳立即刷新
          status = await CoupleApi.status(_xh);
        }
      } else {
        await CoupleApi.stopSyncListener();
      }
      if (!mounted) return false;
      setState(() {
        _status = status;
        _loading = false;
      });
      return true;
    } on CoupleException catch (e) {
      if (!mounted) return false;
      setState(() => _loading = false);
      if (fromPull) rethrow;
      showInkToast(context, e.message, error: true);
      return false;
    } catch (e) {
      AppLog.e('情侣课表', '刷新失败：$e');
      if (!mounted) return false;
      setState(() => _loading = false);
      if (fromPull) rethrow;
      showInkToast(context, '局域网操作失败，请检查双方网络后重试', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    final ok = await _refresh(forceSync: true);
    if (ok && mounted) showInkToast(context, '课表已同步');
  }

  Future<void> _createCode() async {
    if (_busy) return;
    if (_xh.isEmpty) {
      showInkToast(context, '请先登录后再使用情侣课表');
      return;
    }
    setState(() => _busy = true);
    try {
      final timetable = await ref.read(timetableProvider.future);
      final mine = coupleCoursesOf(timetable.courses);
      final code = await CoupleApi.createCode(_xh, mine);
      if (!mounted) return;
      setState(() {
        _code = code;
        _codeLeft = 600;
      });
      _startCodeTimer();
      _startPairPoll();
      await _showCodeDialog(code);
    } on CoupleException catch (e) {
      if (mounted) showInkToast(context, e.message, error: true);
    } catch (e) {
      AppLog.e('情侣课表', '发起局域网配对失败：$e');
      if (mounted) showInkToast(context, '发起失败，请检查网络后重试', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startPairPoll() {
    _pairPoll?.cancel();
    _pairPoll = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!mounted) return t.cancel();
      final s = await CoupleApi.status(_xh);
      if (!s.paired) return;
      t.cancel();
      _codeTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _code = null;
        _codeLeft = 0;
      });
      // 对方已完成配对：自动收起仍在展示的配对码弹窗
      if (_codeDialogOpen && mounted) {
        _codeDialogOpen = false;
        Navigator.of(context).pop();
      }
      showInkToast(context, '配对成功');
      setState(() => _busy = false);
      await _refresh();
    });
  }

  void _startCodeTimer() {
    _codeTimer?.cancel();
    _codeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_codeLeft <= 1) {
        t.cancel();
        _pairPoll?.cancel();
        CoupleApi.cancelPairing();
        setState(() {
          _code = null;
          _codeLeft = 0;
        });
      } else {
        setState(() => _codeLeft -= 1);
      }
    });
  }

  Future<void> _showCodeDialog(String code) async {
    _codeDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('配对码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                code,
                style: context.tabular.copyWith(
                  fontSize: 34,
                  letterSpacing: 6,
                  fontWeight: FontWeight.w700,
                  color: context.scheme.primary,
                ),
              ),
              const SizedBox(height: InkSpacing.s),
              Text(
                '10 分钟内有效。请让对方连接同一 Wi-Fi 或热点，'
                '在情侣课表页输入配对码。',
                textAlign: TextAlign.center,
                style: context.tsSecondary,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) showInkToast(context, '配对码已复制');
              },
              child: const Text('复制'),
            ),
          ],
        ),
      );
    } finally {
      _codeDialogOpen = false;
    }
  }

  Future<void> _bind() async {
    if (_xh.isEmpty) {
      showInkToast(context, '请先登录后再使用情侣课表');
      return;
    }
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      showInkToast(context, '请输入 6 位数字配对码');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final timetable = await ref.read(timetableProvider.future);
      final mine = coupleCoursesOf(timetable.courses);
      await CoupleApi.bind(_xh, code, mine);
      _codeCtrl.clear();
      if (!mounted) return;
      showInkToast(context, '配对成功');
      // 先结束忙碌态，否则 _refresh 会被 _busy 守卫直接跳过，
      // 导致绑定成功后页面仍停留在未配对状态。
      setState(() => _busy = false);
      await _refresh();
    } on CoupleException catch (e) {
      if (mounted) showInkToast(context, e.message, error: true);
    } catch (e) {
      AppLog.e('情侣课表', '加入局域网配对失败：$e');
      if (mounted) showInkToast(context, '加入失败，请确认双方在同一网络', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unbind() async {
    final ok = await showInkDialog(
      context,
      title: '解除配对',
      message: '解除后本机将清除对方课表，需要重新配对才能继续同步。',
      confirmText: '解除',
      danger: true,
    );
    if (!ok || _busy) return;
    setState(() => _busy = true);
    try {
      await CoupleApi.unbind(_xh);
      if (!mounted) return;
      showInkToast(context, '已解除配对');
      setState(() {
        _status = const CoupleStatus(paired: false);
        _code = null;
      });
    } on CoupleException catch (e) {
      if (mounted) showInkToast(context, e.message, error: true);
    } catch (e) {
      AppLog.e('情侣课表', '解除配对失败：$e');
      if (mounted) showInkToast(context, '解除失败，请稍后重试', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editNickname() async {
    final ctrl = TextEditingController(text: _nickname);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('对方昵称'),
        content: TextField(
          controller: ctrl,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '仅保存在本机，默认 TA'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty || name == _nickname) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_nickKey, name);
    if (mounted) {
      setState(() => _nickname = name);
      showInkToast(context, '昵称已保存');
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkPageScaffold(
      showBack: true,
      title: '情侣课表',
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(InkSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          : InkRefresh(
              onRefresh: () async {
                await _refresh(forceSync: true, fromPull: true);
              },
              successMessage: '情侣课表已刷新',
              child: ListView(
                primary: false,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  0,
                  inkPagePadding(context).bottom,
                ),
                children: [
                  if (!_betaClosed) ...[
                    _betaBanner(context),
                    const SizedBox(height: InkSpacing.s),
                  ],
                  if (_status?.paired != true) ...[
                    _introCard(context),
                    const InkSectionHeader(title: '输入对方的配对码'),
                    _bindCard(context),
                  ] else ...[
                    _pairCard(context),
                    const SizedBox(height: InkSpacing.m),
                    _homeHint(context),
                    if (_status!.partnerStale) _staleNote(context),
                  ],
                  const SizedBox(height: InkSpacing.l),
                ],
              ),
            ),
    );
  }

  Widget _betaBanner(BuildContext context) {
    return InkCard(
      tone: InkTone.warning,
      padding: const EdgeInsets.fromLTRB(
        InkSpacing.m,
        InkSpacing.xs,
        InkSpacing.xs,
        InkSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            AppIcons.info,
            size: 16,
            color: inkToneColor(context, InkTone.warning),
          ),
          const SizedBox(width: InkSpacing.s),
          Expanded(
            child: Text(
              '此为新增功能，使用稳定性待测试',
              style: context.tsSecondary,
            ),
          ),
          IconButton(
            onPressed: _closeBeta,
            icon: const Icon(AppIcons.close, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  Widget _introCard(BuildContext context) {
    final cs = context.scheme;
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.groups, color: cs.primary, size: 20),
              const SizedBox(width: InkSpacing.s),
              Text('和 TA 的课表放在一起', style: context.tsBodyStrong),
            ],
          ),
          const SizedBox(height: InkSpacing.m),
          Text(
            '连接同一 Wi-Fi 或热点，生成 6 位配对码，让对方在情侣课表输入即可完成配对。',
            style: context.tsSecondary.copyWith(height: 1.6),
          ),
          const SizedBox(height: InkSpacing.l),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _createCode,
              icon: const Icon(Icons.link_rounded, size: 18),
              label: Text(_code == null ? '生成配对码' : '重新生成配对码'),
            ),
          ),
          if (_code != null) ...[
            const SizedBox(height: InkSpacing.m),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _code!,
                  style: context.tabular.copyWith(
                    fontSize: 30,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
                IconButton(
                  tooltip: '复制',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _code!));
                    if (context.mounted) showInkToast(context, '配对码已复制');
                  },
                  icon: const Icon(AppIcons.copy, size: 20),
                ),
              ],
            ),
            Text(
              '剩余 ${(_codeLeft ~/ 60)}:${(_codeLeft % 60).toString().padLeft(2, '0')} · 10 分钟内有效',
              style: context.tsCaption,
            ),
          ],
        ],
      ),
    );
  }

  Widget _bindCard(BuildContext context) {
    return InkCard(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              onSubmitted: (_) => _bind(),
              decoration: const InputDecoration(
                hintText: '6 位数字',
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: InkSpacing.m),
          FilledButton(
            onPressed: _busy ? null : _bind,
            child: Text(_busy ? '处理中…' : '绑定'),
          ),
        ],
      ),
    );
  }

  Widget _pairCard(BuildContext context) {
    final cs = context.scheme;
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.groups, color: cs.primary, size: 20),
              const SizedBox(width: InkSpacing.s),
              Expanded(
                child: Text('与 $_nickname 已配对', style: context.tsBodyStrong),
              ),
              IconButton(
                tooltip: '修改昵称',
                onPressed: _editNickname,
                icon: const Icon(AppIcons.edit, size: 19),
              ),
            ],
          ),
          const SizedBox(height: InkSpacing.s),
          Text(
            '我：${_fmtUpdated(_status!.myUpdatedAt)} · '
            '$_nickname：${_fmtUpdated(_status!.partnerUpdatedAt)}',
            style: context.tsCaption.copyWith(height: 1.5),
          ),
          const SizedBox(height: InkSpacing.m),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _syncNow,
                  icon: const Icon(AppIcons.refresh, size: 17),
                  label: const Text('同步课表'),
                ),
              ),
              const SizedBox(width: InkSpacing.s),
              TextButton(
                onPressed: _busy ? null : _unbind,
                child: Text('解除配对', style: TextStyle(color: cs.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 配对上后的简短提示：课表已移到首页
  Widget _homeHint(BuildContext context) {
    return InkCard(
      child: Row(
        children: [
          Icon(AppIcons.timetable, size: 20, color: context.scheme.primary),
          const SizedBox(width: InkSpacing.s),
          Expanded(
            child: Text(
              '课表已放到首页，可用「我 / TA / 合看」切换查看。',
              style: context.tsSecondary.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staleNote(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: InkSpacing.s),
      child: InkCard(
        tone: InkTone.warning,
        child: Text(
          '对方课表超过 7 天未同步，首页的 TA 课程可能不是最新。',
          style: context.tsSecondary.copyWith(height: 1.5),
        ),
      ),
    );
  }

  String _fmtUpdated(int ms) {
    if (ms <= 0) return '尚未同步';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(d.hour)}:${two(d.minute)}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '今天 $hm';
    }
    return '${d.month}/${d.day} $hm';
  }
}

