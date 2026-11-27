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
  CouplePartner _partner = const CouplePartner();
  List<CoupleCourse> _mine = const [];
  String _nickname = 'TA';
  String? _code;
  int _week = 1;
  int _day = todayWeekday();
  int _view = 0; // 0 我 / 1 TA / 2 合看
  Timer? _codeTimer;
  Timer? _pairPoll;
  int _codeLeft = 0;
  bool _betaClosed = false;

  @override
  void initState() {
    super.initState();
    _week = coupleCurrentWeek(ref.read(termProvider('timetable')));
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
      final status = await CoupleApi.status(_xh);
      var mine = _mine;
      var partner = _partner;
      if (status.paired) {
        final timetable = await ref.read(timetableProvider.future);
        mine = coupleCoursesOf(timetable.courses);
        await CoupleApi.setMyCourses(mine);
        await CoupleApi.startSyncListener();
        if (forceSync) {
          await CoupleApi.sync(_xh, mine);
          AppLog.d('情侣课表', '已同步我的课表 ${mine.length} 门');
        }
        partner = await CoupleApi.partner(_xh);
      } else {
        await CoupleApi.stopSyncListener();
        mine = const [];
        partner = const CouplePartner();
      }
      if (!mounted) return false;
      setState(() {
        _status = status;
        _mine = mine;
        _partner = partner;
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
        _partner = const CouplePartner();
        _mine = const [];
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
                    const InkSectionHeader(title: '说明'),
                    _privacyCard(context),
                  ] else ...[
                    _pairCard(context),
                    const SizedBox(height: InkSpacing.m),
                    _viewCard(context),
                    if (_status!.partnerStale)
                      _staleBanner(context)
                    else if (_view == 2)
                      _freeCard(context),
                    const SizedBox(height: InkSpacing.m),
                    _courseSection(context),
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
            '双方连接同一 Wi-Fi 或热点后，生成 6 位配对码并让对方输入，'
            '即可完成一对一绑定。只同步课名、时间、地点与周次，'
            '不传学号、姓名、教师或成绩。',
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

  Widget _privacyCard(BuildContext context) {
    return InkCard(
      child: Text(
        '配对关系是一对一的，解除后需要重新配对才能继续同步。'
        '配对与同步均在本地局域网内完成，不上传到服务器。'
        '对方仅能查看你共享的课表快照，看不到学号、姓名、教师与成绩。',
        style: context.tsSecondary.copyWith(height: 1.65),
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

  Widget _staleBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: InkSpacing.s),
      child: InkCard(
        tone: InkTone.warning,
        child: Text(
          '对方的课表超过 7 天未同步，暂不计算共同空闲。让对方打开情侣课表刷新一次即可。',
          style: context.tsSecondary.copyWith(height: 1.5),
        ),
      ),
    );
  }

  Widget _freeCard(BuildContext context) {
    final free = freeSections(_mine, _partner.courses, _day, _week);
    return Padding(
      padding: const EdgeInsets.only(top: InkSpacing.s),
      child: InkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当天的共同空闲', style: context.tsBodyStrong),
            const SizedBox(height: InkSpacing.xs),
            Text(
              free.isEmpty
                  ? '这节课表上没有共同空闲节次'
                  : free.map((e) => '第${e.$1}-${e.$2}节').join('、'),
              style: context.tsSecondary.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewCard(BuildContext context) {
    final cs = context.scheme;
    return InkCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(InkSpacing.m),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(value: 0, label: Text('我')),
                ButtonSegment(value: 1, label: Text('TA')),
                ButtonSegment(value: 2, label: Text('合看')),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: InkSpacing.s,
              vertical: InkSpacing.xs,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: '上一周',
                  onPressed: _week > 1 ? () => setState(() => _week -= 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('第 $_week 周', style: context.tsBodyStrong),
                      Text('切换周次查看对应课程', style: context.tsCaption),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '下一周',
                  onPressed: _week < 30 ? () => setState(() => _week += 1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: InkSpacing.m),
              children: [
                for (var d = 1; d <= 7; d++)
                  Padding(
                    padding: const EdgeInsets.only(right: InkSpacing.s),
                    child: ChoiceChip(
                      label: Text(const ['一', '二', '三', '四', '五', '六', '日'][d - 1]),
                      selected: _day == d,
                      onSelected: (_) => setState(() => _day = d),
                      labelStyle: TextStyle(
                        color: _day == d ? cs.onPrimaryContainer : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: InkSpacing.s),
        ],
      ),
    );
  }

  Widget _courseSection(BuildContext context) {
    final groups = _view == 2 ? _mergedGroups() : null;
    final list = _view == 0
        ? _mineOfDay()
        : _view == 1
            ? _partnerOfDay()
            : const <CoupleCourse>[];
    final hasAny = groups != null ? groups.isNotEmpty : list.isNotEmpty;
    if (!hasAny) {
      return InkCard(
        child: Text(
          _view == 2
              ? '双方当天都没有课程'
              : (_view == 0 ? '我当天没有课程' : '$_nickname 当天没有课程'),
          style: context.tsSecondary,
        ),
      );
    }
    if (groups != null) {
      return Column(
        children: [
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: InkSpacing.s),
              child: g.length == 1
                  ? _CourseCard(
                      course: g.first.c,
                      mine: g.first.mine,
                      nickname: _nickname,
                      showOwner: true,
                    )
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _CourseCard(
                              course: g[0].c,
                              mine: g[0].mine,
                              nickname: _nickname,
                              showOwner: true,
                              compact: true,
                            ),
                          ),
                          const SizedBox(width: InkSpacing.s),
                          Expanded(
                            child: _CourseCard(
                              course: g[1].c,
                              mine: g[1].mine,
                              nickname: _nickname,
                              showOwner: true,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
        ],
      );
    }
    return Column(
      children: [
        for (final c in list)
          Padding(
            padding: const EdgeInsets.only(bottom: InkSpacing.s),
            child: _CourseCard(
              course: c,
              mine: _view == 0,
              nickname: _nickname,
              showOwner: false,
            ),
          ),
      ],
    );
  }

  List<CoupleCourse> _mineOfDay() => _mine
      .where((c) => c.weekday == _day && c.activeInWeek(_week))
      .toList()
    ..sort((a, b) => a.startSection.compareTo(b.startSection));

  List<CoupleCourse> _partnerOfDay() => _partner.courses
      .where((c) => c.weekday == _day && c.activeInWeek(_week))
      .toList()
    ..sort((a, b) => a.startSection.compareTo(b.startSection));

  List<List<_OwnerCourse>> _mergedGroups() {
    final all = <_OwnerCourse>[
      for (final c in _mineOfDay()) _OwnerCourse(c, true),
      for (final c in _partnerOfDay()) _OwnerCourse(c, false),
    ]..sort((a, b) => a.c.startSection.compareTo(b.c.startSection));
    final groups = <List<_OwnerCourse>>[];
    for (final e in all) {
      List<_OwnerCourse>? target;
      for (final g in groups) {
        if (g.length >= 2) continue;
        if (g.any((x) => _overlap(x.c, e.c))) {
          target = g;
          break;
        }
      }
      if (target != null) {
        target.add(e);
      } else {
        groups.add([e]);
      }
    }
    groups.sort((a, b) => a.first.c.startSection.compareTo(b.first.c.startSection));
    return groups;
  }

  static bool _overlap(CoupleCourse a, CoupleCourse b) =>
      a.startSection <= b.endSection && b.startSection <= a.endSection;

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

class _OwnerCourse {
  final CoupleCourse c;
  final bool mine;
  const _OwnerCourse(this.c, this.mine);
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.mine,
    required this.nickname,
    required this.showOwner,
    this.compact = false,
  });

  final CoupleCourse course;
  final bool mine;
  final String nickname;
  final bool showOwner;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final accent = mine ? cs.primary : const Color(0xFF4FA8F5);
    return InkCard(
      padding: EdgeInsets.symmetric(
        horizontal: InkSpacing.m,
        vertical: compact ? InkSpacing.s : InkSpacing.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showOwner) ...[
            Text(
              mine ? '我' : nickname,
              style: context.tsCaption.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            course.name,
            maxLines: compact ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: context.tsBodyStrong.copyWith(fontSize: compact ? 13.5 : null),
          ),
          const SizedBox(height: 4),
          Text(
            '第${course.startSection}-${course.endSection}节',
            style: context.tsCaption.copyWith(color: accent),
          ),
          if (course.room.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              course.room,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.tsCaption,
            ),
          ],
        ],
      ),
    );
  }
}
