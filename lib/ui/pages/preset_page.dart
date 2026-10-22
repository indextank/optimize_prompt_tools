/// 「编程预置词」页面：技术背景预置词的列表与增删改。
///
/// 三态覆盖：请求进行中 loading / 请求失败错误+重试 / 无数据空状态；
/// 新增与编辑共用弹框（名称必填+唯一、内容 ≤300 字）；
/// 删除先弹确认框。数据经 AppState → AppStorage 持久化（名称唯一性与
/// 长度上限在存储层二次校验）。
library;

import 'dart:ui' as ui show TextDirection;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';

class PresetPage extends StatefulWidget {
  const PresetPage({super.key});

  @override
  State<PresetPage> createState() => _PresetPageState();
}

class _PresetPageState extends State<PresetPage> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await appState.refreshPresets();
    } catch (e) {
      _error = '加载失败：$e';
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final presets = appState.presets;
        final compact =
            MediaQuery.of(context).size.width < AppTokens.compactBreakpoint;
        return ScaffoldPage.withPadding(
          padding:
              EdgeInsets.fromLTRB(compact ? 14 : 26, 14, compact ? 14 : 26, 12),
          content: ListView(children: [
            Row(children: [
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('编程预置词',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('预置技术背景（平台 / 编程语言 / 技术架构等），优化时为 AI 提供上下文',
                          style:
                              TextStyle(fontSize: 12.5, color: AppTokens.text3)),
                    ]),
              ),
              FilledButton(
                onPressed: () => _showEditDialog(null),
                child: const Text('＋ 新增'),
              ),
            ]),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: ProgressRing()),
              )
            else if (_error != null)
              _ErrorView(message: _error!, onRetry: _load)
            else if (presets.isEmpty)
              const _EmptyView()
            else ...[
              if (!compact) _tableHeader(),
              for (final p in presets)
                compact ? _CompactRow(preset: p) : _TableRow(preset: p),
            ],
          ]),
        );
      },
    );
  }

  Widget _tableHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: [
        Expanded(flex: 2, child: _HeadText('名称')),
        Expanded(
            flex: 5,
            child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: _HeadText('内容'))),
        Expanded(flex: 2, child: _HeadText('创建日期')),
        Expanded(
            flex: 2,
            child: Align(
                alignment: Alignment.centerRight,
                child: _HeadText('操作'))),
      ]),
    );
  }

  /// 新增/编辑共用弹框；[preset] 为 null 表示新增
  Future<void> _showEditDialog(CodingPreset? preset) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PresetEditDialog(preset: preset),
    );
    // 保存/编辑成功后列表由 AppState 刷新；此处兜底再刷一次
    if (mounted) await _load();
  }

  Future<void> _confirmDelete(CodingPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('删除预置词'),
        content: Text('确定删除「${preset.name}」吗？删除后不可恢复。'),
        actions: [
          Button(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await appState.deletePreset(preset.id);
      if (mounted) _toast('已删除「${preset.name}」');
    } catch (e) {
      if (mounted) _toast('删除失败：$e', severity: InfoBarSeverity.error);
    }
  }

  void _toast(String msg, {InfoBarSeverity severity = InfoBarSeverity.info}) {
    displayInfoBar(context,
        builder: (context, close) => InfoBar(
              title: Text(msg),
              severity: severity,
              onClose: close,
            ));
  }
}

// ------------------------------------------------------------------ 子组件

/// 内容列单元格：内容按编辑时格式（含换行）完整展示，不截断；
/// 行数在 [maxLines] 内直接全量显示，超过时改为下拉框形式（浮层）展现全文。
class _ContentCell extends StatelessWidget {
  const _ContentCell({required this.content, this.maxLines = 8});
  final String content;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12.5, height: 1.5);
    return LayoutBuilder(builder: (context, constraints) {
      // 实测折行行数（含手动换行），决定是否启用下拉全文
      final painter = TextPainter(
        text: TextSpan(text: content, style: style),
        textDirection: ui.TextDirection.ltr,
        maxLines: maxLines + 1,
      )..layout(maxWidth: constraints.maxWidth);
      final lines = painter.computeLineMetrics().length;
      painter.dispose();
      if (lines <= maxLines) {
        return Text(content, style: style);
      }
      return _LongContentDropdown(content: content, lines: lines);
    });
  }
}

/// 超长内容的下拉框式展示：控件形态与本页下拉一致（边框 + ▾），
/// 点击在下方弹出浮层展示完整内容（可滚动，不截断不折叠）。
class _LongContentDropdown extends StatefulWidget {
  const _LongContentDropdown({required this.content, required this.lines});
  final String content;
  final int lines;

  @override
  State<_LongContentDropdown> createState() => _LongContentDropdownState();
}

