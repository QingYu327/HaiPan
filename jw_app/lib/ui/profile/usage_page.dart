import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/usage_api.dart';
import '../../theme/ink_tokens.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ink_dialog.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

/// 使用人数统计页（仅开发者账号可见入口）：显示人数 + 用户学号列表
class UsagePage extends ConsumerStatefulWidget {
  const UsagePage({super.key});

  @override
  ConsumerState<UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends ConsumerState<UsagePage> {
  // 下拉刷新时同时重建名单区块，让它们重新拉取。
  int _refreshToken = 0;
  // 学号备注：管理员可见完整学号，备注用于区分同号段用户
  Map<String, String> _notes = const {};

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final r = await UsageTracker.fetchNotes();
    if (!mounted) return;
    setState(() => _notes = r.notes);
  }

  /// 编辑/清空某学号的备注；空内容表示删除备注。
  Future<void> _editNote(String xh) async {
    final text = await _promptNote(xh, _notes[xh] ?? '');
    if (text == null || !mounted) return;
    final ok = await UsageTracker.setNote(xh, text);
    if (!mounted) return;
    if (!ok) {
      showInkToast(context, '备注保存失败，请稍后重试', error: true);
      return;
    }
    setState(() {
      final next = Map<String, String>.from(_notes);
      if (text.isEmpty) {
        next.remove(xh);
      } else {
        next[xh] = text;
      }
      _notes = next;
    });
  }

  Future<String?> _promptNote(String xh, String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('备注 · $xh', style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: '例如：张三 计科2301',
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
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
    return result;
  }

  Future<void> _refresh() async {
    setState(() => _refreshToken++);
    ref.invalidate(usageCountProvider);
    await Future.wait([
      ref.read(usageCountProvider.future),
      _loadNotes(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(usageCountProvider);
    return InkPageScaffold(
      showBack: true,
      title: '用户统计',
      body: count.when(
        loading: () => loadingView,
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(InkSpacing.xxl),
            child: Text(
              '获取失败：$e',
              textAlign: TextAlign.center,
              style: context.tsSecondary,
            ),
          ),
        ),
        data: (d) => InkRefresh(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: InkSpacing.xs,
              bottom: inkPagePadding(context).bottom,
            ),
            children: [
              // 头部总览卡
              InkCard(
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('累计使用', style: context.tsBodyStrong),
                    ),
                    const SizedBox(height: InkSpacing.s),
                    InkStatsRow(
                      showDividers: false,
                      valueSize: 32,
                      stats: [
                        InkStat('${d.count}', '累计登录使用人数', tone: InkTone.info),
                      ],
                    ),
                    if (d.placeholder) ...[
                      const SizedBox(height: InkSpacing.m),
                      const InkTag(
                        text: '云端暂不可达 · 本地占位（0）',
                        tone: InkTone.warning,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: InkSpacing.m),
              const _RebindSwitch(),
              // 云端名单管理（管理员专属，免发版）：
              // APP 准入（默认禁止） / 更新黑名单
              _PermListSection(
                key: ValueKey('perm-app-$_refreshToken'),
                title: 'APP 准入名单',
                hint: '仅名单内学号可使用 APP，新登录用户默认禁止',
                feature: UsageTracker.featureApp,
                block: false,
                notes: _notes,
                onEditNote: _editNote,
              ),
              const SizedBox(height: InkSpacing.m),
              _PermListSection(
                key: ValueKey('perm-update-$_refreshToken'),
                title: '更新黑名单',
                hint: '名单内学号屏蔽更新',
                feature: UsageTracker.featureUpdate,
                block: true,
                notes: _notes,
                onEditNote: _editNote,
              ),
              const SizedBox(height: InkSpacing.m),
              // 用户列表
              InkSectionHeader(
                title: '登录用户',
                trailing: Text(
                  '共 ${d.ids.length} 人',
                  style: context.tsSecondary,
                ),
              ),
              if (d.ids.isEmpty)
                InkCard(
                  child: Center(
                    child: Text('暂无登录用户', style: context.tsSecondary),
                  ),
                )
              else
                for (final e in d.ids.asMap().entries)
                  _UserTile(
                    index: e.key + 1,
                    xh: e.value,
                    isOwner: e.value == UsageTracker.ownerXh,
                    note: _notes[e.value] ?? '',
                    onEdit: () => _editNote(e.value),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 管理员运行开关：设备自动换绑（默认开启，改完立即下发到云端）。
class _RebindSwitch extends StatefulWidget {
  const _RebindSwitch();

  @override
  State<_RebindSwitch> createState() => _RebindSwitchState();
}

class _RebindSwitchState extends State<_RebindSwitch> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await UsageTracker.fetchSettings();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _enabled = r.allowRebind;
    });
  }

  Future<void> _toggle(bool value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _enabled = value; // 先跟手，失败再回滚
    });
    final r = await UsageTracker.setAllowRebind(value);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _enabled = r.ok ? r.allowRebind : !value;
    });
    showInkToast(
      context,
      r.ok
          ? (r.allowRebind ? '已开启设备自动换绑' : '已关闭设备自动换绑')
          : '保存失败：${r.error ?? '请联系管理员检查云端'}',
      error: !r.ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkCard(
      margin: const EdgeInsets.only(bottom: InkSpacing.m),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('设备自动换绑', style: context.tsBodyStrong),
                const SizedBox(height: 2),
                Text(
                  _enabled
                      ? '清数据或换机后自动重新绑定，旧会话立即失效'
                      : '已关闭：换绑需在下方重置该学号的设备',
                  style: context.tsCaption,
                ),
              ],
            ),
          ),
          const SizedBox(width: InkSpacing.s),
          if (_loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: _enabled,
              onChanged: _saving ? null : _toggle,
            ),
        ],
      ),
    );
  }
}

