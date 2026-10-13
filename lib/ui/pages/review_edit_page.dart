/// 二次复查编辑页：原文对照 / 分段可编辑结果 / 复查清单，版本链与撤销重做。
library;

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import '../../services/export_service.dart';
import '../../state/app_state.dart';
import '../../app.dart';
import '../file_saver.dart';
import '../theme.dart';
import '../widgets/section_view.dart';

class ReviewEditPage extends StatefulWidget {
  const ReviewEditPage({super.key});

  /// 测试注入：替换导出器（避免触发原生保存对话框）
  @visibleForTesting
  static ExportService? debugExporter;

  @override
  State<ReviewEditPage> createState() => _ReviewEditPageState();
}

class _ReviewEditPageState extends State<ReviewEditPage> {
  /// 各段落编辑控制器
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, List<String>> _listItems = {
    SectionKeys.requirements: [],
    SectionKeys.constraints: [],
    SectionKeys.acceptance: [],
  };

  /// 列表条目控制器缓存（键：`$section#$index`）
  final Map<String, TextEditingController> _itemCtrls = {};

  /// 撤销/重做栈（快照为六段内容）
  final List<OptimizeResult> _undoStack = [];
  final List<OptimizeResult> _redoStack = [];

  bool _showOriginal = true;
  String? _editingSection;
  bool _rewriting = false;
  bool _syncing = false; // 程序化同步期间忽略编辑监听
  Timer? _autosave;
  int _loadedVersion = -1;

  ExportService? _exporter;
  ExportService get exporter =>
      _exporter ??= ReviewEditPage.debugExporter ??
          ExportService(fileSaver: createFileSaver());

