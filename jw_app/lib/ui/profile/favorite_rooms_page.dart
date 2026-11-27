import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/jw_apis.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../../util/term_utils.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

/// 空教室查询（支持校区/楼号/类别下拉、周/星期/节次多选）+ 常用教室收藏
///
/// 收藏以卡片展示，点击查看使用情况，左滑删除；收藏按钮点一次收藏、再点一次取消。
class FavoriteRoomsPage extends ConsumerStatefulWidget {
  const FavoriteRoomsPage({super.key});

  @override
  ConsumerState<FavoriteRoomsPage> createState() => _FavoriteRoomsPageState();
}

class _FavoriteRoomsPageState extends ConsumerState<FavoriteRoomsPage> {
  static const _favKey = 'fav_rooms_v2';
  static const _favLegacyKey = 'fav_rooms_v1';
  static const _dayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  // 下拉选项（抓自教务页面）
  static const _xqhOptions = <(String, String)>[
    ('1', '湖光校区'),
    ('2', '海滨校区'),
    ('3', '霞山校区'),
    ('BBF8A51ACEA2144EE053768926D2788B', '阳江校区'),
  ];
  static const _lhOptions = <(String, String)>[
    ('', '全部'),
    ('1', '明德楼'),
    ('2', '望海楼'),
    ('3', '动物医院'),
    ('4', '工厂'),
    ('5', '图海楼'),
    ('6', '林果楼'),
    ('7', '轮机实验楼'),
    ('8', '艺海楼A'),
    ('9', '水产科技楼'),
    ('10', '体育场'),
    ('11', '图书馆（东区）'),
    ('12', '艺海楼B'),
    ('13', '兴海楼'),
    ('14', '兴教楼'),
    ('15', '兴农楼'),
    ('16', '艺海楼C'),
    ('17', '钟海楼'),
    ('18', '广学楼'),
    ('25', '体育馆'),
    ('26', '海科楼'),
    ('27', '海博楼'),
    ('28', '工程训练中心'),
    ('29', '动物科学基地'),
    ('30', '林学后山基地'),
    ('41', '博文楼'),
    ('55', '学生活动中心'),
    ('56', '海创楼'),
    ('00', '线上教学'),
    ('wlh', '无楼号'),
  ];
  static const _cdlbOptions = <(String, String)>[
    ('', '全部'),
    ('01', '多媒体教室'),
    ('02', '语音室'),
    ('03', '实验室'),
    ('04', '计算机房'),
    ('05', '普通教室'),
    ('09', '其它'),
    ('10', '画室'),
    ('11', '绘图教室'),
    ('12', '设计教室'),
    ('13', '声乐教室'),
    ('14', '键盘教室'),
    ('15', '琴房'),
    ('16', '舞蹈教室'),
    ('17', '操场'),
    ('18', '艺术类'),
    ('19', '录像'),
    ('20', '运动场'),
    ('C131816DD14314F1E053768926D2105C', '网络教室'),
    ('BECD43BC8A0C5B3EE053778926D27281', '智慧教室'),
  ];

  // 条件
  String _xqhId = '1';
  String _lh = '';
  String _categoryId = '01';
  final Set<int> _weeks = {};
  final Set<int> _weekdays = {};
  final Set<int> _jcds = {1};
  final GlobalKey _weekChipKey = GlobalKey();
  int _currentWeek = 1;
  final _nameCtrl = TextEditingController();

  // 结果
  List<EmptyRoom>? _rooms;
  bool _loading = false;
  String? _error;
  bool _unionUsed = false; // 是否走了"合并多时段"回退
  // 结果内快速筛选（不发请求，纯本地过滤）
  bool _onlyFree = false;
  final _resultCtrl = TextEditingController();

  List<EmptyRoom> get _filteredRooms {
    final kw = _resultCtrl.text.trim().toLowerCase();
    return [
      for (final r in _rooms ?? const <EmptyRoom>[])
        if ((!_onlyFree || r.available) &&
            (kw.isEmpty ||
                r.cdmc.toLowerCase().contains(kw) ||
                r.jxlmc.toLowerCase().contains(kw) ||
                r.cdlbmc.toLowerCase().contains(kw)))
          r,
    ];
  }