class _PermListSection extends ConsumerStatefulWidget {
  /// 名单区块：title 标题 / hint 说明 / feature 功能名 / block 是否黑名单
  final String title;
  final String hint;
  final String feature;
  final bool block;
  final Map<String, String> notes;
  final ValueChanged<String> onEditNote;
  const _PermListSection({
    super.key,
    required this.title,
    required this.hint,
    required this.feature,
    required this.block,
    required this.notes,
    required this.onEditNote,
  });

  @override
  ConsumerState<_PermListSection> createState() => _PermListSectionState();
}

class _PermListSectionState extends ConsumerState<_PermListSection> {
  final _xhCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<String> _list = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _xhCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await UsageTracker.fetchPermList(
      widget.feature,
      block: widget.block,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.error;
      _list = r.list;
    });
  }

  Future<void> _add() async {
    final xh = _xhCtrl.text.trim();
    if (xh.isEmpty) {
      showInkToast(context, '请输入学号');
      return;
    }
    final r = await UsageTracker.managePermList(
      feature: widget.feature,
      block: widget.block,
      action: 'add',
      xh: xh,
    );
    if (!mounted) return;
    setState(() {
      if (r.ok) _list = r.list;
      _error = r.error;
    });
    if (r.ok) _xhCtrl.clear();
    showInkToast(
      context,
      r.ok ? '已添加 $xh' : '添加失败：${r.error}',
      error: !r.ok,
    );
  }

  Future<void> _remove(String xh) async {
    final title = widget.block ? '移出黑名单' : '取消 APP 权限';
    final message = widget.block
        ? '确认将 $xh 移出黑名单？移出后该学号可正常检查更新。'
        : '确认取消 $xh 的 APP 使用权限？取消后该学号将无法进入 APP。';
    final ok = await showInkDialog(
      context,
      title: title,
      message: message,
      confirmText: '移出',
      danger: true,
    );
    if (!ok) return;
    final r = await UsageTracker.managePermList(
      feature: widget.feature,
      block: widget.block,
      action: 'remove',
      xh: xh,
    );
    if (!mounted) return;
    setState(() {
      if (r.ok) _list = r.list;
      _error = r.error;
    });
    showInkToast(
      context,
      r.ok ? '已移出 $xh' : '移出失败：${r.error}',
      error: !r.ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return InkCard(
      margin: const EdgeInsets.only(bottom: InkSpacing.m),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              InkSpacing.l,
              InkSpacing.s,
              InkSpacing.s,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: context.tsBodyStrong),
                      const SizedBox(height: 2),
                      Text(widget.hint, style: context.tsCaption),
                    ],
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(InkSpacing.m),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              InkSpacing.l,
              InkSpacing.s,
              InkSpacing.l,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  InkBanner(message: '云端不可达：$_error', tone: InkTone.danger),
                  const SizedBox(height: InkSpacing.s),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _xhCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 20,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '输入学号',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              InkRadius.control,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: InkSpacing.s),
                    FilledButton.icon(
                      onPressed: _add,
                      icon: const Icon(AppIcons.add, size: 18),
                      label: const Text('添加'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: InkSpacing.s),
          if (_list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: InkSpacing.m),
              child: Center(
                child: Text(
                  _loading ? '加载中…' : '暂无名单成员',
                  style: context.tsSecondary,
                ),
              ),
            )
          else
            for (var i = 0; i < _list.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: InkStroke.hairline,
                  indent: InkSpacing.l,
                  endIndent: InkSpacing.l,
                  color: ink.hairline,
                ),
              _PermTile(
                xh: _list[i],
                note: widget.notes[_list[i]] ?? '',
                onEdit: () => widget.onEditNote(_list[i]),
                badge: widget.block ? '已屏蔽' : '已开放',
                tone: widget.block ? InkTone.danger : InkTone.success,
                onRemove: () => _remove(_list[i]),
              ),
            ],
          if (_list.isNotEmpty) const SizedBox(height: InkSpacing.s),
        ],
      ),
    );
  }
}

