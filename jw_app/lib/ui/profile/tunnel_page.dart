import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/usage_api.dart';
import '../../theme/ink_tokens.dart';
import '../../util/server_config.dart';
import '../widgets/app_icons.dart';
import '../widgets/ink_dialog.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

/// 公网通道入口管理：切换、测速、编辑，并可下发到云端供所有客户端同步。
class TunnelPage extends StatefulWidget {
  const TunnelPage({super.key});

  @override
  State<TunnelPage> createState() => _TunnelPageState();
}

class _TunnelPageState extends State<TunnelPage> {
  late List<TunnelEndpoint> _list;
  late String _active;
  late String _default;
  final Map<String, int?> _latency = {};
  final Set<String> _testing = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _list = List.of(ServerConfig.endpoints);
    _active = ServerConfig.activeBase;
    _default = _cloudDefaultOf(_list);
    WidgetsBinding.instance.addPostFrameCallback((_) => _testAll());
  }

  /// 云端默认入口：优先用同步下来的标记，未同步过则取列表第一条
  String _cloudDefaultOf(List<TunnelEndpoint> list) {
    for (final e in list) {
      if (e.isDefault) return e.base;
    }
    return list.isEmpty ? '' : list.first.base;
  }

  Future<void> _testAll() async {
    if (_testing.isNotEmpty) return;
    final bases = _list.map((e) => e.base).toList();
    setState(() {
      for (final b in bases) {
        _testing.add(b);
      }
    });
    await Future.wait(bases.map((b) async {
      final e = _list.firstWhere((x) => x.base == b);
      final ms = await ServerConfig.ping(e);
      if (!mounted) return;
      setState(() {
        _latency[b] = ms;
        _testing.remove(b);
      });
    }));
  }

  Future<void> _activate(TunnelEndpoint e) async {
    await ServerConfig.setActive(e.base, byUser: true);
    if (!mounted) return;
    setState(() => _active = e.base);
    showInkToast(context, '已切换到 ${e.name}');
  }

  /// 选择云端默认入口：新装/清数据的客户端首次同步后自动使用该入口，
  /// 后续更换线路只需在这里改，不必重新发版。
  void _setDefault(TunnelEndpoint e) {
    setState(() => _default = e.base);
    showInkToast(context, '已设为云端默认：${e.name}，记得「保存到云端」');
  }

  Future<void> _edit([TunnelEndpoint? initial]) async {
    final result = await _editDialog(initial);
    if (result == null) return;
    final next = List.of(_list);
    if (initial == null) {
      next.add(result);
    } else {
      final i = next.indexWhere((e) => e.base == initial.base);
      if (i >= 0) next[i] = result;
      if (_default == initial.base) _default = result.base;
    }
    await ServerConfig.saveLocal(next);
    if (!mounted) return;
    setState(() {
      _list = List.of(ServerConfig.endpoints);
      _active = ServerConfig.activeBase;
      _latency.removeWhere((k, _) => !_list.any((e) => e.base == k));
    });
    await _testOne(result);
  }

  Future<void> _testOne(TunnelEndpoint e) async {
    setState(() => _testing.add(e.base));
    final ms = await ServerConfig.ping(e);
    if (!mounted) return;
    setState(() {
      _latency[e.base] = ms;
      _testing.remove(e.base);
    });
  }

  Future<void> _delete(TunnelEndpoint e) async {
    if (_list.length <= 1) {
      showInkToast(context, '至少保留一个入口', error: true);
      return;
    }
    final ok = await showInkDialog(
      context,
      title: '删除入口',
      message: '确定删除「${e.name}」？',
      confirmText: '删除',
      danger: true,
    );
    if (!ok) return;
    final next = _list.where((x) => x.base != e.base).toList();
    await ServerConfig.saveLocal(next);
    if (!mounted) return;
    setState(() {
      _list = List.of(ServerConfig.endpoints);
      _active = ServerConfig.activeBase;
      if (_default == e.base) _default = _cloudDefaultOf(_list);
    });
  }

  Future<void> _saveCloud() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await UsageTracker.saveTunnelEndpoints(
      [for (final e in _list) {'name': e.name, 'url': e.base}],
      defaultUrl: _default,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    showInkToast(
      context,
      r.ok ? '已下发到云端（含默认入口），新启动的客户端会自动同步' : '下发失败：${r.error}',
      error: !r.ok,
    );
  }

  Future<void> _syncCloud() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ServerConfig.refresh();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _list = List.of(ServerConfig.endpoints);
      _active = ServerConfig.activeBase;
      _default = _cloudDefaultOf(_list);
    });
    showInkToast(context, '已从云端同步：${_list.length} 个入口');
    await _testAll();
  }

  String _latencyLabel(String base) {
    final ms = _latency[base];
    if (ms == null) return '不可达';
    return '$ms ms';
  }

  InkTone _latencyTone(String base) {
    final ms = _latency[base];
    if (ms == null) return InkTone.danger;
    if (ms < 300) return InkTone.success;
    return InkTone.warning;
  }

  @override
  Widget build(BuildContext context) {
    return InkPageScaffold(
      showBack: true,
      title: '公网通道',
      children: [
        const InkBanner(
          message: '「云端默认」决定新装或清空数据后的首个入口，换线路在这里改即可，无需重新发版。'
              '切换入口立即生效；「保存到云端」后，其他客户端下次启动会自动同步。',
          icon: AppIcons.info,
        ),
        const SizedBox(height: InkSpacing.l),
        InkSectionHeader(
          title: '入口列表',
          subtitle: '点击条目切换当前入口',
          trailing: TextButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(AppIcons.add, size: 18),
            label: const Text('添加'),
          ),
        ),
        InkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < _list.length; i++)
                InkSettingTile(
                  title: _list[i].name,
                  subtitle: '${_list[i].base}'
                      '${_default == _list[i].base ? " · 云端默认" : ""}',
                  icon: AppIcons.bolt,
                  iconTone: _list[i].base == _active
                      ? InkTone.success
                      : InkTone.info,
                  onTap: () => _activate(_list[i]),
                  showDivider: i < _list.length - 1,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_testing.contains(_list[i].base))
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (_latency.containsKey(_list[i].base))
                        InkTag(
                          text: _latencyLabel(_list[i].base),
                          tone: _latencyTone(_list[i].base),
                        ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          AppIcons.more,
                          size: 20,
                          color: context.ink.secondaryLabel,
                        ),
                        onSelected: (v) {
                          if (v == 'default') _setDefault(_list[i]);
                          if (v == 'edit') _edit(_list[i]);
                          if (v == 'delete') _delete(_list[i]);
                        },
                        itemBuilder: (_) => [
                          if (_default != _list[i].base)
                            const PopupMenuItem(
                              value: 'default',
                              child: Text('设为云端默认'),
                            ),
                          const PopupMenuItem(value: 'edit', child: Text('编辑')),
                          const PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: InkSpacing.l),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testAll,
                icon: const Icon(AppIcons.refresh, size: 18),
                label: const Text('全部测速'),
              ),
            ),
            const SizedBox(width: InkSpacing.m),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _saveCloud,
                icon: const Icon(AppIcons.upload, size: 18),
                label: Text(_busy ? '处理中' : '保存到云端'),
              ),
            ),
          ],
        ),
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : _syncCloud,
            icon: const Icon(AppIcons.download, size: 18),
            label: const Text('从云端同步'),
          ),
        ),
      ],
    );
  }

  Future<TunnelEndpoint?> _editDialog(TunnelEndpoint? initial) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final urlCtrl = TextEditingController(text: initial?.base ?? 'https://');
    final result = await showDialog<TunnelEndpoint>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? '添加入口' : '编辑入口'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：备用通道',
              ),
            ),
            const SizedBox(height: InkSpacing.m),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '地址',
                hintText: 'https://api.example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final base = ServerConfig.parseBase(urlCtrl.text);
              if (base == null) {
                showInkToast(ctx, '地址需为 https:// 开头', error: true);
                return;
              }
              final name = nameCtrl.text.trim();
              Navigator.pop(
                ctx,
                TunnelEndpoint(
                  name: name.isEmpty ? Uri.parse(base).host : name,
                  base: base,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    urlCtrl.dispose();
    return result;
  }
}
