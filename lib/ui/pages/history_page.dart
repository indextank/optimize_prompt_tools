/// 历史记录页：搜索 / 筛选 / 打开复查 / 删除。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../services/history_query.dart';
import '../../state/app_state.dart';
import '../../app.dart';
import '../theme.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _searchCtrl = TextEditingController();
  String _sceneFilter = '';
  String _providerFilter = '';
  String _presetFilter = '';
  bool _onlyFavorites = false;
  List<OptimizeRecord> _records = [];
  bool _loading = true;
  String? _error;
  Set<String> _usedProviders = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 「清空所有」按钮：一次性清空全部历史（二次弹框确认）
  Widget _clearAllButton() => Button(
        onPressed: _clearAll,
        child: const Text('🗑 清空所有'),
      );

  Future<void> _clearAll() async {
    final count = await appState.storage.recordCount();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      barrierColor: context.colors.overlay,
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('清空历史记录'),
        content: Text('将删除全部 $count 条历史记录，该操作不可恢复。确定继续吗？'),
        actions: [
          Button(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) {
      await appState.clearHistory();
      await _reload();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 模型选项按全量历史计算（不受当前筛选影响）；若当前选中的模型
      // 已无使用记录，立即清空选择，避免幽灵筛选条件。
      final allRecords = await appState.loadHistory();
      if (!mounted) return;
      final used = usedProviderTypes(allRecords, appState.services);
      if (_providerFilter.isNotEmpty && !used.contains(_providerFilter)) {
        _providerFilter = '';
      }
      final list = await appState.loadHistory(
        keyword: _searchCtrl.text.trim(),
        scene: _sceneFilter,
        provider: _providerFilter,
        presetId: _presetFilter,
        onlyFavorites: _onlyFavorites,
      );
      if (!mounted) return;
      setState(() {
        _records = list;
        _usedProviders = used;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.withPadding(
      padding: const EdgeInsets.fromLTRB(26, 18, 26, 14),
      // crossAxisAlignment.start：Column 默认居中会把自然宽子级（筛选行）整体居中，
      // 导致无法左对齐
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 搜索筛选区：左对齐；最右侧「清空所有」（紧凑态随流换行）
        Builder(builder: (context) {
          final compact = MediaQuery.of(context).size.width < AppTokens.compactBreakpoint;
          final filters = Wrap(
            spacing: AppTokens.gapS,
            runSpacing: AppTokens.gapS,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextBox(
                  controller: _searchCtrl,
                  placeholder: '搜索原文或结果…',
                  prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(FluentIcons.search, size: 14)),
                  onChanged: (_) => _reload(),
                ),
              ),
              ComboBox<String>(
                value: _sceneFilter,
                items: [
                  const ComboBoxItem(value: '', child: Text('全部场景')),
                  for (final s in appState.scenes)
                    ComboBoxItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) {
                  setState(() {
                    _sceneFilter = v ?? '';
                    // 隐藏预置词下拉时必须同时清空选中值，避免幽灵筛选条件。
                    if (!presetFilterVisible(_sceneFilter)) {
                      _presetFilter = '';
                    }
                  });
                  _reload();
                },
              ),
              if (presetFilterVisible(_sceneFilter))
                ComboBox<String>(
                  key: const Key('history-preset-filter'),
                  value: _presetFilter,
                  items: [
                    const ComboBoxItem(value: '', child: Text('全部预置词')),
                    for (final p in appState.presets)
                      ComboBoxItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) {
                    setState(() => _presetFilter = v ?? '');
                    _reload();
                  },
                ),
              ComboBox<String>(
                value: _providerFilter,
                items: [
                  const ComboBoxItem(value: '', child: Text('全部模型')),
                  // 只展示当前历史中实际使用过的模型，而不是全部九家服务商。
                  for (final p in kProviderList
                      .where((p) => _usedProviders.contains(p)))
                    ComboBoxItem(
                        value: p, child: Text(getProviderConfig(p)?.name ?? p)),
                ],
                onChanged: (v) {
                  _providerFilter = v ?? '';
                  _reload();
                },
              ),
              Checkbox(
                checked: _onlyFavorites,
                content: const Text('只看收藏'),
                onChanged: (v) {
                  setState(() => _onlyFavorites = v ?? false);
                  _reload();
                },
              ),
              if (compact) _clearAllButton(),
            ],
          );
          if (compact) return filters;
          return Row(children: [
            Expanded(child: filters),
            const SizedBox(width: AppTokens.gapM),
            _clearAllButton(), // 筛选区域最右侧
          ]);
        }),
        const SizedBox(height: 14),
        Expanded(
          child: _loading
              ? const Center(child: ProgressRing())
              : _error != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!,
                            style: TextStyle(color: context.colors.danger)),
                        const SizedBox(height: 12),
                        Button(onPressed: _reload, child: const Text('重试')),
                      ]),
                    )
                  : _records.isEmpty
                      ? Center(
                          child: Text('暂无历史记录',
                              style:
                                  TextStyle(color: context.colors.textTertiary)))
                      : ListView.builder(
                      itemCount: _records.length,
                      itemBuilder: (context, i) => _RecordTile(
                        record: _records[i],
                        onOpen: () async {
                          await appState.openRecord(_records[i]);
                          if (context.mounted) {
                            navigateTo(context, AppShellState.reviewEdit);
                          }
                        },
                        onFavorite: () async {
                          await appState.toggleFavorite(_records[i]);
                          await _reload();
                        },
                        onDelete: () async {
                          await appState.deleteRecord(_records[i].id);
                          _reload();
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.record,
    required this.onOpen,
    required this.onDelete,
    required this.onFavorite,
  });

  final OptimizeRecord record;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final sceneName = appState.sceneById(record.scene).name;
    final time = DateFormat('MM-dd HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(record.createdAt * 1000));
    final presetName = record.presetId == null
        ? null
        : (appState.presets
                .where((p) => p.id == record.presetId)
                .firstOrNull
                ?.name ??
            '已删除预置词');
    final providerNames = record.providers
        .map((id) {
          final svc = appState.services.where((s) => s.id == id).firstOrNull;
          return svc == null ? id : (getProviderConfig(svc.provider)?.name ?? svc.provider);
        })
        .join('、');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Tooltip(
                message: record.favorite ? '取消收藏' : '收藏',
                child: IconButton(
                  icon: Icon(
                    record.favorite ? FluentIcons.heart_fill : FluentIcons.heart,
                    size: 15,
                    color: record.favorite
                        ? context.colors.danger
                        : context.colors.textSecondary,
                  ),
                  onPressed: onFavorite,
                ),
              ),
              Expanded(
                // Expanded 提供有界宽度，长原文单行省略（修复旧 Row 无界溢出问题）。
                child: Text(record.rawText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 3),
            Text(
                '$time${presetName != null ? ' · 预置词：$presetName' : ''} · $sceneName · ${record.mode.label} · $providerNames · 评分 ${record.scoreBefore ?? "-"}→${record.scoreAfter ?? "-"} · v${record.latest.v}',
                style:  TextStyle(fontSize: 11.5, color: context.colors.textTertiary),
                overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (record.scoreAfter != null)
          Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: context.colors.successSubtle,
                borderRadius: BorderRadius.circular(12)),
            child: Text('${record.scoreAfter}',
                style:  TextStyle(
                    fontSize: 12,
                    color: context.colors.success,
                    fontWeight: FontWeight.w600)),
          ),
        Button(onPressed: onOpen, child: const Text('打开')),
        const SizedBox(width: 8),
        IconButton(
            icon: const Icon(FluentIcons.delete, size: 14), onPressed: onDelete),
      ]),
    );
  }
}