class _PermTile extends StatelessWidget {
  final String xh;
  final String note;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final String badge;
  final InkTone tone;
  const _PermTile({
    required this.xh,
    required this.note,
    required this.onEdit,
    required this.onRemove,
    this.badge = '已开放',
    this.tone = InkTone.success,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        InkSpacing.l,
        InkSpacing.xs,
        InkSpacing.s,
        InkSpacing.xs,
      ),
      child: Row(
        children: [
          InkTag(text: badge, tone: tone),
          const SizedBox(width: InkSpacing.m),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(InkRadius.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(xh, style: context.tsBodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      note.isEmpty ? '点击添加备注' : '备注：$note',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tsCaption.copyWith(
                        color: note.isEmpty ? cs.primary : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '移出',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              AppIcons.close,
              size: 20,
              color: context.ink.secondaryLabel,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final int index;
  final String xh;
  final bool isOwner;
  final String note;
  final VoidCallback onEdit;
  const _UserTile({
    required this.index,
    required this.xh,
    required this.isOwner,
    required this.note,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    return InkCard(
      margin: const EdgeInsets.only(bottom: InkSpacing.s),
      padding: const EdgeInsets.symmetric(
        horizontal: InkSpacing.l,
        vertical: InkSpacing.s + 2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$index', style: context.tsSecondary),
          ),
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isOwner ? cs.primaryContainer : cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Text(
              xh.isEmpty ? '?' : xh.characters.first,
              style: context.tsBodyStrong.copyWith(
                fontWeight: FontWeight.w700,
                color: isOwner ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: InkSpacing.m),
          Expanded(
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(InkRadius.control),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(xh, style: context.tsBodyStrong),
                  const SizedBox(height: 2),
                  Text(
                    note.isEmpty ? '点击添加备注' : '备注：$note',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tsCaption.copyWith(
                      color: note.isEmpty ? cs.primary : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const InkTag(text: '学号'),
        ],
      ),
    );
  }
}
