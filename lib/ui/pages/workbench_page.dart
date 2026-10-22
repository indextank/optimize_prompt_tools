/// 优化工作台：原始提示词输入 / 优化结果展示 / 优化模式与操作条。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/models.dart';
import '../../services/parallel_scheduler.dart';
import '../../state/app_state.dart';
import '../../app.dart';
import '../theme.dart';
import '../widgets/section_view.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key});

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  /// 左右分栏比例（左栏占比），可通过中部拖拽手柄调整
  double _split = 10 / 22;

  final _inputCtrl = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _inputCtrl.text = appState.session.rawText;
    _inputCtrl.addListener(() {
      appState.session.rawText = _inputCtrl.text;
      setState(() {}); // 字数统计
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _onOptimize() async {
    final record = await appState.startOptimize();
    if (!mounted) return;
    if (record != null) {
      if (appState.settings.settings.autoCopy) await _copyResult(record.latest.result);
      setState(() {});
    } else if (appState.session.errorMessage != null) {
      _toast(appState.session.errorMessage!, severity: InfoBarSeverity.error);
    }
    setState(() {});
  }

  Future<void> _copyResult(OptimizeResult r) async {
    await Clipboard.setData(ClipboardData(text: r.toPlainText()));
    if (mounted) _toast('已复制到剪贴板', severity: InfoBarSeverity.success);
  }

  /// 并行对比：复制指定列（1/2）的优化结果
  Future<void> _copyParallelResult(ParallelRunState st, int index) async {
    await Clipboard.setData(
        ClipboardData(text: st.runResult!.result.toPlainText()));
    if (mounted) {
      _toast('已复制结果$index 到剪贴板', severity: InfoBarSeverity.success);
    }
  }

  void _toast(String msg, {InfoBarSeverity severity = InfoBarSeverity.info}) {
    displayInfoBar(context, builder: (context, close) => InfoBar(
          title: Text(msg),
          severity: severity,
          onClose: close,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final session = appState.session;
        final record = session.currentRecord;
        final compact = MediaQuery.of(context).size.width < AppTokens.compactBreakpoint;
        return ScaffoldPage.withPadding(
          padding: EdgeInsets.fromLTRB(compact ? 14 : 26, 14, compact ? 14 : 26, 12),
          content: compact
              // 窄屏（手机竖屏）：输入/结果上下堆叠；模式选择器在结果卡上方
              ? Column(children: [
                  _buildHeader(),
                  const SizedBox(height: AppTokens.gapM),
                  Expanded(
                    child: ListView(children: [
                      SizedBox(height: 340, child: _buildInputCard()),
                      const SizedBox(height: AppTokens.gapM),
                      _buildModeSelector(),
                      const SizedBox(height: AppTokens.gapM),
                      SizedBox(height: 420, child: _buildResultCard(record)),
                    ]),
                  ),
                ])
              // 桌面：左右双栏（比例可拖拽调整）；模式选择器在结果卡上方
              : Column(children: [
                  _buildHeader(),
                  const SizedBox(height: AppTokens.gapM),
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      const handleW = AppTokens.gapL;
                      final avail = constraints.maxWidth - handleW;
                      final leftW = avail * _split;
                      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(width: leftW, child: _buildInputCard()),
                        _buildSplitHandle(avail),
                        SizedBox(
                          width: avail - leftW,
                          child: Column(children: [
                            _buildModeSelector(),
                            const SizedBox(height: AppTokens.gapM),
                            Expanded(child: _buildResultCard(record)),
                          ]),
                        ),
                      ]);
                    }),
                  ),
                ]),
        );
      },
    );
  }

  // ---------------------------------------------------------------- 头部
  Widget _buildHeader() {
    const titleColumn = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('优化工作台', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      SizedBox(height: 4),
      Text('输入原始想法，一键优化为结构化、可直接投喂给 AI 的高质量提示词',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: AppTokens.text3)),
    ]);
    // 紧凑窄屏：标题与控制组上下两行（控制组获全宽约束，内部自行换行，杜绝溢出）
    if (MediaQuery.of(context).size.width < AppTokens.compactBreakpoint) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        titleColumn,
        const SizedBox(height: 8),
        Wrap(
          spacing: AppTokens.gapS,
          runSpacing: AppTokens.gapXs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: _buildParallelControls(context),
        ),
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      const Expanded(child: titleColumn),
      const SizedBox(width: 12),
      // 右侧控制组：Wrap 右对齐——窄屏自动换行，绝不超出页面右缘 padding
      Wrap(
        spacing: AppTokens.gapS,
        runSpacing: AppTokens.gapXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: _buildParallelControls(context),
      ),
    ]);
  }

  /// 并行对比控制组（头部右侧）：开关 + 锁定提示 / 对比模型下拉 + 生效提示
  List<Widget> _buildParallelControls(BuildContext context) {
    final session = appState.session;
    final parallelOn = appState.settings.settings.parallelEnabled;
    final canParallel = appState.canEnableParallel;
    final eff = appState.effectiveService;
    final candidates = [for (final sv in appState.services) if (sv.id != eff?.id) sv];
    final compact = MediaQuery.of(context).size.width < AppTokens.compactBreakpoint;
    return [
      // 单模型（<2 个服务）时锁定开关并说明原因
      if (!canParallel)
        const Text('配置 ≥2 个 AI 服务后可开启并行对比',
            style: TextStyle(fontSize: 11, color: AppTokens.warning)),
      ToggleSwitch(
        checked: canParallel && parallelOn,
        onChanged: canParallel
            ? (v) async {
                await appState.settings.update(
                    appState.settings.settings.copyWith(parallelEnabled: v));
                if (!mounted) return;
                setState(() {
                  if (v) {
                    // 开启后默认选中对比模型下拉框中的第一个（候选非空时）
                    session.parallelServiceId =
                        candidates.isNotEmpty ? candidates.first.id : null;
                  } else {
                    session.parallelServiceId = null;
                  }
                });
              }
            : null, // 仅 1 个可用模型时锁定为不可开启
        content: compact
            ? null
            : const Text('并行对比', style: TextStyle(fontSize: 12.5)),
      ),
      // 开关开启后实时展示对比模型下拉框；关闭自动隐藏
      if (canParallel && parallelOn)
        ComboBox<String>(
          value: session.parallelServiceId ?? '',
          placeholder:
              const Text('选择对比模型', style: TextStyle(fontSize: 12.5)),
          items: [
            if (session.parallelServiceId == null ||
                !candidates.any((sv) => sv.id == session.parallelServiceId))
              const ComboBoxItem(
                  value: '',
                  child: Text('选择对比模型', style: TextStyle(fontSize: 12.5))),
            for (final sv in candidates)
              // 仅展示模型名称，不显示提供商名称；单选
              ComboBoxItem(
                  value: sv.id,
                  child: Text(sv.model, style: const TextStyle(fontSize: 12.5))),
          ],
          onChanged: (v) {
            if (v != null && v.isNotEmpty) {
              setState(() => session.parallelServiceId = v);
            }
          },
        ),
      // 已开启但未选择对比模型时的生效提示
      if (canParallel && parallelOn && appState.parallelCandidateCount < 2)
        const Text('选择对比模型后并行生效',
            style: TextStyle(fontSize: 11, color: AppTokens.warning)),
    ];
  }

  // ---------------------------------------------------------------- 输入卡
  Widget _buildInputCard() {
    final session = appState.session;
    final len = appState.session.rawText.trim().length;
    return Card(
      padding: EdgeInsets.zero,
      // Column 默认 crossAxisAlignment.center：场景 chips 等自然宽子行会被居中，
      // 导致与标题左缘错位（图1-C）——统一左对齐
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _cardHead('原始提示词'),
        // 场景 chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            for (final s in appState.scenes)
              _SceneChip(
                label: s.name,
                selected: appState.session.sceneId == s.id,
                onTap: () => setState(() => appState.session.sceneId = s.id),
              ),
          ]),
        ),
        // 编程预置词下拉：仅「AI 编程 / Bug 修复」场景展示（为优化提供技术背景）；
        // 状态管理与本页其他会话表单控件一致（session + setState）
        if (const ['ai_coding', 'bug_fix'].contains(session.sceneId))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              const Text('编程预置词',
                  style: TextStyle(fontSize: 12.5, color: AppTokens.text2)),
              const SizedBox(width: AppTokens.gapS),
              Expanded(
                child: ComboBox<String>(
                  value: session.presetId ?? '',
                  placeholder: const Text('（不使用）',
                      style: TextStyle(fontSize: 12.5)),
                  items: [
                    // 默认空选项：允许不使用预置词（优化流程保持现状）
                    const ComboBoxItem(
                        value: '',
                        child: Text('（不使用）', style: TextStyle(fontSize: 12.5))),
                    for (final p in appState.presets)
                      ComboBoxItem(
                          value: p.id,
                          child: Text(p.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5))),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => session.presetId = v.isEmpty ? null : v);
                    }
                  },
                ),
              ),
            ]),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextBox(
              controller: _inputCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              placeholder: '例如：帮我写个爬虫爬豆瓣电影 Top250，要存到 Excel 里……',
              style: const TextStyle(fontSize: 13.5, height: 1.6),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            const Expanded(
              child: Text('Ctrl+Enter 快速优化 · 支持粘贴长文本',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppTokens.text3)),
            ),
            // 字数统计：输入框最下方，「粘贴」按钮左侧
            Text('$len 字',
                style: const TextStyle(fontSize: 12, color: AppTokens.text3)),
            const SizedBox(width: AppTokens.gapM),
            Button(
              child: const Text('📋 粘贴'),
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                final t = data?.text ?? '';
                if (t.isNotEmpty) {
                  _inputCtrl.text = '${_inputCtrl.text}$t';
                  _inputCtrl.selection =
                      TextSelection.collapsed(offset: _inputCtrl.text.length);
                }
              },
            ),
            const SizedBox(width: 8),
            Button(
              child: const Text('清空'),
              onPressed: () {
                _inputCtrl.clear();
                appState.session.currentRecord = null;
                appState.session.reset();
              },
            ),
          ]),
        ),
        // 主操作按钮：单独一行置于「粘贴/清空」下方，正常宽度居中对齐
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Center(child: _buildPrimaryButton()),
        ),
      ]),
    );
  }

  /// 开始优化主按钮状态机：
  /// - 首次优化进行中（尚无结果记录）：变为「取消优化」+ 旋转环，承载取消入口
  /// - 重新优化进行中：取消入口在右侧结果卡「取消优化」按钮，此处禁用避免双入口
  /// - 提问式答题中：变为「取消优化」（无旋转环——等待用户而非模型），可取消提问流程
  /// - 空闲：「✨ 开始优化」，按 canOptimize 启停
  Widget _buildPrimaryButton() {
    final session = appState.session;
    final optimizing = session.optimizing;
    final hasRecord = session.currentRecord != null;
    if (optimizing && hasRecord) {
      return const FilledButton(onPressed: null, child: Text('✨ 开始优化'));
    }
    if (optimizing || session.askAnswering) {
      return FilledButton(
        onPressed: appState.cancelOptimize,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (optimizing) ...const [
            SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2.5)),
            SizedBox(width: 8),
          ],
          const Text('取消优化', style: TextStyle(fontSize: 14)),
        ]),
      );
    }
    return FilledButton(
      onPressed: appState.canOptimize ? _onOptimize : null,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Text('✨ 开始优化', style: TextStyle(fontSize: 14)),
      ),
    );
  }

  // ---------------------------------------------------------------- 结果卡
  Widget _buildResultCard(OptimizeRecord? record) {
    final session = appState.session;
    final optimizing = session.optimizing;
    final svc = appState.effectiveService;
    final streamingText = svc == null ? '' : (session.streaming[svc.id] ?? '');

    Widget body;
    if (session.askAnswering) {
      body = _buildAskPanel();
    } else if (session.parallelStates.length >= 2) {
      // 并行对比：流式进行中与完成后均按双列布局展示各模型结果
      body = _ParallelCompareView(states: session.parallelStates);
    } else if (optimizing && record == null) {
      body = _StreamingView(text: streamingText, parallel: session.parallelStates);
    } else if (record != null) {
      // 结果区默认自由编辑：输入停止 800ms 自动落库为新版本（与复查编辑同机制）
      body = ResultSections(
        result: record.latest.result,
        scrollController: _scroll,
        editable: true,
        onEdit: (next) async {
          await appState.saveEditedResult(next);
        },
      );
    } else if (session.errorMessage != null) {
      body = Center(
          child: Text(session.errorMessage!,
              style: const TextStyle(color: AppTokens.danger)));
    } else {
      final compact = MediaQuery.of(context).size.width < AppTokens.compactBreakpoint;
      body = Center(
          child: Text(
              compact
                  ? '优化结果将在这里展示\n输入上方原始想法后点击「开始优化」'
                  : '优化结果将在这里展示\n输入左侧原始想法后点击「开始优化」',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTokens.text3, height: 1.8)));
    }

    final r = record?.latest.result;
    return Card(
      padding: EdgeInsets.zero,
      child: Column(children: [
        _cardHead('优化结果',
            hint: '内容可直接编辑 · 修改自动保存',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (r?.scoreAfter != null)
            _ScorePill(before: r!.scoreBefore, after: r.scoreAfter!),
          if (record != null) ...[
            const SizedBox(width: 8),
            // 版本文字可收缩省略：空间不足时优先保评分胶囊完整，杜绝整体溢出
            Flexible(
              child: Text('v${record.latest.v} · ${record.mode.label}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppTokens.text3)),
            ),
          ],
        ])),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: body)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          // 左侧：输出详略下拉（简单/完整模式，默认简单）；右侧：操作按钮组靠右对齐。
          // 注意用 Row 而非 Wrap：Wrap 在松散约束下会收缩为自然宽并被 Column 居中，
          // 导致按钮组无法真正靠右（本需求的根因）。
          child: Builder(builder: (context) {
            final narrow = MediaQuery.of(context).size.width < AppTokens.compactBreakpoint;
            final dropdown = ComboBox<OutputStyle>(
              value: session.outputStyle,
              items: [
                for (final st in OutputStyle.values)
                  ComboBoxItem(
                      value: st,
                      child: Text(st.label, style: const TextStyle(fontSize: 12.5))),
              ],
              onChanged: (v) {
                if (v != null) setState(() => session.outputStyle = v);
              },
            );
            final parallelEntries = session.parallelStates.entries.toList();
            // 双复制按钮条件：并行对比开启 且 当前结果为并行双列产出
            final showDualCopy = appState.settings.settings.parallelEnabled &&
                parallelEntries.length >= 2;
            final buttonChildren = <Widget>[
              _buildReoptimizeButton(record),
              Button(
                  onPressed: record == null || optimizing
                      ? null
                      : () => navigateTo(context, AppShellState.reviewEdit),
                  child: const Text('📝 复查编辑')),
              // 并行对比结果（双列）：「一键复制」拆为「复制结果1/2」，
              // 各复制对应列的优化结果（列序与双列展示一致）；
              // 关闭并行对比后复原为单一「一键复制」。
              if (showDualCopy)
                for (var i = 0; i < 2 && i < parallelEntries.length; i++)
                  FilledButton(
                      onPressed: parallelEntries[i].value.success && !optimizing
                          ? () => _copyParallelResult(
                              parallelEntries[i].value, i + 1)
                          : null,
                      child: Text('复制结果${i + 1}'))
              else
                FilledButton(
                    onPressed: record == null || optimizing
                        ? null
                        : () => _copyResult(record.latest.result),
                    child: const Text('📄 一键复制')),
            ];
            // 紧凑窄屏：上下两行，按钮组 Wrap 右对齐（超宽自动换行防溢出）
            if (narrow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                dropdown,
                const SizedBox(height: AppTokens.gapS),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppTokens.gapXs,
                    runSpacing: AppTokens.gapXs,
                    children: buttonChildren,
                  ),
                ),
              ]);
            }
            return Row(children: [
              dropdown,
              const Expanded(child: SizedBox()),
              for (var i = 0; i < buttonChildren.length; i++) ...[
                if (i > 0) const SizedBox(width: AppTokens.gapS),
                buttonChildren[i],
              ],
            ]);
          }),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------- 提问面板
  Widget _buildAskPanel() {
    final qs = appState.session.questions;
    return Column(children: [
      Expanded(
        child: ListView(children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('请先回答以下关键问题（可标记跳过，AI 将采用最小安全假设）：',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          for (var i = 0; i < qs.length; i++) _AskItem(index: i, question: qs[i]),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          FilledButton(
            onPressed: () async {
              final rec = await appState.finalizeAsk();
              if (!mounted) return;
              if (rec != null && appState.settings.settings.autoCopy) {
                await _copyResult(rec.latest.result);
              }
              setState(() {});
            },
            child: const Text('✨ 生成优化提示词'),
          ),
        ]),
      ),
    ]);
  }

  /// 分栏拖拽手柄：左右拖动调整「原始提示词 / 优化结果」宽度比
  Widget _buildSplitHandle(double avail) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          setState(() {
            _split = (_split + d.delta.dx / avail).clamp(0.25, 0.75);
          });
        },
        child: SizedBox(
          key: const Key('split-handle'),
          width: AppTokens.gapL,
          child: Center(
            child: Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: AppTokens.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 模式选择器（结果卡上方独立模块）
  Widget _buildModeSelector() {
    final session = appState.session;
    // 独立模块区域：背景色与「优化结果」卡片一致，宽度与结果卡一致。
    // SizedBox(double.infinity)：Column 松散约束下 Card 会收缩为内容自然宽并被居中。
    return SizedBox(
      width: double.infinity,
      child: Card(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          // 仅保留模式选择组，居左展示；并行对比开关组已迁至页面头部右侧
          child: Wrap(
            spacing: AppTokens.gapS,
            runSpacing: AppTokens.gapXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('优化模式',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.text3)),
              for (final m in OptimizeMode.values)
                _ModeSegment(
                  label: m.label,
                  selected: session.mode == m,
                  onTap: () => setState(() => session.mode = m),
                ),
              if (session.droppedProviderNames.isNotEmpty)
                Text('超出并行上限已忽略：${session.droppedProviderNames.join("、")}',
                    style: const TextStyle(fontSize: 11, color: AppTokens.warning)),
            ],
          ),
        ),
      ),
    );
  }

  /// 重新优化按钮：重新优化进行中变为「取消优化」+ 旋转环（取消入口唯一化）
  Widget _buildReoptimizeButton(OptimizeRecord? record) {
    final optimizing = appState.session.optimizing;
    if (optimizing && record != null) {
      return Button(
        onPressed: appState.cancelOptimize,
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2.5)),
          SizedBox(width: 8),
          Text('取消优化'),
        ]),
      );
    }
    return Button(
      onPressed: record == null || optimizing ? null : _onOptimize,
      child: const Text('↻ 重新优化'),
    );
  }

  Widget _cardHead(String title, {Widget? trailing, String? hint}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(hint,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppTokens.text3)),
            ),
          ],
          const Spacer(),
          if (trailing != null) Flexible(child: trailing),
        ]),
      );
}

