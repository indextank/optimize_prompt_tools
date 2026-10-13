/// 六段式结果展示组件（工作台可直接编辑 / 只读两模式共用）
library;

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/models.dart';
import '../theme.dart';

/// 段落标识
class SectionKeys {
  static const role = 'role';
  static const goal = 'goal';
  static const requirements = 'requirements';
  static const constraints = 'constraints';
  static const outputFormat = 'output_format';
  static const acceptance = 'acceptance';

  static const titles = {
    role: '角色定位',
    goal: '任务目标',
    requirements: '具体要求',
    constraints: '约束条件',
    outputFormat: '输出格式',
    acceptance: '验收标准',
  };
}

/// 六段式结果展示。
///
/// [editable] 为 true 时内容直接可编辑（默认自由编辑），
/// 输入停止 800ms 后经 [onEdit] 提交拼装好的新结果
/// （由调用方落库为新版本，与复查编辑同机制）。
class ResultSections extends StatefulWidget {
  const ResultSections({
    super.key,
    required this.result,
    this.scrollController,
    this.editable = false,
    this.onEdit,
  });

  final OptimizeResult result;
  final ScrollController? scrollController;
  final bool editable;
  final ValueChanged<OptimizeResult>? onEdit;

  @override
  State<ResultSections> createState() => _ResultSectionsState();
}

class _ResultSectionsState extends State<ResultSections> {
  final _textCtrls = <String, TextEditingController>{};
  final _itemCtrls = <String, List<TextEditingController>>{};
  Timer? _debounce;
  bool _syncing = false;

  /// 最近一次自己提交的文本指纹：提交引起的重建不回跳控制器（保持光标/焦点）
  String? _lastSubmitted;

  @override
  void initState() {
    super.initState();
    _rebuildControllers();
  }

  @override
  void didUpdateWidget(covariant ResultSections old) {
    super.didUpdateWidget(old);
    if (!widget.editable) return;
    final newFp = widget.result.toPlainText();
    if (newFp == old.result.toPlainText()) return;
    if (newFp == _lastSubmitted) return; // 自己提交的更新：不重建
    _rebuildControllers(); // 外部变化（重新优化/回滚/导入）：重建
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    _textCtrls.clear();
    for (final list in _itemCtrls.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    _itemCtrls.clear();
  }

  void _rebuildControllers() {
    _disposeControllers();
    if (!widget.editable) return;
    _syncing = true;
    final r = widget.result;
    if (!r.isStructured) {
      _textCtrls['raw'] = TextEditingController(text: r.rawText)
        ..addListener(_onAnyEdit);
    } else {
      _textCtrls[SectionKeys.role] = TextEditingController(text: r.role)
        ..addListener(_onAnyEdit);
      _textCtrls[SectionKeys.goal] = TextEditingController(text: r.goal)
        ..addListener(_onAnyEdit);
      _textCtrls[SectionKeys.outputFormat] =
          TextEditingController(text: r.outputFormat)..addListener(_onAnyEdit);
      for (final (key, items) in [
        (SectionKeys.requirements, r.requirements),
        (SectionKeys.constraints, r.constraints),
        (SectionKeys.acceptance, r.acceptance),
      ]) {
        _itemCtrls[key] = [
          for (final t in items)
            TextEditingController(text: t)..addListener(_onAnyEdit),
        ];
      }
    }
    _syncing = false;
  }

  void _onAnyEdit() {
    if (_syncing) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _commit);
  }

  OptimizeResult _collect() {
    final r = widget.result;
    if (!r.isStructured) {
      return OptimizeResult.unstructured(_textCtrls['raw']?.text ?? r.rawText,
          scoreBefore: r.scoreBefore);
    }
    List<String> items(String key) =>
        [for (final c in _itemCtrls[key]!) c.text.trim()]
          ..removeWhere((e) => e.isEmpty);
    return r.copyWithSections(
      role: _textCtrls[SectionKeys.role]?.text ?? r.role,
      goal: _textCtrls[SectionKeys.goal]?.text ?? r.goal,
      requirements: items(SectionKeys.requirements),
      constraints: items(SectionKeys.constraints),
      outputFormat: _textCtrls[SectionKeys.outputFormat]?.text ?? r.outputFormat,
      acceptance: items(SectionKeys.acceptance),
    );
  }