class _LongContentDropdownState extends State<_LongContentDropdown> {
  final _controller = FlyoutController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return FlyoutTarget(
      controller: _controller,
      child: GestureDetector(
        onTap: () => _controller.showFlyout(
          builder: (_) => FlyoutContent(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
              child: SingleChildScrollView(
                child: SelectableText(widget.content,
                    style: const TextStyle(fontSize: 12.5, height: 1.6)),
              ),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: AppTokens.border),
            borderRadius: BorderRadius.circular(4),
            color: theme.resources.controlFillColorDefault,
          ),
          child: Row(children: [
            Expanded(
              child: Text('内容共 ${widget.lines} 行 · 点击下拉查看完整内容',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppTokens.text3)),
            ),
            const Text('▾', style: TextStyle(fontSize: 11, color: AppTokens.text3)),
          ]),
        ),
      ),
    );
  }
}

class _HeadText extends StatelessWidget {
  const _HeadText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 12, color: AppTokens.text3));
}

/// 宽屏四列行（名称/内容/创建日期/操作，与表头同栅格）
class _TableRow extends StatelessWidget {
  const _TableRow({required this.preset});
  final CodingPreset preset;

  @override
  Widget build(BuildContext context) {
    final page = context.findAncestorStateOfType<_PresetPageState>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(children: [
        Expanded(
          flex: 2,
          child: Text(preset.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _ContentCell(content: preset.content),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(_fmtDate(preset.createdAt),
              style: const TextStyle(
                  fontSize: 12, color: AppTokens.text3)),
        ),
        Expanded(
          flex: 2,
          // 操作列右对齐：释放的水平空间由内容列（flex 5）承接
          child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Button(
                  onPressed: () => page._showEditDialog(preset),
                  child: const Text('编辑',
                      style: TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(width: AppTokens.gapXs),
                Button(
                  onPressed: () => page._confirmDelete(preset),
                  child: const Text('删除',
                      style: TextStyle(
                          fontSize: 12.5, color: AppTokens.danger)),
                ),
              ]),
        ),
      ]),
    );
  }
}

/// 紧凑窄屏行：堆叠卡片（名称+日期 / 内容 / 操作），防四列挤爆
class _CompactRow extends StatelessWidget {
  const _CompactRow({required this.preset});
  final CodingPreset preset;

  @override
  Widget build(BuildContext context) {
    final page = context.findAncestorStateOfType<_PresetPageState>()!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTokens.border),
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(preset.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Text(_fmtDate(preset.createdAt),
              style:
                  const TextStyle(fontSize: 11, color: AppTokens.text3)),
        ]),
        const SizedBox(height: 6),
        _ContentCell(content: preset.content, maxLines: 6),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Button(
            onPressed: () => page._showEditDialog(preset),
            child: const Text('编辑', style: TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(width: AppTokens.gapXs),
          Button(
            onPressed: () => page._confirmDelete(preset),
            child: const Text('删除',
                style:
                    TextStyle(fontSize: 12.5, color: AppTokens.danger)),
          ),
        ]),
      ]),
    );
  }
}

String _fmtDate(int epochSec) {
  if (epochSec <= 0) return '—';
  return DateFormat('yyyy-MM-dd HH:mm')
      .format(DateTime.fromMillisecondsSinceEpoch(epochSec * 1000));
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text('暂无编程预置词\n点击右上角「＋ 新增」创建技术背景预置词',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTokens.text3, height: 1.8)),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTokens.danger)),
          const SizedBox(height: AppTokens.gapM),
          Button(onPressed: onRetry, child: const Text('重试')),
        ]),
      );
}

// ------------------------------------------------------------------ 编辑弹框

/// 新增/编辑弹框：支持拖拽面板边缘或四角自由调整宽高。
///
/// 默认尺寸在旧弹框（实测 480×380）基础上各放大 1/3（×4/3）；
/// 内部布局随尺寸自适应：内容输入框占据弹性高度，不溢出、不错位、不遮挡。
class _PresetEditDialog extends StatefulWidget {
  const _PresetEditDialog({this.preset});
  final CodingPreset? preset;

  @override
  State<_PresetEditDialog> createState() => _PresetEditDialogState();
}

