/// 工作台多 tab（TabView 重构）验收测试：
/// A) 固定首 tab 无关闭入口、新增 tab 带 x；点击 x 只关目标 tab；
///    关闭激活 tab 后激活右侧，末尾激活左侧；首 tab.onClosed 为 null。
/// B) 多 tab 输入/面板状态独立；切换前后 WorkbenchPanel State 实例保持相同
///   （Tab 对象缓存 + keepAlive）；后台 tab 的 runtime 切换后继续可用。
/// C) 10+ tab 窄窗口：标签单行不换行/不重叠、scrollController.max>0；
///    标签条鼠标横向拖拽与滚轮均可平移且能到达末尾；扩大窗口后范围更新且激活 tab 可见。
/// D) 关闭按钮具备 Key/Tooltip 与约 32×27 点击区域；点击 x 不触发标签切换。
/// E) 标签标题的 Tooltip/语义跟随 runtime.state.title（改名后不过期）。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/state/workbench_tabs.dart'
    show WorkbenchTabRuntime;
import 'package:prompt_optimizer/ui/pages/workbench_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 跨用例持有上一份 appState，供 setUp 释放，避免 tabs/runtime/存储泄漏
  AppState? previousAppState;

  setUp(() async {
    previousAppState?.dispose();
    final state = await makeTestAppState(llm: FakeLlmClient());
    previousAppState = state;
    appState = state;
  });

  Future<void> pumpPage(WidgetTester tester,
      {double w = 1440, double h = 900}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const WorkbenchPage()));
    await tester.pumpAndSettle();
  }

  /// 按 id 定位自定义关闭按钮（Key('close-tab-<id>')）
  Finder closeBtn(String id) => find.byKey(Key('close-tab-$id'));

  WorkbenchTabRuntime runtimeAt(int i) => appState.tabs.tabs[i];

  /// 点击 TabView 内置「新增 tab」按钮（带 newTabLabel Tooltip 的图标按钮）
  Future<void> addTabViaButton(WidgetTester tester) async {
    final l10n = FluentLocalizations.of(tester.element(find.byType(TabView)));
    await tester.tap(
        find.byWidgetPredicate((w) => w is Tooltip && w.message == l10n.newTabLabel));
    await tester.pumpAndSettle();
  }

  /// 点击某个 tab 的标题以切换
  Future<void> switchToTab(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  testWidgets('A) 固定首 tab 无关闭 x；新增 tab 有 x，点击只关闭该 tab', (tester) async {
    await pumpPage(tester);
    final id0 = runtimeAt(0).state.id;

    // 默认固定 tab 无关闭入口
    expect(find.byType(Tab), findsOneWidget);
    expect(closeBtn(id0), findsNothing);

    // 新增两个 tab，各自带 x
    await addTabViaButton(tester);
    await addTabViaButton(tester);
    final id1 = runtimeAt(1).state.id;
    final id2 = runtimeAt(2).state.id;
    expect(find.byType(Tab), findsNWidgets(3));
    expect(closeBtn(id1), findsOneWidget);
    expect(closeBtn(id2), findsOneWidget);
    expect(closeBtn(id0), findsNothing);

    // 点击非激活 tab（id1）的 x：只关它，其余保留
    await tester.tap(closeBtn(id1));
    await tester.pumpAndSettle();
    expect(closeBtn(id1), findsNothing);
    expect(appState.tabs.tabs.map((r) => r.state.id), [id0, id2]);
    expect(appState.tabs.activeTab.state.id, id2, reason: '关闭非激活 tab 不得改变激活 tab');
  });

  testWidgets('A) 首 tab.onClosed 为 null；关闭激活 tab 激活右侧，末尾激活左侧', (tester) async {
    await pumpPage(tester);

    expect(tester.widget<Tab>(find.byType(Tab).first).onClosed, isNull,
        reason: '固定首 tab 不可关闭');

    await addTabViaButton(tester);
    await addTabViaButton(tester);
    final id1 = runtimeAt(1).state.id;
    final id2 = runtimeAt(2).state.id;
    expect(tester.widget<Tab>(find.byType(Tab).at(1)).onClosed, isNotNull);
    expect(tester.widget<Tab>(find.byType(Tab).at(2)).onClosed, isNotNull);

    // 末尾激活左侧：active=末尾 id2 → 关闭后激活 id1
    expect(appState.tabs.activeTab.state.id, id2);
    await tester.tap(closeBtn(id2));
    await tester.pumpAndSettle();
    expect(appState.tabs.activeTab.state.id, id1, reason: '末尾 tab 关闭后应激活左侧');

    // 关闭激活 tab 激活右侧：active=id1（中间）→ 关闭后激活原右侧 id3
    await addTabViaButton(tester);
    final id3 = runtimeAt(2).state.id;
    expect(appState.tabs.activeTab.state.id, id3);
    await switchToTab(tester, '会话 1');
    expect(appState.tabs.activeTab.state.id, id1);
    await tester.tap(closeBtn(id1));
    await tester.pumpAndSettle();
    expect(appState.tabs.activeTab.state.id, id3,
        reason: '中间激活 tab 关闭后应激活右侧');
  });

  testWidgets('B) 多 tab 输入独立，切换前后 WorkbenchPanel State 实例保持相同', (tester) async {
    await pumpPage(tester);
    final id0 = runtimeAt(0).state.id;

    Finder panelOf(String id) =>
        find.byKey(ValueKey(id), skipOffstage: false);

    // tab0 输入
    await tester.enterText(
        find.descendant(of: panelOf(id0), matching: find.byType(TextBox)).first,
        '第一段原始输入');
    await tester.pump();
    expect(runtimeAt(0).state.rawText, '第一段原始输入');
    final panel0Before = tester.state<State>(panelOf(id0));

    // 新增 tab1 输入另一段
    await addTabViaButton(tester);
    final id1 = runtimeAt(1).state.id;
    await tester.enterText(
        find.descendant(of: panelOf(id1), matching: find.byType(TextBox)).first,
        '第二段原始输入');
    await tester.pump();
    expect(runtimeAt(1).state.rawText, '第二段原始输入');
    // 输入互相独立
    expect(runtimeAt(0).state.rawText, '第一段原始输入');
    expect(runtimeAt(0).controller.text, '第一段原始输入');
    expect(runtimeAt(1).controller.text, '第二段原始输入');
    final panel1Before = tester.state<State>(panelOf(id1));

    // 切回 tab0：Panel State 实例不变（Tab 缓存 + keepAlive），输入保留
    await switchToTab(tester, '工作台');
    expect(find.text('第一段原始输入'), findsOneWidget);
    final panel0After = tester.state<State>(panelOf(id0));
    expect(identical(panel0Before, panel0After), isTrue,
        reason: '切换 tab 不得重建 WorkbenchPanel State');

    // 再切到 tab1：State 实例同样不变
    await switchToTab(tester, '会话 1');
    final panel1After = tester.state<State>(panelOf(id1));
    expect(identical(panel1Before, panel1After), isTrue,
        reason: '切换 tab 不得重建 WorkbenchPanel State');
    expect(find.text('第二段原始输入'), findsOneWidget);
  });

  testWidgets('B) 后台 tab 的 runtime 切换后继续可用（输入/状态同步不中断）', (tester) async {
    await pumpPage(tester);
    final id0 = runtimeAt(0).state.id;

    Finder panelOf(String id) =>
        find.byKey(ValueKey(id), skipOffstage: false);

    await tester.enterText(
        find.descendant(of: panelOf(id0), matching: find.byType(TextBox)).first,
        '前台输入');
    await tester.pump();
    final panel0Before = tester.state<State>(panelOf(id0));

    await addTabViaButton(tester);
    final id1 = runtimeAt(1).state.id;
    final bg = appState.tabs.tabById(id0)!;
    expect(bg.disposed, isFalse);

    // 后台 tab 的 runtime 仍可写入并同步状态
    bg.controller.text = '后台继续写入';
    await tester.pump();
    expect(bg.disposed, isFalse);
    expect(appState.tabs.tabById(id0)!.state.rawText, '后台继续写入');

    // 回到 tab0：面板 State 未重建且展示后台写入内容
    await switchToTab(tester, '工作台');
    expect(find.text('后台继续写入'), findsOneWidget);
    expect(identical(panel0Before, tester.state<State>(panelOf(id0))), isTrue);
    // tab1 仍在（后台未被误关）
    expect(appState.tabs.tabById(id1), isNotNull);
  });

  testWidgets('C) 11 个 tab 窄窗口：单行标签、可滚动、拖拽/滚轮平移、扩窗后范围更新', (tester) async {
    await pumpPage(tester);
    for (var i = 0; i < 10; i++) {
      appState.tabs.addTab();
    }
    await tester.pumpAndSettle();
    expect(find.byType(Tab), findsNWidgets(11));

    // 缩到窄窗口
    tester.view.physicalSize = const Size(720, 500);
    await tester.pumpAndSettle();

    final tv = tester.widget<TabView>(find.byType(TabView));
    final sc = tv.scrollController!;
    expect(sc.max, greaterThan(0), reason: '11 个 tab 窄窗口下标签条应可横向滚动');

    // 标签单行不换行/不重叠/不压缩
    final listRect = tester.getRect(find.byType(ReorderableListView));
    final visible = <Rect>[];
    for (final r in appState.tabs.tabs) {
      final f = find.text(r.state.title);
      if (f.evaluate().isEmpty) continue;
      final rect = tester.getRect(f);
      if (rect.left < listRect.left - 2 || rect.right > listRect.right + 2) {
        continue; // 已滚出视口的标签不做断言
      }
      expect(rect.height, lessThanOrEqualTo(24),
          reason: '标签标题「${r.state.title}」应单行不换行（高度 ${rect.height}）');
      visible.add(rect);
    }
    expect(visible.length, greaterThanOrEqualTo(3));
    visible.sort((a, b) => a.left.compareTo(b.left));
    for (var i = 1; i < visible.length; i++) {
      expect(visible[i - 1].right, lessThanOrEqualTo(visible[i].left + 0.5),
          reason: '相邻标签不得重叠');
    }
    // 不压缩：标签宽度不小于其标题宽度
    for (final r in appState.tabs.tabs) {
      final f = find.text(r.state.title);
      if (f.evaluate().isEmpty) continue;
      final textRect = tester.getRect(f);
      if (textRect.left < listRect.left - 2 || textRect.right > listRect.right + 2) {
        continue;
      }
      final tabRect = tester.getRect(find.ancestor(of: f, matching: find.byType(Tab)).first);
      expect(tabRect.width, greaterThanOrEqualTo(textRect.width),
          reason: '标签不得压缩到小于标题宽度');
    }

    // 激活首 tab：标签条应自动回滚使激活 tab 可视
    appState.tabs.switchTab(0);
    await tester.pumpAndSettle();
    final startTabRect = tester.getRect(find.text('工作台'));
    expect(startTabRect.left, greaterThanOrEqualTo(listRect.left - 1),
        reason: '切换激活 tab 后应滚动到可视区');
    expect(startTabRect.right, lessThanOrEqualTo(listRect.right + 1));

    // 标签条上鼠标横向拖拽 → offset 变化
    final dragFrom = tester.getCenter(find.text('会话 2'));
    final before = sc.offset;
    final gesture =
        await tester.startGesture(dragFrom, kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(-100, 0));
    await gesture.moveBy(const Offset(-100, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sc.offset, greaterThan(before), reason: '标签条鼠标拖拽应横向平移');

    // 滚轮事件 → offset 变化并可到达末尾
    final listRect2 = tester.getRect(find.byType(ReorderableListView));
    final wheelAt = Offset(listRect2.left + 180, listRect2.center.dy);
    final pointer = TestPointer(88, PointerDeviceKind.mouse);
    final beforeWheel = sc.offset;
    for (var i = 0; i < 40 && !sc.atEnd; i++) {
      pointer.hover(wheelAt);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(sc.offset, greaterThan(beforeWheel), reason: '滚轮应平移标签条');
    expect(sc.atEnd, isTrue, reason: '持续滚轮应可到达末尾');

    // 窄窗口下切换到远处激活 tab：应滚入可视区（scroll_pos 按均宽估算
    // item 偏移，sizeToContent 标签宽不等时以「滚入可视区」为准）
    appState.tabs.switchTab(3);
    await tester.pumpAndSettle();
    final farTabRect = tester.getRect(find.text('会话 3'));
    expect(farTabRect.center.dx, greaterThanOrEqualTo(listRect2.left),
        reason: '激活 tab 应滚动到可视区');
    expect(farTabRect.center.dx, lessThanOrEqualTo(listRect2.right));

    final maxBefore = sc.max;
    // 扩大窗口：滚动范围更新且激活 tab 可见
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(sc.max, lessThan(maxBefore), reason: '扩大窗口后滚动范围应更新');
    appState.tabs.switchTab(appState.tabs.tabs.length - 1);
    await tester.pumpAndSettle();
    final activeRect =
        tester.getRect(find.text(appState.tabs.activeTab.state.title));
    final tvRect = tester.getRect(find.byType(TabView));
    expect(activeRect.left, greaterThanOrEqualTo(tvRect.left - 1),
        reason: '扩大窗口后激活 tab 应可见');
    expect(activeRect.right, lessThanOrEqualTo(tvRect.right + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('C) 鼠标拖拽只走内层 Scrollable：behavior 含 mouse，无外层拖拽兜底', (tester) async {
    await pumpPage(tester);
    for (var i = 0; i < 10; i++) {
      appState.tabs.addTab();
    }
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(720, 500);
    await tester.pumpAndSettle();
    final tv = tester.widget<TabView>(find.byType(TabView));
    final sc = tv.scrollController!;

    // ① 标签条的 ScrollConfiguration behavior.dragDevices 含 mouse
    final mouseConfigs = find.ancestor(
      of: find.byType(ReorderableListView),
      matching: find.byWidgetPredicate((w) =>
          w is ScrollConfiguration &&
          w.behavior.dragDevices.contains(PointerDeviceKind.mouse)),
    );
    expect(mouseConfigs, findsOneWidget,
        reason: '标签条应由自定义 ScrollBehavior 允许鼠标拖拽（dragDevices 含 mouse）');

    // ② 不得再有外层 onHorizontalDragUpdate 兜底（拖拽只归内层 Scrollable；
    //    限定标签条祖先范围，避免命中结果区的分栏拖拽手柄）
    expect(
      find.ancestor(
        of: find.byType(ReorderableListView),
        matching: find.byWidgetPredicate(
            (w) => w is GestureDetector && w.onHorizontalDragUpdate != null),
      ),
      findsNothing,
      reason: '不得存在外层 GestureDetector 拖拽兜底（会吞掉首段位移）',
    );

    // ③ 鼠标在标签条上拖拽 → 内层 Scrollable 平移，位移不被吞
    appState.tabs.switchTab(0);
    await tester.pumpAndSettle();
    final before = sc.offset;
    final gesture = await tester.startGesture(
        tester.getCenter(find.text('会话 2')),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(-100, 0));
    await gesture.moveBy(const Offset(-100, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sc.offset - before, greaterThanOrEqualTo(195),
        reason: '200px 鼠标拖拽不得吞掉首段位移（实际 ${sc.offset - before}）');

    // ④ 拖拽起点在标签列表外（新增按钮处）：无兜底则不应平移
    final l10n = FluentLocalizations.of(tester.element(find.byType(TabView)));
    final newBtn = find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == l10n.newTabLabel);
    final outsideBefore = sc.offset;
    final gesture2 = await tester.startGesture(tester.getCenter(newBtn),
        kind: PointerDeviceKind.mouse);
    await gesture2.moveBy(const Offset(-80, 0));
    await gesture2.moveBy(const Offset(-80, 0));
    await gesture2.up();
    await tester.pumpAndSettle();
    expect(sc.offset, outsideBefore,
        reason: '列表外起点不应平移标签条（无外层拖拽兜底）');
    expect(find.byType(Tab, skipOffstage: false), findsNWidgets(11),
        reason: '拖拽不得误触新增按钮');
  });

  testWidgets('D) 关闭按钮有 Key/Tooltip 与真实可点区域（约 32×27），tapAt 各内侧点位均可关闭', (tester) async {
    await pumpPage(tester);
    await addTabViaButton(tester);
    await addTabViaButton(tester);
    await addTabViaButton(tester);
    final id0 = runtimeAt(0).state.id;
    final id1 = runtimeAt(1).state.id;
    final id2 = runtimeAt(2).state.id;
    final id3 = runtimeAt(3).state.id;
    expect(appState.tabs.activeTab.state.id, id3);

    // Key 与 Tooltip
    final btn = closeBtn(id1);
    expect(btn, findsOneWidget);
    final l10n = FluentLocalizations.of(tester.element(find.byType(TabView)));
    final tip = find.ancestor(of: btn, matching: find.byType(Tooltip));
    expect(tip, findsOneWidget);
    expect(tester.widget<Tooltip>(tip).message, l10n.closeTabLabel);

    // 布局值：宽约 32；高度受 TabView 标签高 34 物理限制约 32×27（≥24 即满足点击区），
    // 断言真实布局值而非虚报的 32×32
    final size = tester.getSize(btn);
    expect(size.width, closeTo(32, 2), reason: '关闭按钮宽约 32（实际 $size）');
    expect(size.height, greaterThanOrEqualTo(24),
        reason: '关闭按钮高度至少 24（实际 $size）');
    expect(size.height, lessThanOrEqualTo(29),
        reason: '高度应为 Tab 物理限制下的自然值约 27~28，不得虚报 32（实际 $size）');

    // 真实命中区可用性：中心及上下内侧 tapAt 均能关闭（证明 hit 不是布局摆设）
    final events = <int>[];
    void listener() => events.add(appState.tabs.activeIndex);
    appState.tabs.addListener(listener);
    addTearDown(() => appState.tabs.removeListener(listener));

    // 中心点位关闭非激活 tab：只关闭，不触发标签切换
    final c1 = tester.getCenter(closeBtn(id1));
    await tester.tapAt(c1);
    await tester.pumpAndSettle();
    expect(events, hasLength(1),
        reason: 'x 点击只应产生关闭通知，不得先触发标签切换（$events）');
    expect(appState.tabs.activeTab.state.id, id3, reason: 'x 点击不得切换标签');
    expect(appState.tabs.tabs.map((r) => r.state.id), [id0, id2, id3]);

    // 上内侧点位
    final r2 = tester.getRect(closeBtn(id2));
    await tester.tapAt(r2.center - Offset(0, r2.height / 2 - 3));
    await tester.pumpAndSettle();
    expect(appState.tabs.tabs.map((r) => r.state.id), [id0, id3]);

    // 下内侧点位（激活 tab：关闭后激活左侧）
    final r3 = tester.getRect(closeBtn(id3));
    await tester.tapAt(r3.center + Offset(0, r3.height / 2 - 3));
    await tester.pumpAndSettle();
    expect(appState.tabs.tabs.map((r) => r.state.id), [id0]);
    expect(appState.tabs.activeTab.state.id, id0,
        reason: '末尾激活 tab 关闭后应激活左侧');

    // 固定 tab 依然没有关闭按钮
    expect(closeBtn(id0), findsNothing);
  });

  testWidgets('E) 标签标题的 Tooltip/语义跟随 runtime.state.title，缓存 Tab 不携带过期 semanticLabel', (tester) async {
    await pumpPage(tester);
    await addTabViaButton(tester);
    final id1 = runtimeAt(1).state.id;
    expect(find.text('会话 1'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == '会话 1'),
      findsOneWidget,
    );

    // 程序化改名（如重命名会话）：Tab 实例被缓存，标题提示须自行跟随
    appState.tabs.updateTab(id1, (s) => s.title = '改名后的会话');
    await tester.pumpAndSettle();

    // 可见标题与 Tooltip 消息均跟随运行时标题
    expect(find.text('改名后的会话'), findsOneWidget);
    expect(find.text('会话 1'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == '改名后的会话'),
      findsOneWidget,
      reason: 'Tooltip 消息必须跟随 runtime.state.title',
    );
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == '会话 1'),
      findsNothing,
      reason: '旧标题 Tooltip 不得过期残留',
    );

    // 缓存的 Tab 不得携带冻结在创建时的 semanticLabel
    final tab = tester.widget<Tab>(find.byType(Tab).at(1));
    expect(tab.semanticLabel, isNot('会话 1'),
        reason: '缓存的 Tab 不得保留旧标题 semanticLabel');
    expect(tab.semanticLabel, anyOf(isNull, '改名后的会话'));

    // 语义标签（Tooltip 提供）同样跟随新标题
    final handle = tester.ensureSemantics();
    try {
      expect(find.bySemanticsLabel(RegExp('改名后的会话')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('会话 1')), findsNothing);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('F) Ctrl+W 关闭激活 tab；中键关闭指向 tab；首 tab 对两者免疫', (tester) async {
    await pumpPage(tester);
    await addTabViaButton(tester);
    await addTabViaButton(tester);
    final id0 = runtimeAt(0).state.id;
    final id1 = runtimeAt(1).state.id;
    final id2 = runtimeAt(2).state.id;
    expect(appState.tabs.activeTab.state.id, id2);

    // Ctrl+W 关闭激活 tab（末尾 → 激活左侧）
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1)); // fluent closeDelay 1s 计时器收尾
    await tester.pumpAndSettle();
    expect(appState.tabs.tabs.map((r) => r.state.id), [id0, id1]);
    expect(appState.tabs.activeTab.state.id, id1);

    // 先激活「工作台」，再中键点击非激活的「会话 1」→ 只关它，激活 tab 不变
    await switchToTab(tester, '工作台');
    expect(appState.tabs.activeTab.state.id, id0);
    await tester.tapAt(tester.getCenter(find.text('会话 1')),
        buttons: kMiddleMouseButton);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(appState.tabs.tabs.map((r) => r.state.id), [id0]);
    expect(appState.tabs.activeTab.state.id, id0,
        reason: '中键关闭非激活 tab 不得改变激活 tab');

    // 首 tab 免疫：中键与 Ctrl+W 均不得关闭它
    await addTabViaButton(tester);
    final id3 = runtimeAt(1).state.id;
    await switchToTab(tester, '工作台');
    expect(appState.tabs.activeTab.state.id, id0);

    await tester.tapAt(tester.getCenter(find.text('工作台')),
        buttons: kMiddleMouseButton);
    await tester.pumpAndSettle();
    expect(appState.tabs.tabs.map((r) => r.state.id), [id0, id3],
        reason: '中键不得关闭首 tab');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(appState.tabs.tabs.map((r) => r.state.id), [id0, id3],
        reason: 'Ctrl+W 不得关闭首 tab');
    expect(appState.tabs.activeTab.state.id, id0);
    expect(closeBtn(id0), findsNothing);
  });
}