  void _commit() {
    final next = _collect();
    if (next.toPlainText() == widget.result.toPlainText()) return; // 无变化不落版本
    _lastSubmitted = next.toPlainText();
    widget.onEdit?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.editable) {
      return _buildReadOnly();
    }
    return _buildEditable();
  }

  // ---------------------------------------------------------------- 只读
  Widget _buildReadOnly() {
    final result = widget.result;
    if (!result.isStructured) {
      return SingleChildScrollView(
        controller: widget.scrollController,
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(result.rawText,
                style: const TextStyle(fontSize: 12.8, height: 1.7)),
          ),
        ),
      );
    }
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        _SectionBlock(label: SectionKeys.titles[SectionKeys.role]!, content: result.role),
        _SectionBlock(label: SectionKeys.titles[SectionKeys.goal]!, content: result.goal),
        _SectionBlock.list(
            label: SectionKeys.titles[SectionKeys.requirements]!, items: result.requirements),
        _SectionBlock.list(
            label: SectionKeys.titles[SectionKeys.constraints]!, items: result.constraints),
        _SectionBlock(
            label: SectionKeys.titles[SectionKeys.outputFormat]!, content: result.outputFormat),
        _SectionBlock.list(
            label: SectionKeys.titles[SectionKeys.acceptance]!, items: result.acceptance),
      ],
    );
  }

  // ---------------------------------------------------------------- 可编辑
  Widget _buildEditable() {
    final result = widget.result;
    if (!result.isStructured) {
      return SingleChildScrollView(
        controller: widget.scrollController,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextBox(
            controller: _textCtrls['raw'],
            maxLines: null,
            style: const TextStyle(fontSize: 12.8, height: 1.7),
            decoration: WidgetStatePropertyAll(BoxDecoration(
              color: Colors.transparent,
              border: Border.all(color: Colors.transparent),
            )),
          ),
        ),
      );
    }
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        _editableText(SectionKeys.role),
        _editableText(SectionKeys.goal),
        _editableList(SectionKeys.requirements),
        _editableList(SectionKeys.constraints),
        _editableText(SectionKeys.outputFormat),
        _editableList(SectionKeys.acceptance),
      ],
    );
  }

  /// 可编辑文本段：标题 + 内联 TextBox（无边框融入卡片，直接输入修改）
  Widget _editableText(String key) {
    final ctrl = _textCtrls[key];
    if (ctrl == null || ctrl.text.trim().isEmpty) return const SizedBox.shrink();
    return _blockShell(
      key,
      TextBox(
        controller: ctrl,
        maxLines: null,
        style: const TextStyle(fontSize: 12.8, height: 1.65),
        decoration: WidgetStatePropertyAll(BoxDecoration(
          color: Colors.transparent,
          border: Border.all(color: Colors.transparent),
        )),
      ),
    );
  }

  /// 可编辑列表段：每项一行「编号 + 输入框」
  Widget _editableList(String key) {
    final ctrls = _itemCtrls[key];
    if (ctrls == null || ctrls.isEmpty) return const SizedBox.shrink();
    return _blockShell(
      key,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < ctrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text('${i + 1}.',
                      style: const TextStyle(fontSize: 12.8, height: 1.6))),
              const SizedBox(width: 6),
              Expanded(
                child: TextBox(
                  controller: ctrls[i],
                  maxLines: null,
                  style: const TextStyle(fontSize: 12.8, height: 1.6),
                  decoration: WidgetStatePropertyAll(BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(color: Colors.transparent),
                  )),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _blockShell(String key, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
            decoration: BoxDecoration(
              color: AppTokens.accentLight,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(SectionKeys.titles[key]!,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.accentDark)),
          ),
          const SizedBox(height: 3),
          child,
        ]),
      );
}

/// 单个段落块（只读）
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.label, this.content = '', this.items});

  factory _SectionBlock.list({required String label, required List<String> items}) =>
      _SectionBlock(label: label, items: items);

  final String label;
  final String content;
  final List<String>? items;

  @override
  Widget build(BuildContext context) {
    if ((items == null && content.trim().isEmpty) || (items != null && items!.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          decoration: BoxDecoration(
            color: AppTokens.accentLight,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: AppTokens.accentDark)),
        ),
        const SizedBox(height: 5),
        if (items == null)
          SelectableText(content, style: const TextStyle(fontSize: 12.8, height: 1.7))
        else
          ...[
            for (var i = 0; i < items!.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: SelectableText('${i + 1}. ${items![i]}',
                    style: const TextStyle(fontSize: 12.8, height: 1.6)),
              ),
          ],
      ]),
    );
  }
}
