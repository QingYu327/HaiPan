import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ink_dialog.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

/// 解析出的单条日志
class _LogEntry {
  final DateTime time;
  final String level; // D / W / E
  final String tag;
  final String message;
  const _LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
  });
}

/// 日志级别 → 文案与语义色：错误 danger / 警告 warning / 调试 info
(String, InkTone) _levelMeta(String level) => switch (level) {
  'E' => ('错误', InkTone.danger),
  'W' => ('警告', InkTone.warning),
  _ => ('调试', InkTone.info),
};

/// 运行日志页：按级别分区展示逐条卡片，支持级别过滤、关键词搜索、
/// 详情报收、单条/全部复制与清空。
class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  static const _fileCh = MethodChannel('cn.gdou.xiuhong/file');
  final _filter = TextEditingController();
  String _level = 'ALL'; // ALL / E / W / D
  String _tag = 'ALL'; // ALL / 具体模块
  List<_LogEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _entries = _parseEntries());

  Future<void> _refresh() async => _reload();

  /// 把原始日志行解析为条目（含多行堆栈合并），最新在前
  List<_LogEntry> _parseEntries() {
    final headerRe = RegExp(r'^(\S+)\s+\[(D|W|E)\]\s+\[([^\]]*)\]\s?(.*)$');
    final out = <_LogEntry>[];
    _LogEntry? cur;
    for (final raw in AppLog.entries) {
      for (final line in raw.split('\n')) {
        final m = headerRe.firstMatch(line);
        if (m != null) {
          if (cur != null) out.add(cur);
          cur = _LogEntry(
            time: DateTime.tryParse(m.group(1)!) ?? DateTime(0),
            level: m.group(2)!,
            tag: m.group(3)!,
            message: m.group(4)?.trim() ?? '',
          );
        } else if (cur != null && line.trim().isNotEmpty) {
          // 堆栈等续行并入上一条消息，保留完整上下文
          cur = _LogEntry(
            time: cur.time,
            level: cur.level,
            tag: cur.tag,
            message: '${cur.message}\n${line.trim()}',
          );
        }
      }
    }
    if (cur != null) out.add(cur);
    return out;
  }

  /// 按出现次数排序的模块名（用于细分筛选）
  List<String> get _tags {
    final count = <String, int>{};
    for (final e in _entries) {
      if (e.tag.isEmpty) continue;
      count[e.tag] = (count[e.tag] ?? 0) + 1;
    }
    final tags = count.keys.toList()
      ..sort((a, b) => count[b]!.compareTo(count[a]!));
    return tags;
  }

  List<_LogEntry> get _visible {
    final q = _filter.text.trim().toLowerCase();
    return _entries.where((e) {
      if (_level != 'ALL' && e.level != _level) return false;
      if (_tag != 'ALL' && e.tag != _tag) return false;
      if (q.isNotEmpty &&
          !e.tag.toLowerCase().contains(q) &&
          !e.message.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  Widget _tagChip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: InkSpacing.s),
      child: ChoiceChip(
        label: Text(label),
        selected: _tag == value,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _tag = value),
      ),
    );
  }

  Future<void> _copyText(String text, {String hint = '已复制到剪贴板'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showInkToast(context, hint);
  }

  /// 导出当前筛选的日志为 .log 文件（用户自选保存路径）
  Future<void> _exportLog() async {
    final visible = _visible;
    final buf = StringBuffer('海畔运行日志 ${DateTime.now()}\n');
    buf.write('---\n');
    for (final e in visible) {
      buf.writeln('${_fmtTime(e.time)} [${e.level}] ${e.tag}: ${e.message}');
    }
    try {
      await _fileCh.invokeMethod('saveLog', {'text': buf.toString()});
    } catch (e) {
      if (mounted) {
        showInkToast(context, '导出失败：$e', error: true);
      }
    }
  }

  Future<void> _clear() async {
    final ok = await showInkDialog(
      context,
      title: '清空日志',
      message: '确定清空全部日志吗？',
      confirmText: '清空',
      danger: true,
    );
    if (ok) {
      await AppLog.clear();
      _filter.clear();
      _tag = 'ALL';
      _reload();
    }
  }

  /// 详情报收：完整消息 + 复制
  void _showDetail(_LogEntry e) {
    final (label, tone) = _levelMeta(e.level);
    showInkSheet(
      context,
      title: '日志详情',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkTag(text: label, tone: tone),
              const SizedBox(width: InkSpacing.s),
              Expanded(
                child: Text(
                  e.tag,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.tsBodyStrong,
                ),
              ),
              Text(_fmtTime(e.time), style: context.tsSecondary),
              const SizedBox(width: InkSpacing.xs),
              IconButton(
                tooltip: '复制',
                visualDensity: VisualDensity.compact,
                onPressed: () => _copyText(e.message, hint: '该条日志已复制'),
                icon: const Icon(AppIcons.copy, size: 20),
              ),
            ],
          ),
          const SizedBox(height: InkSpacing.xs),
          Divider(
            height: 1,
            thickness: InkStroke.hairline,
            color: context.ink.hairline,
          ),
          const SizedBox(height: InkSpacing.m),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                e.message.isEmpty ? '（无消息内容）' : e.message,
                style: context.tsCaption.copyWith(
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime t) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final tags = _tags;
    return InkPageScaffold(
      showBack: true,
      title: '运行日志',
      actions: [
        IconButton(
          tooltip: '清空日志',
          icon: const Icon(AppIcons.delete, size: 20),
          onPressed: _clear,
        ),
        IconButton(
          tooltip: '导出日志',
          icon: const Icon(AppIcons.upload, size: 20),
          onPressed: _exportLog,
        ),
        const SizedBox(width: InkSpacing.xs),
      ],
      body: Column(
        children: [
          const SizedBox(height: InkSpacing.xs),
          // 级别分区：全部 / 错误 / 警告 / 调试
          SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(value: 'ALL', label: Text('全部')),
                  ButtonSegment(
                    value: 'E',
                    label: Text('错误'),
                    icon: Icon(AppIcons.error, size: 14),
                  ),
                  ButtonSegment(
                    value: 'W',
                    label: Text('警告'),
                    icon: Icon(AppIcons.warning, size: 14),
                  ),
                  ButtonSegment(
                    value: 'D',
                    label: Text('调试'),
                    icon: Icon(AppIcons.info, size: 14),
                  ),
                ],
                selected: {_level},
                onSelectionChanged: (sel) => setState(() => _level = sel.first),
              ),
            ),
          ),
          // 模块细分：按日志 tag 快速切换
          if (tags.isNotEmpty) ...[
            const SizedBox(height: InkSpacing.s),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                children: [
                  _tagChip('ALL', '全部模块'),
                  for (final t in tags) _tagChip(t, t),
                ],
              ),
            ),
          ],
          const SizedBox(height: InkSpacing.s),
          TextField(
            controller: _filter,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '搜索模块或内容',
              prefixIcon: Icon(AppIcons.search),
            ),
          ),
          const SizedBox(height: InkSpacing.s),
          Expanded(
            child: visible.isEmpty
                ? InkRefresh(
                    fill: true,
                    onRefresh: _refresh,
                    child: Center(
                      child: Text('暂无日志', style: context.tsSecondary),
                    ),
                  )
                : InkRefresh(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                        bottom: inkPagePadding(context).bottom,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, i) => _LogCard(
                        entry: visible[i],
                        onTap: () => _showDetail(visible[i]),
                        onLongPress: () =>
                            _copyText(visible[i].message, hint: '该条日志已复制'),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 单条日志卡片：级别徽标 + 模块 + 关键消息 + 时间
class _LogCard extends StatelessWidget {
  final _LogEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _LogCard({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final (label, tone) = _levelMeta(entry.level);
    return GestureDetector(
      onLongPress: onLongPress,
      child: InkCard(
        margin: const EdgeInsets.only(bottom: InkSpacing.s),
        padding: const EdgeInsets.symmetric(
          horizontal: InkSpacing.m,
          vertical: InkSpacing.s + 2,
        ),
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkTag(text: label, tone: tone),
            const SizedBox(width: InkSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.tag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tsBodyStrong,
                        ),
                      ),
                      const SizedBox(width: InkSpacing.s),
                      Text(_time(entry.time), style: context.tsSecondary),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.message.isEmpty ? '（无消息内容）' : entry.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.tsCaption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime t) {
    String p(int v) => v.toString().padLeft(2, '0');
    return '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }
}