// ==================== 小组件 ====================

class _SceneChip extends StatelessWidget {
  const _SceneChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppTokens.accentLight : Colors.white,
          border: Border.all(color: selected ? AppTokens.accent : AppTokens.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected ? AppTokens.accentDark : AppTokens.text2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFFF0F1F2),
          borderRadius: BorderRadius.circular(5),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 2)]
              : null,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                color: selected ? AppTokens.accentDark : AppTokens.text2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({this.before, required this.after});
  final int? before;
  final int after;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        before == null ? '质量评分 $after / 100' : '质量评分 $before → $after',
        style: const TextStyle(fontSize: 12, color: AppTokens.success, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 请求耗时格式化：精确到分秒，如「总耗时2分34秒」
String _fmtElapsed(int ms) {
  final totalSec = (ms / 1000).round();
  final m = totalSec ~/ 60;
  final sec = totalSec % 60;
  return m > 0 ? '总耗时$m分$sec秒' : '总耗时$totalSec秒';
}

/// 并行对比双列结果视图：每个成功/进行中的模型一列，
/// 按当前输出模式渲染（完整模式=六段结构，简单模式=整段纯文本）。
class _ParallelCompareView extends StatelessWidget {
  const _ParallelCompareView({required this.states});
  final Map<String, ParallelRunState> states;

  @override
  Widget build(BuildContext context) {
    final entries = states.entries.toList();
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < entries.length; i++) ...[
        if (i > 0) const SizedBox(width: AppTokens.gapS),
        Expanded(child: _ParallelColumn(entry: entries[i])),
      ],
    ]);
  }
}

