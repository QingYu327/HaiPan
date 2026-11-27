import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../providers/data_providers.dart';
import '../../providers/session_provider.dart';
import '../../theme/ink_tokens.dart';
import '../../util/app_log.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ink_notice.dart';
import '../widgets/ink_page.dart';

class RankPage extends ConsumerStatefulWidget {
  const RankPage({super.key});

  @override
  ConsumerState<RankPage> createState() => _RankPageState();
}

class _RankPageState extends ConsumerState<RankPage> {
  String? _qs; // 起始学期 value，如 202512
  String? _zz; // 终止学期 value
  String _cjxzm = 'zdz'; // 成绩性质
  String _tjfw = 'bj'; // 统计范围
  bool _queried = false; // 是否已点击过查询
  String? _notifiedKey; // 已提示过的查询条件，避免同一结果重复弹提示

  /// 学年学期 value(如 202512) → 可读标签（2025-2026-2）
  static String termDisplay(String v) {
    final m = RegExp(r'(\d{4})(\d{2})').firstMatch(v.trim());
    if (m != null) {
      final yy1 = m.group(1)!;
      final yy2 = (int.parse(yy1) + 1).toString();
      final sem = m.group(2) == '3' ? '1' : '2';
      return '$yy1-$yy2学年 · 第$sem学期';
    }
    return v.trim();
  }

  /// 只看晚于入学年的学期
  List<RankOption> _filterByEnrollment(List<RankOption> all) {
    final enrollmentYear = ref.watch(enrollmentYearProvider);
    return all
        .where(
          (o) => (int.tryParse(o.value.substring(0, 4)) ?? 0) >= enrollmentYear,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final meta = ref.watch(rankMetaProvider);
    // 查询结果回来后给一次灵动岛反馈（同一条件只提示一次）
    if (_queried && _qs != null && _zz != null) {
      final key = '$_qs|$_zz|$_cjxzm|$_tjfw';
      ref.listen(rankResultProvider((_qs!, _zz!, _cjxzm, _tjfw)), (prev, next) {
        next.whenData((r) {
          if (!context.mounted || _notifiedKey == key) return;
          _notifiedKey = key;
          showInkToast(
            context,
            r.items.isEmpty
                ? '查询完成：该范围暂无排名数据'
                : '排名查询完成，共 ${r.items.length} 条记录',
          );
        });
      });
    }
    return InkPageScaffold(
      showBack: true,
      title: '绩点排名',
      body: Column(
        children: [
          meta.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(InkSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.refresh(rankMetaProvider),
            ),
            data: (m) {
              final options = _filterByEnrollment(m.xnqOptions);
              if (_qs == null && options.isNotEmpty) {
                _qs = options.last.value; // 默认最新
                _zz = options.last.value;
                _cjxzm = m.defCjxzm;
                _tjfw = m.defTjfw;
              }
              return _buildQueryBar(m, options);
            },
          ),
          Expanded(
            child: (_qs == null || _zz == null)
                ? const EmptyView('暂无可选学年学期')
                : _queried
                ? _buildResult()
                : const EmptyView('选择条件后点击查询'),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryBar(RankPageMeta meta, List<RankOption> options) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: InkSpacing.s),
      child: InkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 组1：统计范围（年级专业 / 班级）
            _label(context, '统计范围'),
            InkSelect<String>(
              value: _tjfw,
              options: [
                for (final o in meta.tjfwOptions)
                  InkSelectOption(value: o.value, label: o.label),
              ],
              onChanged: (v) => setState(() => _tjfw = v),
            ),
            const SizedBox(height: InkSpacing.m),
            // 组2：起始 / 终止学年学期
            _label(context, '起始学年学期'),
            InkSelect<String>(
              value: _qs,
              options: [
                for (final o in options)
                  InkSelectOption(
                    value: o.value,
                    label: o.label.isNotEmpty ? o.label : termDisplay(o.value),
                  ),
              ],
              onChanged: (v) => setState(() => _qs = v),
            ),
            const SizedBox(height: InkSpacing.s + 2),
            _label(context, '终止学年学期'),
            InkSelect<String>(
              value: _zz,
              options: [
                for (final o in options)
                  InkSelectOption(
                    value: o.value,
                    label: o.label.isNotEmpty ? o.label : termDisplay(o.value),
                  ),
              ],
              onChanged: (v) => setState(() => _zz = v),
            ),
            const SizedBox(height: InkSpacing.m),
            // 组3：成绩性质（正考 / 最大值 / 首次通过）
            _label(context, '成绩性质'),
            InkSelect<String>(
              value: _cjxzm,
              options: [
                for (final o in meta.cjxzmOptions)
                  InkSelectOption(value: o.value, label: o.label),
              ],
              onChanged: (v) => setState(() => _cjxzm = v),
            ),
            const SizedBox(height: InkSpacing.m),
            FilledButton.icon(
              onPressed: (_qs == null || _zz == null)
                  ? null
                  : () {
                      AppLog.d(
                        '排名',
                        '查询 $_qs ~ $_zz 性质=$_cjxzm 范围=$_tjfw',
                      );
                      setState(() => _queried = true);
                      showInkToast(context, '正在查询排名…');
                    },
              icon: const Icon(AppIcons.search, size: 18),
              label: const Text('查询'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: InkSpacing.xs + 1),
      child: Text(text, style: context.tsLabel),
    );
  }

  Widget _buildResult() {
    final provider = rankResultProvider((_qs!, _zz!, _cjxzm, _tjfw));
    final result = ref.watch(provider);
    final myXh = ref.watch(sessionProvider).student.xh;
    return result.when(
      loading: () => loadingView,
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.refresh(provider)),
      data: (r) {
        if (r.items.isEmpty) return const EmptyView('该范围暂无排名数据');
        return ListView.builder(
          padding: EdgeInsets.only(bottom: inkPagePadding(context).bottom),
          itemCount: r.items.length,
          itemBuilder: (context, i) {
            final item = r.items[i];
            final isMe = item.xh == myXh;
            return _RankTile(rank: i + 1, item: item, highlight: isMe);
          },
        );
      },
    );
  }
}

class _RankTile extends StatelessWidget {
  final int rank;
  final RankItem item;
  final bool highlight;

  const _RankTile({
    required this.rank,
    required this.item,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.scheme;
    return InkCard(
      margin: const EdgeInsets.only(bottom: InkSpacing.s + 2),
      padding: EdgeInsets.zero,
      tone: highlight ? InkTone.info : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: InkSpacing.l,
          vertical: InkSpacing.m + 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.xm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: highlight ? context.tsBodyStrong : context.tsBody,
                  ),
                  if (item.bj.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: InkSpacing.xs - 1),
                      child: Text(
                        '${item.zymc} · ${item.bj}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.tsSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: InkSpacing.m),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.pjxfjd,
                  style: context.tsSection.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: InkSpacing.xs - 1),
                  child: Text('名次 ${item.pm}', style: context.tsSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