  @override
  void dispose() {
    _rawResultCtrl.dispose();
    _autosave?.cancel();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final c in _itemCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncFromResult(OptimizeResult r) {
    _syncing = true;
    try {
      _syncFromResultInner(r);
    } finally {
      _syncing = false;
    }
  }

  /// 非结构化（简单模式）结果的整体文本控制器
  final TextEditingController _rawResultCtrl = TextEditingController();

  /// 并行对比模式：当前查看的结果来源服务 id（null=当前记录主结果）
  String? _srcServiceId;
  String? _loadedRecordId;

  /// 主结果来源（并行状态中首个成功方，与落库选择一致）
  String? get _primarySourceId {
    for (final st in appState.session.parallelStates.values) {
      if (st.success) return st.service.id;
    }
    return null;
  }

  /// 当前应展示/编辑的结果（记录主结果或选中的并行模型结果）
  OptimizeResult _displayResult(OptimizeRecord record) {
    final id = _srcServiceId;
    if (id != null) {
      final st = appState.session.parallelStates[id];
      if (st != null && st.success) return st.runResult!.result;
    }
    return record.latest.result;
  }

  void _switchSource(String? id) {
    if (id == null) return;
    final effective = _srcServiceId ?? _primarySourceId;
    if (id == effective) return;
    _autosave?.cancel();
    setState(() {
      _srcServiceId = id == _primarySourceId ? null : id;
      _undoStack.clear(); // 来源切换后撤销链不再跨模型混用
      _redoStack.clear();
      _syncFromResult(
          _displayResult(appState.session.currentRecord!));
    });
  }

  void _syncFromResultInner(OptimizeResult r) {
    _rawResultCtrl.text = r.rawText;
    _ctrls[SectionKeys.role]?.text = r.role;
    _ctrls[SectionKeys.goal]?.text = r.goal;
    _ctrls[SectionKeys.outputFormat]?.text = r.outputFormat;
    _listItems[SectionKeys.requirements] = [...r.requirements];
    _listItems[SectionKeys.constraints] = [...r.constraints];
    _listItems[SectionKeys.acceptance] = [...r.acceptance];
    _rebuildItemCtrls();
    _loadedVersion = appState.session.currentRecord?.latest.v ?? -1;
  }

  /// 版本切换/结构变更后重建条目控制器
  void _rebuildItemCtrls() {
    for (final c in _itemCtrls.values) {
      c.dispose();
    }
    _itemCtrls.clear();
  }

  TextEditingController _itemCtrl(String section, int index, String initial) {
    return _itemCtrls.putIfAbsent('$section#$index', () {
      final c = TextEditingController(text: initial);
      c.addListener(() {
        final items = _listItems[section]!;
        if (index < items.length) {
          items[index] = c.text;
          _onAnyEdit();
        }
      });
      return c;
    });
  }

  TextEditingController _ctrl(String key) => _ctrls.putIfAbsent(key, () {
        final c = TextEditingController();
        c.addListener(_onAnyEdit);
        return c;
      });

  @override
  void initState() {
    super.initState();
    _rawResultCtrl.addListener(_onAnyEdit);
  }

  void _onAnyEdit() {
    if (_syncing) return;
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 800), _saveDraft);
  }

  OptimizeResult _collectResult() {
    final base = appState.session.currentRecord?.latest.result ?? const OptimizeResult();
    if (!base.isStructured) {
      // 简单模式结果：整体一段文本
      return OptimizeResult.unstructured(_rawResultCtrl.text,
          scoreBefore: base.scoreBefore);
    }
    return base.copyWithSections(
      role: _ctrls[SectionKeys.role]?.text ?? base.role,
      goal: _ctrls[SectionKeys.goal]?.text ?? base.goal,
      requirements: _cleanList(_listItems[SectionKeys.requirements]!),
      constraints: _cleanList(_listItems[SectionKeys.constraints]!),
      outputFormat: _ctrls[SectionKeys.outputFormat]?.text ?? base.outputFormat,
      acceptance: _cleanList(_listItems[SectionKeys.acceptance]!),
    );
  }

  List<String> _cleanList(List<String> items) =>
      [for (final e in items) e.trim()]..removeWhere((e) => e.isEmpty);

  /// 自动保存草稿：生成新版本（编辑类）
  Future<void> _saveDraft() async {
    final record = appState.session.currentRecord;
    if (record == null) return;
    final next = _collectResult();
    // 内容无变化时不生成新版本（防止程序化同步误触发）
    if (next.toPlainText() == record.latest.result.toPlainText()) return;
    _undoStack.add(record.latest.result);
    _redoStack.clear();
    await appState.saveEditedResult(next);
    _srcServiceId = null; // 编辑落库后该内容即记录主结果
    if (mounted) setState(() {});
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final cur = appState.session.currentRecord?.latest.result;
    if (cur != null) _redoStack.add(cur);
    final prev = _undoStack.removeLast();
    _autosave?.cancel();
    _syncFromResult(prev);
    appState.saveEditedResult(prev);
    setState(() {});
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final cur = appState.session.currentRecord?.latest.result;
    if (cur != null) _undoStack.add(cur);
    final next = _redoStack.removeLast();
    _autosave?.cancel();
    _syncFromResult(next);
    appState.saveEditedResult(next);
    setState(() {});
  }

  Future<void> _rewrite(String key) async {
    final title = SectionKeys.titles[key]!;
    final current = _isListSection(key)
        ? _cleanList(_listItems[key]!).join('\n')
        : (_ctrls[key]?.text ?? '');
    setState(() => _rewriting = true);
    try {
      final text = await appState.rewriteSection(key, title, current);
      if (!mounted) return;
      setState(() {
        if (_isListSection(key)) {
          _listItems[key] = [
            for (final line in text.split('\n'))
              line.trim().replaceFirst(RegExp(r'^[\d\.\-、\s]+'), '')
          ]..removeWhere((e) => e.isEmpty);
          _rebuildItemCtrls();
        } else {
          _ctrls[key]?.text = text;
        }
      });
      await _saveDraft();
    } on LlmException catch (e) {
      if (mounted) _toast(e.userMessage, InfoBarSeverity.error);
    } finally {
      if (mounted) setState(() => _rewriting = false);
    }
  }

  bool _isListSection(String key) => _listItems.containsKey(key);

  /// 返回工作台：若结果发生过变更（含未触达防抖的待存草稿），先自动保存再离开
  Future<void> _backToWorkbench() async {
    _autosave?.cancel();
    await _saveDraft(); // 内部已实现「无变化不生成新版本」
    if (mounted) navigateTo(context, AppShellState.workbench);
  }

  Future<void> _exportMd() async {
    final record = appState.session.currentRecord;
    if (record == null) return;
    // 仅导出优化结果正文：不含标题、描述（场景/评分等元信息）与原始输入
    final path = await exporter.exportResultOnly(_collectResult(), record);
    if (!mounted) return;
    _toast(path == null ? '已取消导出' : '已导出：$path',
        path == null ? InfoBarSeverity.info : InfoBarSeverity.success);
  }

  void _toast(String msg, InfoBarSeverity sev) {
    displayInfoBar(context,
        builder: (context, close) =>
            InfoBar(title: Text(msg), severity: sev, onClose: close));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final record = appState.session.currentRecord;
        if (record == null) {
          return ScaffoldPage.withPadding(
            content: const Center(
                child: Text('暂无待复查的优化结果\n请先在优化工作台执行优化',
                    textAlign: TextAlign.center)),
          );
        }
        // 记录切换或并行状态失效时重置来源选择
        if (_loadedRecordId != record.id) {
          _loadedRecordId = record.id;
          _srcServiceId = null;
        }
        if (_srcServiceId != null &&
            !appState.session.parallelStates.containsKey(_srcServiceId)) {
          _srcServiceId = null;
        }
        final result = _displayResult(record);
        if (_loadedVersion != record.latest.v) {
          // 首次加载或版本切换后同步控制器
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _syncFromResult(result));
          });
        }
        final width = MediaQuery.of(context).size.width;
        final showOriginal = _showOriginal && width >= 1180; // 窄屏自动折叠原文栏
        final showChecklist = width >= 900; // 更窄仅保留编辑器，杜绝挤压
        return ScaffoldPage.withPadding(
          padding: EdgeInsets.fromLTRB(width < 900 ? 12 : 22, 12, width < 900 ? 12 : 22, 12),
          content: Column(children: [
            _buildTopBar(record),
            const SizedBox(height: AppTokens.gapM),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (showOriginal) ...[
                  SizedBox(width: 260, child: _buildOriginal(record)),
                  const SizedBox(width: AppTokens.gapM),
                ],
                Expanded(child: _buildEditor(result)),
                if (showChecklist) ...[
                  const SizedBox(width: AppTokens.gapM),
                  SizedBox(width: 260, child: _buildChecklist(result)),
                ],
              ]),
            ),
            const SizedBox(height: 10),
            _buildBottomBar(record),
          ]),
        );
      },
    );
  }

  // ------------------------------------------------------------------ 顶栏
  Widget _buildTopBar(OptimizeRecord record) {
    return Row(children: [
      Button(
        onPressed: _backToWorkbench,
        child: const Text('‹ 返回工作台'),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('复查与编辑', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          Text('对照复查清单逐项核对，点击任意段落可直接编辑',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: AppTokens.text3)),
        ]),
      ),
      const SizedBox(width: 10),
      ComboBox<int>(
        value: record.latest.v,
        items: [
          for (final v in record.versions.reversed)
            ComboBoxItem(
                value: v.v,
                child: Text('版本 v${v.v}${v.v == record.latest.v ? '（当前）' : ''}${v.edited ? ' · 已编辑' : ''}')),
        ],
        onChanged: (v) async {
          if (v == null || v == record.latest.v) return;
          _srcServiceId = null; // 回滚版本后回到记录内容
          await appState.rollbackToVersion(v);
          if (mounted) {
            setState(() => _syncFromResult(appState.session.currentRecord!.latest.result));
          }
        },
      ),
      const SizedBox(width: 10),
      // 窄屏下原文栏本就被折叠，「对照原文」开关无意义且会挤顶栏——隐藏
      if (MediaQuery.of(context).size.width >= 1180)
        ToggleSwitch(
          checked: _showOriginal,
          onChanged: (v) => setState(() => _showOriginal = v),
          content: const Text('对照原文', style: TextStyle(fontSize: 12.5)),
        ),
    ]);
  }

  // ------------------------------------------------------------------ 原文
  Widget _buildOriginal(OptimizeRecord record) {
    return Card(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _head('原始提示词', trailing: const Text('只读',
            style: TextStyle(fontSize: 11.5, color: AppTokens.text3))),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7F8),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTokens.border),
              ),
              child: SelectableText(record.rawText,
                  style: const TextStyle(fontSize: 13, height: 1.8, color: AppTokens.text2)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
              '${record.rawText.length} 字 · 优化前质量评分 ${record.scoreBefore ?? "-"} / 100',
              style: const TextStyle(fontSize: 11.5, color: AppTokens.text3)),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ 编辑区
  Widget _buildEditor(OptimizeResult result) {
    return Card(
      padding: EdgeInsets.zero,
      child: Column(children: [
        _head('优化结果（可编辑）', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          // 并行对比模式：支持切换查看/编辑各模型结果
          if (appState.session.parallelStates.values
                  .where((s) => s.success)
                  .length >=
              2) ...[
            ComboBox<String>(
              value: _srcServiceId ?? _primarySourceId ?? '',
              items: [
                for (final st in appState.session.parallelStates.values
                    .where((s) => s.success))
                  ComboBoxItem(
                      value: st.service.id,
                      child: Text(st.service.model,
                          style: const TextStyle(fontSize: 12))),
              ],
              onChanged: _switchSource,
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
              icon: const Icon(FluentIcons.undo, size: 14),
              onPressed: _undoStack.isEmpty ? null : _undo),
          IconButton(
              icon: const Icon(FluentIcons.redo, size: 14),
              onPressed: _redoStack.isEmpty ? null : _redo),
        ])),
        Expanded(
          child: result.isStructured
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    _textSection(SectionKeys.role),
                    _textSection(SectionKeys.goal),
                    _listSection(SectionKeys.requirements),
                    _listSection(SectionKeys.constraints),
                    _textSection(SectionKeys.outputFormat),
                    _listSection(SectionKeys.acceptance),
                  ],
                )
              // 简单模式结果：整体一段文本，单文本域编辑
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextBox(
                    controller: _rawResultCtrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 13, height: 1.7),
                  ),
                ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: Row(children: [
            Flexible(
                child: Text('修改将自动保存为当前版本草稿',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppTokens.text3))),
            Spacer(),
            Flexible(
                child: Text('支持 Markdown 语法',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: AppTokens.text3))),
          ]),
        ),
      ]),
    );
  }

  Widget _sectionShell(String key, Widget child) {
    final editing = _editingSection == key;
    return GestureDetector(
      onTap: () => setState(() => _editingSection = key),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: editing ? AppTokens.accent : Colors.transparent, width: 1.5),
          color: editing ? Colors.white : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
                decoration: BoxDecoration(
                    color: AppTokens.accentLight, borderRadius: BorderRadius.circular(4)),
                child: Text(SectionKeys.titles[key]!,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: AppTokens.accentDark)),
              ),
              const Spacer(),
              if (editing)
                Button(
                  onPressed: _rewriting ? null : () => _rewrite(key),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_rewriting)
                      const SizedBox(
                          width: 11, height: 11, child: ProgressRing(strokeWidth: 2))
                    else
                      const Text('✨', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    const Text('让 AI 重写此段', style: TextStyle(fontSize: 11)),
                  ]),
                ),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: child),
        ]),
      ),
    );
  }

  Widget _textSection(String key) => _sectionShell(
        key,
        TextBox(
          controller: _ctrl(key),
          maxLines: null,
          style: const TextStyle(fontSize: 12.8, height: 1.65),
          decoration: WidgetStatePropertyAll(BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.transparent),
          )),
        ),
      );

  Widget _listSection(String key) {
    final items = _listItems[key]!;
    return _sectionShell(
      key,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text('${i + 1}.', style: const TextStyle(fontSize: 12.8))),
              const SizedBox(width: 6),
              Expanded(
                child: TextBox(
                  controller: _itemCtrl(key, i, items[i]),
                  maxLines: null,
                  style: const TextStyle(fontSize: 12.8, height: 1.6),
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.delete, size: 12),
                onPressed: () => setState(() {
                  items.removeAt(i);
                  _itemCtrls.remove('$key#$i')?.dispose();
                  // 索引前移：重建后续控制器
                  _rebuildItemCtrls();
                  _onAnyEdit();
                }),
              ),
            ]),
          ),
        Button(
          onPressed: () => setState(() {
            items.add('');
            _onAnyEdit();
          }),
          child: const Text('＋ 添加条目', style: TextStyle(fontSize: 11.5)),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ 复查清单
  Widget _buildChecklist(OptimizeResult result) {
    final fixed = result.diagnosis.where((d) => d.isFixed).length;
    final total = result.diagnosis.length;
    return Card(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _head('复查清单', trailing: const Text('AI 诊断',
            style: TextStyle(fontSize: 11.5, color: AppTokens.text3))),
        if (result.scoreBefore != null || result.scoreAfter != null)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF6FBF7),
              border: Border.all(color: const Color(0xFFD8ECDD)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Text('${result.scoreBefore ?? "-"}',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTokens.text3,
                      decoration: TextDecoration.lineThrough)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('→', style: TextStyle(color: AppTokens.success, fontSize: 14)),
              ),
              Text('${result.scoreAfter ?? "-"}',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w700, color: AppTokens.success)),
              const Spacer(),
              const Text('质量评分\n优化前 / 后',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 10.5, color: AppTokens.text3)),
            ]),
          ),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(horizontal: 14), children: [
            if (result.diagnosis.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('无诊断数据（快速模式或结果未结构化）',
                    style: TextStyle(fontSize: 12, color: AppTokens.text3)),
              ),
            for (final d in result.diagnosis)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: d.isFixed ? AppTokens.success : Colors.white,
                      border: d.isFixed
                          ? null
                          : Border.all(color: AppTokens.warning, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(d.isFixed ? '✓' : '!',
                        style: TextStyle(
                            fontSize: 11,
                            color: d.isFixed ? Colors.white : AppTokens.warning)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.item,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      if (d.before.isNotEmpty)
                        Text(d.before,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFB0B6BB),
                                decoration: TextDecoration.lineThrough)),
                      if (d.action.isNotEmpty)
                        Text(d.action,
                            style: const TextStyle(fontSize: 11, color: AppTokens.text3)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: ProgressBar(value: total == 0 ? 0 : fixed / total * 100),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('$total 项诊断 · $fixed 项已修复 · ${total - fixed} 项待确认',
                  style: const TextStyle(fontSize: 11, color: AppTokens.text3)),
            ),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ 底栏
  Widget _buildBottomBar(OptimizeRecord record) {
    return Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: AppTokens.gapS,
        runSpacing: AppTokens.gapS,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('✓ 自动保存已开启 · 历史版本可随时回滚',
              style: TextStyle(fontSize: 11.5, color: AppTokens.text3)),
          Wrap(spacing: AppTokens.gapS, runSpacing: AppTokens.gapS, children: [
            Button(
              onPressed: _backToWorkbench,
              child: const Text('返回工作台'),
            ),
            Button(onPressed: _exportMd, child: const Text('导出 Markdown')),
          ]),
        ],
      ),
    );
  }

  Widget _head(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (trailing != null) trailing,
        ]),
      );
}