class _ParallelColumn extends StatelessWidget {
  const _ParallelColumn({required this.entry});
  final MapEntry<String, ParallelRunState> entry;

  @override
  Widget build(BuildContext context) {
    final st = entry.value;
    final modelName = st.service.model;
    Widget content;
    if (st.error != null) {
      content = Text('调用失败：${st.error is LlmException ? (st.error as LlmException).userMessage : st.error}',
          style: const TextStyle(fontSize: 12, color: AppTokens.danger, height: 1.6));
    } else if (st.success) {
      final r = st.runResult!.result;
      content = r.isStructured
          ? ResultSections(result: r)
          : SingleChildScrollView(
              child: SelectableText(r.rawText,
                  style: const TextStyle(fontSize: 12.5, height: 1.7)));
    } else {
      final streamed = appState.session.streaming[entry.key] ?? '';
      content = SingleChildScrollView(
        child: Text(streamed.isEmpty ? '请求中…' : streamed,
            style: const TextStyle(fontSize: 12, height: 1.6, color: AppTokens.text3)),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 4, top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 列头：模型名 + 状态
        Row(children: [
          Expanded(
            child: Text(modelName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          if (st.error != null)
            const Text('✗ 失败', style: TextStyle(fontSize: 11, color: AppTokens.danger))
          else if (st.success)
            Text('✓ 完成 ${_fmtElapsed(st.elapsedMs)}',
                style: const TextStyle(fontSize: 11, color: AppTokens.success))
          else
            const SizedBox(
                width: 12, height: 12, child: ProgressRing(strokeWidth: 2)),
        ]),
        const SizedBox(height: 6),
        Expanded(child: content),
      ]),
    );
  }
}

class _StreamingView extends StatelessWidget {
  const _StreamingView({required this.text, required this.parallel});
  final String text;
  final Map<String, dynamic> parallel;

