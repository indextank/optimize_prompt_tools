/// 优化工作台页壳：多 tab 容器（fluent [TabView]）。
///
/// 每个 tab 的业务 UI 为 [WorkbenchPanel]（单 tab 数据源），输入/按钮/结果
/// 业务逻辑仅存在于 Panel 一处，不在本页复制。
///
/// Tab 对象按 id 缓存（[_tabCache]）保证实例稳定：[Tab] 内部持有 GlobalKey，
/// 且 tab body 以 `ValueKey<Tab>` 索引，重建实例会导致切换/重绘时
/// WorkbenchPanel 的 State 被销毁（SSE 流中断、输入状态丢失）。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';

import '../../state/app_state.dart';
import '../../state/workbench_tabs.dart' show WorkbenchTabRuntime;
import '../theme.dart';
import 'workbench_panel.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key});

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage>
    with WidgetsBindingObserver {
  /// 按 tab id 缓存的 Tab 对象；关闭 tab 时移除对应缓存。
  ///
  /// 缓存不变量：
  /// 1) 首 tab 恒定位于 index 0：closeTab 拒绝关闭 index 0，且 TabView 未启用
  ///    重排（onReorder 为 null），故其 closable=false 在创建时确定且终身不变；
  /// 2) 同 id 的 runtime 不会被替换：id 在创建时唯一分配，runtime 只随 closeTab
  ///    销毁并同步驱逐缓存条目，同 id 不会再次出现。因此缓存条目与其
  ///    WorkbenchTabRuntime 终身一一绑定，只需增删、无需更新。
  final Map<String, Tab> _tabCache = <String, Tab>{};

  /// 标签条滚动控制器：TabView 内置滚轮/翻页按钮与鼠标拖拽平移共用。
  /// 外部持有（TabView 不会释放外部 controller），由本 State 释放。
  final ScrollPosController _stripScroll = ScrollPosController(
    itemCount: 0,
    animate: false,
  );

  /// 上一帧布局尺寸与 tab 数量：变化时将激活 tab 滚入可视区。
  Size? _lastLayoutSize;
  int _lastTabCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stripScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // 窗口尺寸变化后滚动范围重算，post-frame 将激活 tab 滚入可视区
    _scheduleScrollToActive();
  }

  void _scheduleScrollToActive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 首帧布局未完成时 position 可能尚无 contentDimensions，避免 assert
      if (_stripScroll.hasClients &&
          _stripScroll.position.hasContentDimensions) {
        _stripScroll.scrollToItem(appState.tabs.activeIndex, animate: false);
      }
    });
  }

  /// 构造（或复用缓存中的）[Tab]。
  ///
  /// 首 tab 固定不可关闭（`onClosed == null`）；其余 tab 的 `onClosed` 仅用于
  /// 内置快捷键（Ctrl+W），内置 x 隐藏（`closeIcon: null`），标题行内渲染
  /// 自定义关闭按钮（见 [_TabTitle]）。
  Tab _buildTab(int index, WorkbenchTabRuntime runtime) {
    final id = runtime.state.id;
    return _tabCache.putIfAbsent(id, () {
      final closable = index > 0;
      return Tab(
        closeIcon: null, // 隐藏内置 x，改用标题行内自定义关闭按钮
        onClosed: closable ? () => appState.tabs.closeTab(id) : null,
        // 显式浅色标签配色（AppTokens 令牌）：fluent 默认为半透明 Mica 层，
        // 透明标签叠在未绘制区域（引擎黑底）上会黑底黑字。激活=白卡、
        // 非激活=浅灰深字，标题/关闭按钮文字经 DefaultTextStyle 继承同一前景色。
        backgroundColor: AppTokens.tabBg,
        foregroundColor: AppTokens.tabFg,
        selectedBackgroundColor: AppTokens.tabSelectedBg,
        selectedForegroundColor: AppTokens.tabSelectedFg,
        // 不设 semanticLabel：Tab 实例被缓存，label 会冻结在创建时的标题，
        // 改名后成为过期的可访问性标签（比没有更糟）。标题的语义/提示由
        // [_TabTitle] 内的 Tooltip 随 runtime.state.title 实时重建。
        text: _TabTitle(runtime: runtime, closable: closable),
        body: WorkbenchPanel(key: ValueKey(id), runtime: runtime),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final tabs = appState.tabs.tabs;
        // 移除已关闭 tab 的缓存（其 Tab 实例随之销毁，body State 一并释放）
        _tabCache.removeWhere((id, _) => tabs.every((r) => r.state.id != id));
        final tabList = [
          for (var i = 0; i < tabs.length; i++) _buildTab(i, tabs[i]),
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            if (size != _lastLayoutSize || tabs.length != _lastTabCount) {
              _lastLayoutSize = size;
              _lastTabCount = tabs.length;
              _scheduleScrollToActive();
            }
            return ColoredBox(
              // TabView 本体不涂底色：strip 顶部留白（margin 4.5）等区域
              // 若透明会露出未绘制的引擎黑底，浅色主题下呈黑条
              color: FluentTheme.of(context).scaffoldBackgroundColor,
              child: TabView(
                currentIndex: appState.tabs.activeIndex,
                onChanged: appState.tabs.switchTab,
                onNewPressed: appState.tabs.addTab,
                tabWidthBehavior: TabWidthBehavior.sizeToContent,
                showScrollButtons: true,
                shortcutsEnabled: true,
                scrollController: _stripScroll,
                tabs: tabList,
                // 标签条显式浅色背景（同 scaffold 底色）+ 鼠标拖拽平移由内层
                // Scrollable 承担（ScrollBehavior 的 dragDevices 含 mouse 即可），
                // 不做外层 GestureDetector 兜底：双识别器会引入首段位移吞失
                // 与手势竞争
                stripBuilder: (context, strip) => ColoredBox(
                  color: FluentTheme.of(context).scaffoldBackgroundColor,
                  child: ScrollConfiguration(
                    behavior: const _StripScrollBehavior(),
                    child: strip,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 自定义 tab 标题：单行标题 + 可关闭时右侧自定义关闭按钮。
///
/// 关闭按钮约 32×27（Key/Tooltip/图标按钮；高受 TabView 标签行物理限制），
/// 事件只关闭该 tab，不触发标签切换（内部按钮赢得点击手势，不冒泡到 Tab
/// 的 HoverButton）。
class _TabTitle extends StatelessWidget {
  const _TabTitle({required this.runtime, required this.closable});

  final WorkbenchTabRuntime runtime;
  final bool closable;

  @override
  Widget build(BuildContext context) {
    final localizations = FluentLocalizations.of(context);
    // Tab 实例被缓存，标题需自行监听状态变化（如程序化改名）
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              // Tooltip 消息与语义标签均跟随 runtime.state.title：本组件监听
              // appState 重建，程序化改名后提示即时更新（Tab 缓存不会冻结它）
              child: Tooltip(
                message: runtime.state.title,
                child: Text(
                  runtime.state.title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (closable)
              Tooltip(
                message: localizations.closeTabLabel,
                // 目标宽 32、高随 TabView 标签行（高 34、内容区 27~28）自然钳制
                // 为约 32×27：真实命中区即布局值，不做溢出虚报
                child: SizedBox(
                  key: Key('close-tab-${runtime.state.id}'),
                  width: 32,
                  height: 32,
                  child: IconButton(
                    icon: const WindowsIcon(
                      WindowsIcons.chrome_close,
                      size: 10,
                    ),
                    onPressed: () => appState.tabs.closeTab(runtime.state.id),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 标签条滚动行为：鼠标拖拽平移标签条，且不渲染滚动条。
class _StripScrollBehavior extends ScrollBehavior {
  const _StripScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        ...super.dragDevices,
        PointerDeviceKind.mouse,
      };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