class _PresetEditDialogState extends State<_PresetEditDialog> {
  /// 默认宽 = 480 × 4/3 = 640；默认高 = 380 × 4/3 ≈ 507
  static const double defaultWidth = 640;
  static const double defaultHeight = 380 * 4 / 3;
  static const double minWidth = 420;
  static const double minHeight = 320;
  static const double _hit = 10;

  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.preset?.name ?? '');
  late final TextEditingController _contentCtrl =
      TextEditingController(text: widget.preset?.content ?? '');
  bool _saving = false;
  String? _error;
  double _w = defaultWidth;
  double _h = defaultHeight;

  bool get _isEdit => widget.preset != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  /// 拖拽调整尺寸：l/r/t/b 指示被拖动的边缘/角（可组合）
  void _resize(Offset delta, {bool l = false, bool r = false, bool t = false, bool b = false}) {
    final screen = MediaQuery.of(context).size;
    setState(() {
      final dw = delta.dx * ((r ? 1 : 0) - (l ? 1 : 0));
      final dh = delta.dy * ((b ? 1 : 0) - (t ? 1 : 0));
      _w = (_w + dw).clamp(minWidth, screen.width - 32);
      _h = (_h + dh).clamp(minHeight, screen.height - 32);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final preset = CodingPreset(
      id: widget.preset?.id ??
          'preset-${nowSec.toString()}-${_nameCtrl.text.hashCode.toRadixString(36)}',
      name: _nameCtrl.text,
      content: _contentCtrl.text,
      createdAt: widget.preset?.createdAt ?? nowSec,
    );
    try {
      await appState.savePreset(preset);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // 吞掉面板外点击，避免穿透
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: const SizedBox.expand(),
        ),
      ),
      Center(
        child: SizedBox(
          key: const Key('preset-dialog-panel'),
          width: _w,
          height: _h,
          child: Stack(children: [
            Positioned.fill(child: _panel(context)),
            // 8 向拖拽手柄：四边 + 四角
            _handle(l: true),
            _handle(r: true),
            _handle(t: true),
            _handle(b: true),
            _handle(l: true, t: true),
            _handle(r: true, t: true),
            _handle(l: true, b: true),
            _handle(r: true, b: true),
          ]),
        ),
      ),
    ]);
  }

  Widget _panel(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // 不透明白底：资源色 cardBackgroundFillColorDefault 带 96% 透明度，
        // 叠加路由遮罩后弹框显得半透明（用户反馈），改纯色彻底取消透明度
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTokens.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_isEdit ? '编辑预置词' : '新增预置词',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('技术背景仅作为优化上下文，不会作为待优化内容',
            style: TextStyle(fontSize: 14, color: AppTokens.text3)),
        const SizedBox(height: 14),
        const Text('名称', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 4),
        TextBox(
          controller: _nameCtrl,
          placeholder: '例如：Electron + Vue3 桌面端',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppTokens.gapM),
        const Text('内容', style: TextStyle(fontSize: 14)),
        const SizedBox(height: 4),
        // 内容输入框占据弹性高度：弹框调大调小时随之伸缩
        Expanded(
          child: TextBox(
            controller: _contentCtrl,
            maxLines: null,
            expands: true,
            placeholder: '描述技术背景：目标平台、编程语言、技术架构、关键约束等',
            inputFormatters: [
              LengthLimitingTextInputFormatter(CodingPreset.maxContentChars),
            ],
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          const Expanded(
            child: Text('内容超过 300 字禁止输入',
                style: TextStyle(fontSize: 14, color: AppTokens.text3)),
          ),
          Text('${_contentCtrl.text.length}/${CodingPreset.maxContentChars}',
              style:
                  const TextStyle(fontSize: 14, color: AppTokens.text3)),
        ]),
        if (_error != null) ...[
          const SizedBox(height: AppTokens.gapS),
          Text(_error!,
              style: const TextStyle(fontSize: 12, color: AppTokens.danger)),
        ],
        const SizedBox(height: AppTokens.gapM),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Button(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: AppTokens.gapS),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 14, height: 14, child: ProgressRing(strokeWidth: 2))
                : Text(_isEdit ? '保存' : '新增'),
          ),
        ]),
      ]),
    );
  }

  /// 边缘/角拖拽命中带（面板边缘 10px，角部覆盖两轴）
  Widget _handle({bool l = false, bool r = false, bool t = false, bool b = false}) {
    final isCorner = (l || r) && (t || b);
    final cursor = switch ((l || r, t || b)) {
      (true, true) => SystemMouseCursors.resizeUpLeftDownRight,
      (true, false) => SystemMouseCursors.resizeLeftRight,
      (false, true) => SystemMouseCursors.resizeUpDown,
      (false, false) => SystemMouseCursors.basic,
    };
    final horizontal = l || r;
    final vertical = t || b;
    return Positioned(
      // 单边手柄沿该边拉伸（对面边缘留 8px 让开角部），角块固定 18×18；
      // 四轴定位必须成对完整，否则子件拿到无界约束（infinite size）
      left: l ? -_hit / 2 : (horizontal ? null : 8),
      right: r ? -_hit / 2 : (horizontal ? null : 8),
      top: t ? -_hit / 2 : (vertical ? null : 8),
      bottom: b ? -_hit / 2 : (vertical ? null : 8),
      width: horizontal ? (isCorner ? 18 : _hit) : null,
      height: vertical ? (isCorner ? 18 : _hit) : null,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => _resize(d.delta, l: l, r: r, t: t, b: b),
        ),
      ),
    );
  }
}