  @override
  Widget build(BuildContext context) {
    if (parallel.isNotEmpty) {
      // 并行：每模型一个状态块
      return ListView(children: [
        for (final e in parallel.entries)
          Card(
            margin: const EdgeInsets.only(bottom: 8, top: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(getProviderConfig(e.value.service.provider)?.name ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              const SizedBox(height: 6),
              if (e.value.error != null)
                Text('失败：${e.value.error}',
                    style: const TextStyle(color: AppTokens.danger, fontSize: 12))
              else if (e.value.success)
                Text(e.value.runResult!.result.toPlainText(),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.6))
              else
                Text(
                    (appState.session.streaming[e.key] ?? '').isEmpty
                        ? '请求中…'
                        : appState.session.streaming[e.key]!,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.6)),
            ]),
          ),
      ]);
    }
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(text.isEmpty ? '正在请求模型…' : text,
            style: const TextStyle(fontSize: 12.8, height: 1.7)),
      ),
    );
  }
}

class _AskItem extends StatefulWidget {
  const _AskItem({required this.index, required this.question});
  final int index;
  final ClarifyQuestion question;

  @override
  State<_AskItem> createState() => _AskItemState();
}

class _AskItemState extends State<_AskItem> {
  final _ctrl = TextEditingController();
  bool _skipped = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Q${widget.index + 1}：${widget.question.question}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          ToggleSwitch(
            checked: _skipped,
            onChanged: (v) {
              setState(() {
                _skipped = v;
                appState.session.answers[widget.index] = v ? null : _ctrl.text;
              });
            },
            content: const Text('跳过', style: TextStyle(fontSize: 11.5)),
          ),
        ]),
        if (widget.question.decides.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text('决定：${widget.question.decides}',
                style: const TextStyle(fontSize: 11, color: AppTokens.text3)),
          ),
        if (!_skipped)
          TextBox(
            controller: _ctrl,
            placeholder: '填写你的回答…',
            maxLines: 2,
            onChanged: (t) => appState.session.answers[widget.index] = t,
          ),
      ]),
    );
  }
}