  /// 按教学楼分组，组内按教室名自然排序（102 在 99 之后）
  Map<String, List<EmptyRoom>> get _groupedRooms {
    final map = <String, List<EmptyRoom>>{};
    for (final r in _filteredRooms) {
      final key = r.jxlmc.trim().isEmpty ? '未标注教学楼' : r.jxlmc.trim();
      (map[key] ??= []).add(r);
    }
    for (final list in map.values) {
      list.sort((a, b) => _naturalCompare(a.cdmc, b.cdmc));
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => _naturalCompare(a.key, b.key)),
    );
  }

  // 收藏
  final _favCtrl = TextEditingController();
  List<EmptyRoom> _favRooms = [];

  @override
  void initState() {
    super.initState();
    _currentWeek = TermUtils.estimatedCurrentWeek(TermUtils.currentTerm()) ?? 1;
    _weeks.add(_currentWeek);
    _weekdays.add(DateTime.now().weekday);
    _loadFav();
    // 等页面进场稳定后，把周次横向列表滚到当前周，免去手动翻找。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 320), () {
        if (mounted) _focusCurrentWeek();
      });
    });
  }

  void _focusCurrentWeek() {
    final ctx = _weekChipKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 320),
      curve: InkMotion.standard,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _favCtrl.dispose();
    _resultCtrl.dispose();
    super.dispose();
  }

  // ---------------- 收藏读写（迁移旧版纯字符串） ----------------
  Future<void> _loadFav() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_favKey);
    var fav = <EmptyRoom>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List);
        fav = [
          for (final e in list)
            EmptyRoom.fromMap(Map<String, dynamic>.from(e as Map)),
        ];
      } catch (_) {
        fav = const [];
      }
    }
    // 旧版（纯字符串列表）迁移
    if (fav.isEmpty) {
      final legacy = p.getStringList(_favLegacyKey) ?? const [];
      if (legacy.isNotEmpty) {
        fav = [
          for (final s in legacy) EmptyRoom.fromMap({'cdmc': s}),
        ];
        await p.remove(_favLegacyKey);
        await _saveFav(fav);
      }
    }
    if (mounted) setState(() => _favRooms = fav);
  }

  Future<void> _saveFav(List<EmptyRoom> fav) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_favKey, jsonEncode([for (final r in fav) r.toMap()]));
  }

  bool _sameRoom(EmptyRoom a, EmptyRoom b) =>
      (a.cdbh.isNotEmpty && b.cdbh.isNotEmpty && a.cdbh == b.cdbh) ||
      a.cdmc == b.cdmc;

  /// 收藏开关：点一次收藏，再点一次取消
  Future<void> _toggleFav(EmptyRoom r) async {
    final wasFav = _favRooms.any((f) => _sameRoom(f, r));
    setState(() {
      if (wasFav) {
        _favRooms = _favRooms.where((f) => !_sameRoom(f, r)).toList();
        AppLog.d('空教室', '取消收藏 ${r.cdmc}');
      } else {
        _favRooms = [..._favRooms, r];
        AppLog.d('空教室', '收藏 ${r.cdmc}');
      }
    });
    await _saveFav(_favRooms);
    if (!mounted) return;
    showInkToast(context, wasFav ? '已取消收藏 ${r.cdmc}' : '已收藏 ${r.cdmc}');
  }

  Future<void> _removeFav(EmptyRoom r) async {
    final before = _favRooms.length;
    setState(
      () => _favRooms = _favRooms.where((f) => !_sameRoom(f, r)).toList(),
    );
    await _saveFav(_favRooms);
    AppLog.d('空教室', '删除收藏 ${r.cdmc}（${before - _favRooms.length}>0）');
    if (mounted) showInkToast(context, '已删除收藏 ${r.cdmc}');
  }

  Future<void> _addFavByInput() async {
    final name = _favCtrl.text.trim();
    if (name.isEmpty) {
      showInkToast(context, '请输入教室名称');
      return;
    }
    _favCtrl.clear();
    await _toggleFav(EmptyRoom.fromMap({'cdmc': name}));
  }

  /// 多选 chip：点一次选中、再点一次取消
  void _toggle(Set<int> set, int v) {
    setState(() {
      if (set.contains(v)) {
        set.remove(v);
      } else {
        set.add(v);
      }
    });
  }

  // ---------------- 查询 ----------------
  /// 查询代号：用户连续改条件时，旧查询的结果直接丢弃，避免覆盖新结果
  int _searchGen = 0;

  // 极端情况收紧：多时段回退最多 12 组、每组只取 1 页、总耗时不超过 20 秒
  static const int _unionMaxCombos = 12;
  static const Duration _unionBudget = Duration(seconds: 20);
  static const Duration _unionInterval = Duration(milliseconds: 320);

  Future<void> _search() async {
    if (_weeks.isEmpty || _weekdays.isEmpty || _jcds.isEmpty) {
      showInkToast(context, '请至少选择周次、星期和节次各一项');
      return;
    }
    final gen = ++_searchGen;
    setState(() {
      _loading = true;
      _error = null;
      _rooms = null;
      _unionUsed = false;
    });
    AppLog.d(
      '空教室',
      '查询 周${_weeks.join(',')} 星期${_weekdays.join(',')} 节${_jcds.join(',')} 校区$_xqhId 楼$_lh 类别$_categoryId',
    );
    try {
      var list = await ref
          .read(emptyRoomApiProvider)
          .query(
            weeks: _weeks.toList()..sort(),
            weekdays: _weekdays.toList()..sort(),
            jcds: _jcds.toList()..sort(),
            categoryId: _categoryId,
            building: _lh,
            name: _nameCtrl.text.trim(),
            xqhId: _xqhId,
          );
      if (!mounted || gen != _searchGen) return;

      // 多条件（周/星期/节次任一项多选）且直接查询为空时：
      // 教务端按 "同时空闲(AND)" 判定，多选会让结果趋空。此时按单时段分别查询后合并（OR），
      // 只要在任意所选时段空闲即返回，解决"扩大筛选反而无数据"。
      if (list.isEmpty &&
          (_weeks.length > 1 || _weekdays.length > 1 || _jcds.length > 1)) {
        final merged = await _unionBroad();
        if (!mounted || gen != _searchGen) return;
        if (merged.isNotEmpty) {
          list = merged;
          _unionUsed = true;
        }
      }

      // 可用（可借）优先，其余在后
      final sorted = [...list]
        ..sort((a, b) {
          if (a.available == b.available) return 0;
          return a.available ? -1 : 1;
        });
      setState(() {
        _loading = false;
        _rooms = sorted;
      });
      if (list.isEmpty) {
        showInkToast(context, '未查到空闲教室');
      } else {
        showInkToast(
          context,
          _unionUsed
              ? '查到 ${sorted.length} 间空闲教室（已按所选时段合并）'
              : '查到 ${sorted.length} 间空闲教室',
        );
      }
      AppLog.d('空教室', '查询完成：${sorted.length} 间（合并=$_unionUsed）');
    } catch (e) {
      if (!mounted || gen != _searchGen) return;
      AppLog.e('空教室', '查询失败：$e');
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 均匀抽样：组合过多时也覆盖到后面的周次/时段，而不是只查前几个
  static List<T> _sampleEven<T>(List<T> src, int cap) {
    if (src.length <= cap) return src;
    final out = <T>[];
    for (var i = 0; i < cap; i++) {
      out.add(src[((i + 0.5) * src.length / cap).floor()]);
    }
    return out;
  }

  /// 按单时段组合查询后并集。
  /// 极端情况：所有维度全选会产生上千种组合，这里做三重收紧
  /// （最多 12 组、每组 1 页 100 间、总预算 20 秒、间隔 320ms）。
  Future<List<EmptyRoom>> _unionBroad() async {
    AppLog.d('空教室', '多选查询为空，尝试按单时段合并（限速）');
    final all = <String, EmptyRoom>{};
    // 周次优先当前周，最多取 2 个，避免跨 20 周乱查
    final weeks = (_weeks.toList()..sort()).take(2).toList();
    final weekdays = _weekdays.toList()..sort();
    final jcds = _jcds.toList()..sort();
    final combos = <(int, int, int)>[
      for (final w in weeks)
        for (final d in weekdays)
          for (final s in jcds) (w, d, s),
    ];
    final picked = _sampleEven(combos, _unionMaxCombos);
    final deadline = DateTime.now().add(_unionBudget);
    for (var i = 0; i < picked.length; i++) {
      if (DateTime.now().isAfter(deadline)) break;
      final (w, d, s) = picked[i];
      try {
        final r = await ref
            .read(emptyRoomApiProvider)
            .query(
              weeks: [w],
              weekdays: [d],
              jcds: [s],
              categoryId: _categoryId,
              building: _lh,
              name: _nameCtrl.text.trim(),
              xqhId: _xqhId,
              maxPages: 1,
              budget: const Duration(seconds: 8),
            );
        for (final e in r) {
          if (e.cdbh.isNotEmpty) all[e.cdbh] = e;
        }
      } catch (_) {
        // 单个时段失败不阻塞整体
      }
      if (i < picked.length - 1 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(_unionInterval);
      }
    }
    AppLog.d(
      '空教室',
      '单时段合并得到 ${all.length} 间（${picked.length}/${combos.length} 组）',
    );
    return all.values.toList();
  }

  // ---------------- 收藏使用情况弹层 ----------------
  void _showFavDetail(EmptyRoom r) {
    showInkSheet(
      context,
      title: r.cdmc,
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('点击下方按钮，按当前所选周次/星期/节次查看该教室是否空闲。', style: context.tsSecondary),
            const SizedBox(height: InkSpacing.l),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _checkFavUsage(r);
              },
              icon: const Icon(AppIcons.examEvent, size: 18),
              label: const Text('查看使用情况'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkFavUsage(EmptyRoom r) async {
    if (_weeks.isEmpty || _weekdays.isEmpty || _jcds.isEmpty) {
      showInkToast(context, '请先选择查询条件（周次/星期/节次各一项）');
      return;
    }
    AppLog.d('空教室', '查收藏使用情况 ${r.cdmc}');
    // 查询需 1~2s，先给转圈占位，避免"点了没反应"
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LoadingOverlay(message: '正在查询该教室使用情况…'),
    );
    try {
      final res = await ref
          .read(emptyRoomApiProvider)
          .query(
            weeks: _weeks.toList()..sort(),
            weekdays: _weekdays.toList()..sort(),
            jcds: _jcds.toList()..sort(),
            categoryId: _categoryId,
            building: _lh,
            name: r.cdmc,
            xqhId: _xqhId,
            maxPages: 3,
            budget: const Duration(seconds: 12),
          );
      if (!mounted) return;
      _dismissLoading();
      final free = res.any((e) => _sameRoom(e, r));
      _showFavUsageResult(r, free: free);
    } catch (e) {
      AppLog.e('空教室', '使用情况查询失败：$e');
      if (!mounted) return;
      _dismissLoading();
      showInkToast(context, '查询失败：$e', error: true);
    }
  }

  void _dismissLoading() {
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      // 对话框已被关闭时忽略
    }
  }

  void _showFavUsageResult(EmptyRoom r, {required bool free}) {
    final tone = free ? context.ink.success : context.ink.danger;
    showInkSheet(
      context,
      title: '「${r.cdmc}」使用情况',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: InkSpacing.m,
                vertical: InkSpacing.xl,
              ),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(InkRadius.control),
                border: Border.all(
                  color: tone.withValues(alpha: 0.22),
                  width: InkStroke.hairline,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    free ? AppIcons.examEvent : AppIcons.error,
                    size: 30,
                    color: tone,
                  ),
                  const SizedBox(height: InkSpacing.s),
                  Text(
                    free ? '该时段空闲' : '该时段已被占用',
                    style: context.tsBodyStrong.copyWith(color: tone),
                  ),
                  const SizedBox(height: InkSpacing.xs),
                  Text(
                    '查询时间：周${_weeks.join(',')}'
                    ' 星期${_weekdays.join(',')}'
                    ' 节次${_jcds.join(',')}',
                    textAlign: TextAlign.center,
                    style: context.tsSecondary,
                  ),
                ],
              ),
            ),
            const InkSectionHeader(
              title: '基本信息',
              padding: EdgeInsets.only(top: InkSpacing.l, bottom: InkSpacing.s),
            ),
            _infoRow('场地类别', r.cdlbmc),
            _infoRow('教学楼', r.jxlmc),
            _infoRow('座位数', r.zws),
            _infoRow('校区', r.xqmc),
            _infoRow('使用部门', r.sybm),
            _infoRow('备注', r.bz),
            const SizedBox(height: InkSpacing.s),
            Text('提示：以上空闲状态依据当前所选查询条件判定；不同时段结果不同。', style: context.tsSecondary),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: context.tsSecondary)),
          Expanded(
            child: Text(value.isEmpty ? '—' : value, style: context.tsBody),
          ),
        ],
      ),
    );
  }

  // ---------------- UI ----------------
  Widget _chips(
    String label,
    Set<int> set,
    List<String> names, {
    GlobalKey? focusKey,
    int? focusValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: InkSpacing.s),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < names.length; i++) ...[
                if (i > 0) const SizedBox(width: InkSpacing.s),
                KeyedSubtree(
                  key: focusKey != null && i + 1 == focusValue
                      ? focusKey
                      : null,
                  child: _FilterPill(
                    label: names[i],
                    selected: set.contains(i + 1),
                    onTap: () => _toggle(set, i + 1),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(text, style: context.tsLabel);

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRooms;
    final grouped = _groupedRooms;
    final filtering = _onlyFree || _resultCtrl.text.trim().isNotEmpty;
    return InkPageScaffold(
      showBack: true,
      title: '空教室',
      // 标题固定，仅内容滚动（与成绩/学业等页面一致）
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: inkPagePadding(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const InkSectionHeader(title: '查询条件'),
            InkCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _dropdown(
                    '校区',
                    _xqhOptions,
                    _xqhId,
                    (v) => setState(() => _xqhId = v),
                  ),
                  const SizedBox(height: InkSpacing.m),
                  _dropdown(
                    '场地类别',
                    _cdlbOptions,
                    _categoryId,
                    (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: InkSpacing.m),
                  _dropdown(
                    '楼号',
                    _lhOptions,
                    _lh,
                    (v) => setState(() => _lh = v),
                  ),
                  const SizedBox(height: InkSpacing.l),
                  _chips(
                    '周次（可多选）',
                    _weeks,
                    [for (var i = 1; i <= 20; i++) '第 $i 周'],
                    focusKey: _weekChipKey,
                    focusValue: _currentWeek,
                  ),
                  const SizedBox(height: InkSpacing.m),
                  _chips('星期（可多选）', _weekdays, _dayNames),
                  const SizedBox(height: InkSpacing.m),
                  _chips('节次（可多选）', _jcds, [
                    for (var i = 1; i <= 10; i++) '第 $i 节',
                  ]),
                  const SizedBox(height: InkSpacing.l),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '场地名/编号（可选）',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: InkSpacing.m),
                  FilledButton.icon(
                    onPressed: _loading ? null : _search,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(AppIcons.search, size: 18),
                    label: Text(_loading ? '查询中…' : '查询空闲教室'),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: InkSpacing.m),
              InkBanner(
                message: '查询失败：$_error',
                tone: InkTone.danger,
                icon: AppIcons.error,
              ),
            ],
            if (_rooms != null) ...[
              if (_rooms!.isEmpty) ...[
                const SizedBox(height: InkSpacing.l),
                InkCard(
                  child: Column(
                    children: [
                      Icon(
                        AppIcons.inbox,
                        size: 30,
                        color: context.ink.secondaryLabel,
                      ),
                      const SizedBox(height: InkSpacing.s),
                      Text('该时段暂无空闲教室', style: context.tsBodyStrong),
                      const SizedBox(height: InkSpacing.xs),
                      Text(
                        '请扩大周次/星期/节次的选择后重试'
                        '（多选会要求“同时空闲”，若仍无结果请尝试仅选单一周次/星期/节次）。',
                        textAlign: TextAlign.center,
                        style: context.tsCaption,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                InkSectionHeader(
                  title: '空闲教室',
                  subtitle:
                      '共 ${filtered.length} 间 · ${grouped.length} 栋'
                      '${_unionUsed ? " · 已按任一时段合并" : ""}',
                ),
                // 结果内快速筛选：本地过滤，不重新请求教务
                InkCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: InkSpacing.m,
                    vertical: InkSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _resultCtrl,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            hintText: '筛选教室名 / 楼栋',
                            prefixIcon: Icon(AppIcons.search, size: 18),
                            isDense: true,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      const SizedBox(width: InkSpacing.s),
                      FilterChip(
                        label: const Text('只看可借'),
                        selected: _onlyFree,
                        showCheckmark: false,
                        onSelected: (v) => setState(() => _onlyFree = v),
                        // 默认不填充颜色，仅留发丝描边；点击选中后再填充主色底，
                        // 避免未选中时看起来像已开启。
                        backgroundColor: Colors.transparent,
                        selectedColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.6),
                        side: BorderSide(
                          color: _onlyFree
                              ? Colors.transparent
                              : context.ink.hairline,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: InkSpacing.s),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: InkSpacing.l),
                    child: Center(
                      child: Text('没有符合筛选条件的教室', style: context.tsSecondary),
                    ),
                  )
                else
                  for (final e in grouped.entries)
                    _BuildingGroup(
                      // 筛选模式切换时重建，保证 initiallyExpanded 生效
                      key: ValueKey('${e.key}-${filtering ? 'f' : 'n'}'),
                      name: e.key,
                      rooms: e.value,
                      // 有筛选时全部展开，否则只展开第一栋
                      initiallyExpanded:
                          filtering || e.key == grouped.keys.first,
                      isFav: (r) => _favRooms.any((f) => _sameRoom(f, r)),
                      onFav: _toggleFav,
                    ),
                const SizedBox(height: InkSpacing.xs),
              ],
            ],
            InkSectionHeader(
              title: '我的收藏',
              trailing: InkTag(text: '${_favRooms.length} 间'),
            ),
            // 简洁搜索框：一个输入框 + 一个添加按钮，少装饰、突出功能
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _favCtrl,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addFavByInput(),
                    decoration: const InputDecoration(
                      hintText: '输入教室名',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: InkSpacing.s),
                FilledButton(
                  onPressed: _addFavByInput,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: InkSpacing.l,
                    ),
                  ),
                  child: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: InkSpacing.s),
            if (_favRooms.isEmpty)
              InkCard(
                child: Column(
                  children: [
                    Icon(
                      AppIcons.star,
                      size: 26,
                      color: context.ink.secondaryLabel,
                    ),
                    const SizedBox(height: InkSpacing.s),
                    Text('暂无收藏', style: context.tsBodyStrong),
                    const SizedBox(height: InkSpacing.xs),
                    Text('查询结果中点星标，或在上方手动添加', style: context.tsCaption),
                  ],
                ),
              )
            else
              for (final r in _favRooms)
                Dismissible(
                  key: ValueKey('fav_${r.cdbh.isNotEmpty ? r.cdbh : r.cdmc}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: InkSpacing.xl),
                    margin: const EdgeInsets.only(bottom: InkSpacing.s),
                    decoration: BoxDecoration(
                      color: context.ink.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(InkRadius.card),
                    ),
                    child: Icon(AppIcons.delete, color: context.ink.danger),
                  ),
                  onDismissed: (_) => _removeFav(r),
                  child: _FavCard(room: r, onTap: () => _showFavDetail(r)),
                ),
            const SizedBox(height: InkSpacing.l),
          ],
        ),
      ),
    );
  }

  /// 下拉：菜单高度限制约 5 项，超出部分上下滑动浏览
  Widget _dropdown(
    String label,
    List<(String, String)> options,
    String value,
    ValueChanged<String> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 76, child: Text(label, style: context.tsLabel)),
        Expanded(
          child: InkSelect<String>(
            value: value,
            options: [
              for (final (v, t) in options) InkSelectOption(value: v, label: t),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 按教学楼分组的结果卡：默认只展开第一栋，避免一次性渲染上百条
class _BuildingGroup extends StatelessWidget {
  const _BuildingGroup({
    super.key,
    required this.name,
    required this.rooms,
    required this.initiallyExpanded,
    required this.isFav,
    required this.onFav,
  });

  final String name;
  final List<EmptyRoom> rooms;
  final bool initiallyExpanded;
  final bool Function(EmptyRoom) isFav;
  final void Function(EmptyRoom) onFav;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    final free = rooms.where((r) => r.available).length;
    return InkCard(
      margin: const EdgeInsets.only(bottom: InkSpacing.s),
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: InkSpacing.l),
          childrenPadding: const EdgeInsets.fromLTRB(
            InkSpacing.l,
            0,
            InkSpacing.l,
            InkSpacing.s,
          ),
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: ink.secondaryLabel,
          collapsedIconColor: ink.secondaryLabel,
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.tsBodyStrong,
          ),
          subtitle: Text(
            '${rooms.length} 间 · 可借 $free',
            style: context.tsSecondary,
          ),
          children: [
            for (var i = 0; i < rooms.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: InkStroke.hairline,
                  color: ink.hairline,
                ),
              _RoomRow(
                room: rooms[i],
                isFav: isFav(rooms[i]),
                onFav: () => onFav(rooms[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 自然排序：逐段比较数字/文本，让 102 排在 99 之后
int _naturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final ta = re.allMatches(a).map((m) => m.group(0)!).toList();
  final tb = re.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < ta.length && i < tb.length; i++) {
    final na = int.tryParse(ta[i]);
    final nb = int.tryParse(tb[i]);
    final c = (na != null && nb != null)
        ? na.compareTo(nb)
        : ta[i].compareTo(tb[i]);
    if (c != 0) return c;
  }
  return ta.length.compareTo(tb.length);
}

/// 筛选胶囊：圆角 + 主色选中态
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    final ink = context.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: InkMotion.fast,
        curve: InkMotion.standard,
        padding: const EdgeInsets.symmetric(
          horizontal: InkSpacing.m,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: selected ? cs.primary : ink.groupedBackground,
          borderRadius: BorderRadius.circular(InkRadius.pill),
          border: Border.all(
            color: selected ? cs.primary : ink.hairline,
            width: InkStroke.hairline,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: InkTextStyles.label.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : ink.secondaryLabel,
          ),
        ),
      ),
    );
  }
}

/// 分组内的教室行（收藏按钮：再点取消）
class _RoomRow extends StatelessWidget {
  final EmptyRoom room;
  final bool isFav;
  final VoidCallback onFav;
  const _RoomRow({
    required this.room,
    required this.isFav,
    required this.onFav,
  });

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    // 列表本身来自「空闲教室」查询，能出现在结果里就说明所选时段空闲；
    // sfkjy=否 只代表教务标记为不可借用，并不等于被占用（此前误显示为“占用”）。
    final borrowable = room.sfkjy != '否';
    final meta = [
      if (room.cdlbmc.isNotEmpty) room.cdlbmc,
      if (room.zws.isNotEmpty) '${room.zws}座',
      if (room.xqmc.isNotEmpty) room.xqmc,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: InkSpacing.s + 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.cdmc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tsBodyStrong,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: InkSpacing.xs),
                  Text(meta, style: context.tsSecondary),
                ],
                if (room.bz.isNotEmpty || room.sybm.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (room.sybm.isNotEmpty) '${room.sybm}使用',
                      if (room.bz.isNotEmpty) room.bz,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tsSecondary,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: InkSpacing.s),
          Column(
            children: [
              InkTag(
                text: borrowable ? '空闲' : '不可借用',
                tone: borrowable ? InkTone.success : InkTone.warning,
              ),
              IconButton(
                tooltip: isFav ? '取消收藏' : '收藏',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isFav ? AppIcons.starFilled : AppIcons.star,
                  size: 19,
                  color: isFav ? context.scheme.primary : ink.secondaryLabel,
                ),
                onPressed: onFav,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 收藏卡片：点击查看使用情况，左滑删除
class _FavCard extends StatelessWidget {
  final EmptyRoom room;
  final VoidCallback onTap;
  const _FavCard({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (room.jxlmc.isNotEmpty) room.jxlmc,
      if (room.cdlbmc.isNotEmpty) room.cdlbmc,
      if (room.zws.isNotEmpty) '${room.zws}座',
      if (room.sybm.isNotEmpty) '${room.sybm}使用',
    ].join(' · ');
    return InkCard(
      margin: const EdgeInsets.only(bottom: InkSpacing.s),
      padding: const EdgeInsets.symmetric(
        horizontal: InkSpacing.l,
        vertical: InkSpacing.m,
      ),
      onTap: onTap,
      child: Row(
        children: [
          InkIconBadge(icon: AppIcons.room, tone: InkTone.info),
          const SizedBox(width: InkSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.cdmc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tsBodyStrong,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: InkSpacing.xs),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tsSecondary,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: InkSpacing.s),
          Icon(
            AppIcons.chevronRight,
            size: 18,
            color: context.ink.secondaryLabel,
          ),
        ],
      ),
    );
  }
}

/// 查询加载占位：转圈 + 提示文字
class _LoadingOverlay extends StatelessWidget {
  final String message;
  const _LoadingOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkCard(
        padding: const EdgeInsets.symmetric(
          horizontal: InkSpacing.xxl,
          vertical: InkSpacing.xl,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            const SizedBox(width: InkSpacing.m),
            Text(message, style: context.tsBodyStrong),
          ],
        ),
      ),
    );
  }
}
