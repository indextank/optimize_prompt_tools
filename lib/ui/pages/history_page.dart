/// 历史记录页：搜索 / 筛选 / 打开复查 / 删除。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
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
  List<OptimizeRecord> _records = [];
  bool _loading = true;

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
    setState(() => _loading = true);
    final list = await appState.loadHistory(
      keyword: _searchCtrl.text.trim(),
      scene: _sceneFilter,
      provider: _providerFilter,
    );
    if (!mounted) return;
    setState(() {
      _records = list;
      _loading = false;
    });
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
                  _sceneFilter = v ?? '';
                  _reload();
                },
              ),
              ComboBox<String>(
                value: _providerFilter,
                items: [
                  const ComboBoxItem(value: '', child: Text('全部模型')),
                  for (final p in kProviderList)
                    ComboBoxItem(
                        value: p, child: Text(getProviderConfig(p)?.name ?? p)),
                ],
                onChanged: (v) {
                  _providerFilter = v ?? '';
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
              : _records.isEmpty
                  ? const Center(
                      child: Text('暂无历史记录',
                          style: TextStyle(color: AppTokens.text3)))
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
  const _RecordTile(
      {required this.record, required this.onOpen, required this.onDelete});

  final OptimizeRecord record;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final sceneName = appState.sceneById(record.scene).name;
    final time = DateFormat('MM-dd HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(record.createdAt * 1000));
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
            // 直接作为 Column 子级获得有界宽度约束，省略号方可生效；
            // 曾包在 Row 中导致无界约束、文本按自然宽渲染溢出 4000+px（历史页红圈问题）
            Text(record.rawText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(
                '$time · $sceneName · ${record.mode.label} · $providerNames · 评分 ${record.scoreBefore ?? "-"}→${record.scoreAfter ?? "-"} · v${record.latest.v}',
                style: const TextStyle(fontSize: 11.5, color: AppTokens.text3),
                overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (record.scoreAfter != null)
          Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFFEAF6EC),
                borderRadius: BorderRadius.circular(12)),
            child: Text('${record.scoreAfter}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTokens.success,
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
