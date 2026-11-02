/// WorkbenchPanel 数据源隔离验收测试（多 tab 重构任务 4）：
/// - Panel 只读写构造传入的 runtime.state（tab），不触碰 appState.session（active tab）
/// - 输入控制器来自 runtime，panel 卸载后不释放它（只释放自身 ScrollController）
/// - 并行开关/对比模型写 tab.parallelEnabled/tab.parallelServiceId，不更新全局 settings
/// - 清空走 clearWorkbenchTab；提问终轮按钮受 tab.optimizing 限制
/// - 结果区按 tab.status 渲染：empty/loading/streaming/error（含旧记录中断标注 + 重试）
library;

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/parallel_scheduler.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/state/workbench_tabs.dart';
import 'package:prompt_optimizer/ui/pages/workbench_panel.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

OptimizeRecord _record(String rawText) => OptimizeRecord(
      id: 'old-record',
      scene: kDefaultScene.id,
      mode: OptimizeMode.deep,
      rawText: 'raw',
      versions: [
        OptimizeVersion(v: 1, result: OptimizeResult.unstructured(rawText)),
      ],
      providers: const ['svc-1'],
      createdAt: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmClient llm;

  setUp(() async {
    llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
    await appState.saveService(testService(), apiKey: 'sk');
  });

  Future<void> pumpPanel(WidgetTester tester, WorkbenchTabRuntime runtime,
      {Size size = const Size(1440, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(WorkbenchPanel(runtime: runtime)));
    await tester.pumpAndSettle();
  }

  /// 新建一个 tab 后切回固定工作台，使目标 tab 处于非激活态（与 active tab 隔离）
  WorkbenchTabRuntime createBackgroundTab() {
    final runtime = appState.tabs.addTab();
    appState.tabs.switchTab(0);
    return runtime;
  }

  testWidgets('Panel 渲染构造 runtime 的 tab 数据，而非 active tab', (tester) async {
    final bg = createBackgroundTab();
    final active = appState.tabs.activeTab;
    appState.tabs.updateTab(bg.state.id, (s) => s.rawText = '后台 tab 的输入');
    appState.tabs.updateTab(active.state.id, (s) => s.rawText = '激活 tab 的输入');

    await pumpPanel(tester, bg);

    expect(find.text('后台 tab 的输入'), findsOneWidget);
    expect(find.text('激活 tab 的输入'), findsNothing);
    expect(find.text('${'后台 tab 的输入'.trim().length} 字'), findsOneWidget);
  });

  testWidgets('输入/模式/场景写入 runtime 的 tab，不影响 active tab', (tester) async {
    final bg = createBackgroundTab();
    final active = appState.tabs.activeTab;
    await pumpPanel(tester, bg);

    await tester.enterText(find.byType(TextBox).first, 'panel 输入');
    await tester.pump();
    expect(bg.state.rawText, 'panel 输入');
    expect(bg.controller.text, 'panel 输入');
    expect(active.state.rawText, isEmpty);

    await tester.tap(find.text('深度优化'));
    await tester.pump();
    expect(bg.state.mode, OptimizeMode.deep);
    expect(active.state.mode, OptimizeMode.quick);

    await tester.tap(find.text('文案写作'));
    await tester.pump();
    expect(bg.state.sceneId, 'writing');
    expect(active.state.sceneId, 'ai_coding');
  });

  testWidgets('并行开关只写 tab.parallelEnabled/parallelServiceId，不更新全局设置', (tester) async {
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2');
    final bg = createBackgroundTab();
    await pumpPanel(tester, bg);

    await tester.tap(find.text('并行对比'));
    await tester.pumpAndSettle();
    expect(bg.state.parallelEnabled, isTrue);
    expect(bg.state.parallelServiceId, 'svc-2', reason: '开启后默认选中第一个候选');
    expect(appState.tabs.activeTab.state.parallelEnabled, isFalse,
        reason: 'active tab 不得被误写');
    expect(appState.settings.settings.parallelEnabled, isFalse,
        reason: '开关只写 tab 状态，不再更新全局 settings');

    // 优化中仅禁用该 tab 的并行开关/下拉
    appState.tabs.updateTab(bg.state.id, (s) {
      s.status = OptimizationRunStatus.loading;
    });
    await tester.pump();
    final toggle = tester.widget<ToggleSwitch>(
        find.widgetWithText(ToggleSwitch, '并行对比'));
    expect(toggle.onChanged, isNull);
    final combo = tester.widget<ComboBox<String>>(
        find.widgetWithText(ComboBox<String>, 'k3'));
    expect(combo.onChanged, isNull);
  });

  testWidgets('清空走 clearWorkbenchTab：清空输入与运行数据，不影响其他 tab', (tester) async {
    final bg = createBackgroundTab();
    final active = appState.tabs.activeTab;
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '待清空';
      s.currentRecord = _record('上次的旧结果');
      s.status = OptimizationRunStatus.error;
      s.errorMessage = '请求已取消';
    });
    appState.tabs.updateTab(active.state.id, (s) => s.rawText = '保留');
    await pumpPanel(tester, bg);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(bg.state.rawText, isEmpty);
    expect(bg.controller.text, isEmpty);
    expect(bg.state.currentRecord, isNull);
    expect(bg.state.errorMessage, isNull);
    expect(bg.state.status, OptimizationRunStatus.empty);
    expect(active.state.rawText, '保留');
  });

  testWidgets('error 态显示 errorMessage + 重试按钮', (tester) async {
    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '会失败的输入';
      s.status = OptimizationRunStatus.error;
      s.errorMessage = '请求已取消';
    });
    await pumpPanel(tester, bg);

    expect(find.textContaining('请求已取消'), findsOneWidget);
    expect(find.widgetWithText(Button, '重试'), findsOneWidget);
  });

  testWidgets('error 态有旧记录时保留旧结果并标注中断，重试只作用于该 tab', (tester) async {
    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '会失败的输入';
      s.currentRecord = _record('上次的旧结果');
      s.status = OptimizationRunStatus.error;
      s.errorMessage = '请求超时';
    });
    await pumpPanel(tester, bg);

    expect(find.textContaining('已中断'), findsOneWidget);
    expect(find.textContaining('请求超时'), findsOneWidget);
    expect(find.text('上次的旧结果'), findsWidgets, reason: '旧结果应保留展示');
    expect(find.widgetWithText(Button, '重试'), findsOneWidget);

    llm.enqueueText('重试产出的内容');
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(bg.state.status, OptimizationRunStatus.success);
    expect(bg.state.currentRecord, isNotNull);
    expect(find.textContaining('重试产出的内容'), findsOneWidget);
    expect(appState.tabs.activeTab.state.currentRecord, isNull,
        reason: '重试不得写入 active tab');
    // 排空 InfoBar 自动关闭 Timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('panel 不释放 runtime 的输入控制器，仅释放自身滚动控制器', (tester) async {
    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) => s.rawText = '初始');
    await pumpPanel(tester, bg);
    await tester.enterText(find.byType(TextBox).first, '改动');
    await tester.pump();
    expect(bg.state.rawText, '改动');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(find.byType(WorkbenchPanel), findsNothing);

    expect(() => bg.controller.text = '卸载后仍可用', returnsNormally);
    expect(bg.state.rawText, '卸载后仍可用', reason: '控制器监听仍归 runtime 管理');
  });

  testWidgets('提问终轮受 optimizing 限制，答案写入 runtime 的 tab', (tester) async {
    final bg = createBackgroundTab();
    final active = appState.tabs.activeTab;
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '提问输入';
      s.mode = OptimizeMode.ask;
      s.askAnswering = true;
      s.questions = const [ClarifyQuestion(question: '目标？', decides: '范围')];
      s.answers = [null];
      s.status = OptimizationRunStatus.empty;
    });
    await pumpPanel(tester, bg);

    await tester.enterText(
        find
            .descendant(
                of: find.byType(ListView), matching: find.byType(EditableText))
            .first,
        '我的回答');
    await tester.pump();
    expect(bg.state.answers, ['我的回答']);
    expect(active.state.answers, isEmpty);

    final enabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '✨ 生成优化提示词'));
    expect(enabled.onPressed, isNotNull);

    appState.tabs.updateTab(bg.state.id, (s) {
      s.status = OptimizationRunStatus.loading;
    });
    await tester.pump();
    final disabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '✨ 生成优化提示词'));
    expect(disabled.onPressed, isNull, reason: '提问终轮也不得重复提交');
  });

  testWidgets('结果区按 tab.status 渲染：empty/loading/streaming', (tester) async {
    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) {
      s.status = OptimizationRunStatus.empty;
    });
    await pumpPanel(tester, bg);
    expect(find.textContaining('优化结果将在这里展示'), findsOneWidget);

    appState.tabs.updateTab(bg.state.id, (s) {
      s.status = OptimizationRunStatus.loading;
    });
    await tester.pump();
    expect(find.textContaining('正在请求模型'), findsOneWidget);

    appState.tabs.updateTab(bg.state.id, (s) {
      s.status = OptimizationRunStatus.streaming;
      s.streaming['svc-1'] = '已经收到的流式内容';
    });
    await tester.pump();
    expect(find.textContaining('已经收到的流式内容'), findsOneWidget);
  });

  testWidgets('并行运行 error：展示整体错误与重试，列标注已中断并保留流文本', (tester) async {
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2');
    final bg = createBackgroundTab();
    final st1 = ParallelRunState(service: testService(), apiKey: 'sk')
      ..streamedText = '主模型已收半段';
    final st2 = ParallelRunState(
        service: testService(
            id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2')
      ..streamedText = '对比模型已收半段';
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '原文';
      s.parallelEnabled = true;
      s.parallelServiceId = 'svc-2';
      s.parallelStates = {'svc-1': st1, 'svc-2': st2};
      s.status = OptimizationRunStatus.error;
      s.errorMessage = '请求已取消，已保留接收内容';
    });
    await pumpPanel(tester, bg);

    // 整体错误 + 重试入口（不只列内错误）
    expect(find.textContaining('请求已取消，已保留接收内容'), findsOneWidget);
    expect(find.widgetWithText(Button, '重试'), findsOneWidget);
    // 取消/中断的列不得停留在 ProgressRing/「请求中…」
    expect(find.byType(ProgressRing), findsNothing);
    expect(find.textContaining('请求中'), findsNothing);
    // 列明确标注已中断并保留部分流文本
    expect(find.text('⚠ 已中断'), findsNWidgets(2));
    expect(find.textContaining('主模型已收半段'), findsOneWidget);
    expect(find.textContaining('对比模型已收半段'), findsOneWidget);
  });

  testWidgets('并行全部失败：整体错误与重试仍展示（不只列内错误）', (tester) async {
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2');
    final bg = createBackgroundTab();
    final st1 = ParallelRunState(service: testService(), apiKey: 'sk');
    st1.done = true;
    st1.error = Exception('boom-1');
    final st2 = ParallelRunState(
        service: testService(
            id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2');
    st2.done = true;
    st2.error = Exception('boom-2');
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '原文';
      s.parallelEnabled = true;
      s.parallelServiceId = 'svc-2';
      s.parallelStates = {'svc-1': st1, 'svc-2': st2};
      s.status = OptimizationRunStatus.error;
      s.errorMessage = '两路均失败';
    });
    await pumpPanel(tester, bg);

    expect(find.textContaining('两路均失败'), findsOneWidget,
        reason: '已全部失败必须展示整体错误，不只列内错误');
    expect(find.widgetWithText(Button, '重试'), findsOneWidget);
    // 列内错误保留
    expect(find.textContaining('boom-1'), findsOneWidget);
    expect(find.textContaining('boom-2'), findsOneWidget);
    expect(find.textContaining('异常：'), findsNWidgets(2),
        reason: '非 LlmException 异常文案以「异常：」标注，不裸插值');
  });

  testWidgets('error 且有旧 record + partial：已接收内容与旧结果同时保留并标注中断', (tester) async {
    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '会失败的输入';
      s.currentRecord = _record('上次的旧结果');
      s.status = OptimizationRunStatus.error;
      s.errorMessage = '请求已取消，已保留接收内容';
      s.streaming['svc-1'] = '已接收的半段内容';
    });
    await pumpPanel(tester, bg);

    expect(find.textContaining('已中断'), findsOneWidget,
        reason: '请求取消/中断必须明确标注');
    expect(find.textContaining('已接收的半段内容'), findsOneWidget,
        reason: '不得丢弃 partial');
    expect(find.text('上次的旧结果'), findsWidgets, reason: '旧 record 必须同时展示');
    expect(find.widgetWithText(Button, '重试'), findsOneWidget);
  });

  testWidgets('并行 error 且有旧 record：列内已接收内容与旧结果同时保留', (tester) async {
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2');
    final bg = createBackgroundTab();
    final st1 = ParallelRunState(service: testService(), apiKey: 'sk')
      ..streamedText = '列一已收半段';
    final st2 = ParallelRunState(
        service: testService(
            id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2')
      ..streamedText = '列二已收半段';
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '原文';
      s.parallelEnabled = true;
      s.parallelServiceId = 'svc-2';
      s.parallelStates = {'svc-1': st1, 'svc-2': st2};
      s.status = OptimizationRunStatus.error;
      s.errorMessage = '请求已取消，已保留接收内容';
      s.currentRecord = _record('上次的旧结果');
    });
    await pumpPanel(tester, bg);

    expect(find.textContaining('列一已收半段'), findsOneWidget, reason: '不得丢弃 partial');
    expect(find.textContaining('列二已收半段'), findsOneWidget);
    expect(find.text('上次的旧结果'), findsWidgets, reason: '旧 record 必须同时展示');
    expect(find.widgetWithText(Button, '重试'), findsOneWidget);
  });

  testWidgets('_AskItem 从 tab.answers 回填文本与跳过态（null=跳过），重建后值保留', (tester) async {
    final bg = createBackgroundTab();
    final active = appState.tabs.activeTab;
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '提问输入';
      s.mode = OptimizeMode.ask;
      s.askAnswering = true;
      s.questions = const [
        ClarifyQuestion(question: '目标？', decides: '范围'),
        ClarifyQuestion(question: '环境？', decides: '依赖'),
      ];
      s.answers = ['已回答', null]; // null = 跳过
    });
    await pumpPanel(tester, bg);

    // 初始化回填：文本 + 跳过态
    expect(find.text('已回答'), findsOneWidget);
    final skips = find.widgetWithText(ToggleSwitch, '跳过');
    expect(skips, findsNWidgets(2));
    expect(tester.widget<ToggleSwitch>(skips.at(0)).checked, isFalse);
    expect(tester.widget<ToggleSwitch>(skips.at(1)).checked, isTrue,
        reason: '答案 null 即跳过态');

    // 后续修改仍写本 tab
    await tester.enterText(
        find
            .descendant(
                of: find.byType(ListView), matching: find.byType(EditableText))
            .first,
        '改过的回答');
    await tester.pump();
    expect(bg.state.answers, ['改过的回答', null]);
    expect(active.state.answers, isEmpty);

    // 重建（新 State 实例）后文本与跳过态保留
    await tester.pumpWidget(wrapWithFluentApp(
        WorkbenchPanel(key: const Key('rebuilt'), runtime: bg)));
    await tester.pumpAndSettle();
    expect(find.text('改过的回答'), findsOneWidget);
    final rebuiltSkips = find.widgetWithText(ToggleSwitch, '跳过');
    expect(rebuiltSkips, findsNWidgets(2));
    expect(tester.widget<ToggleSwitch>(rebuiltSkips.at(0)).checked, isFalse);
    expect(tester.widget<ToggleSwitch>(rebuiltSkips.at(1)).checked, isTrue);
  });

  testWidgets('WorkbenchPanel State 保持 keep-alive（wantKeepAlive=true）', (tester) async {
    final bg = createBackgroundTab();
    await pumpPanel(tester, bg);
    final state = tester
        .state<AutomaticKeepAliveClientMixin<WorkbenchPanel>>(
            find.byType(WorkbenchPanel));
    // ignore: invalid_use_of_protected_member
    expect(state.wantKeepAlive, isTrue);
  });

  testWidgets('粘贴：Clipboard.getData 期间 runtime 被释放后不写控制器、不崩溃', (tester) async {
    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) => s.rawText = '原文');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        bg.dispose(); // 模拟 await 期间 tab 被关闭、资源被释放
        return <String, dynamic>{'text': '粘贴进来的内容'};
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpPanel(tester, bg);
    await tester.tap(find.text('📋 粘贴'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(bg.disposed, isTrue);
    expect(bg.state.rawText, '原文', reason: 'runtime 已释放不得回写控制器');
  });

  testWidgets('卸载后 _onOptimize 的 autoCopy/Clipboard.setData 回归不得 setState', (tester) async {
    await appState.settings
        .update(appState.settings.settings.copyWith(autoCopy: true));
    final copyGate = Completer<void>();
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
        await copyGate.future; // 显式放行：制造可控挂起空隙
      }
      return null;
    });
    addTearDown(() {
      if (!copyGate.isCompleted) copyGate.complete();
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '原文';
      s.outputStyle = OutputStyle.simple;
    });
    await pumpPanel(tester, bg);
    llm.enqueueText('一段结果内容');

    await tester.tap(find.widgetWithText(FilledButton, '✨ 开始优化'));
    for (var i = 0; i < 20 && copied == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(copied, isNotNull, reason: '应已进入 Clipboard.setData 挂起空隙');

    bg.dispose(); // 运行资源一并释放
    await tester.pumpWidget(const SizedBox()); // 卸载 panel
    copyGate.complete();
    await tester.pump();
    await tester.pumpAndSettle(); // 排空点击残留定时器
    expect(tester.takeException(), isNull, reason: '卸载后不得再 setState');
  });

  testWidgets('提问终轮 handler：卸载后 autoCopy/Clipboard.setData 回归不得 setState', (tester) async {
    await appState.settings
        .update(appState.settings.settings.copyWith(autoCopy: true));
    final copyGate = Completer<void>();
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
        await copyGate.future;
      }
      return null;
    });
    addTearDown(() {
      if (!copyGate.isCompleted) copyGate.complete();
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '提问输入';
      s.mode = OptimizeMode.ask;
      s.askAnswering = true;
      s.questions = const [ClarifyQuestion(question: '目标？', decides: '范围')];
      s.answers = ['答'];
      s.status = OptimizationRunStatus.empty;
    });
    await pumpPanel(tester, bg);
    llm.enqueueText(kValidContractJson);

    await tester.tap(find.widgetWithText(FilledButton, '✨ 生成优化提示词'));
    for (var i = 0; i < 20 && copied == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(copied, isNotNull, reason: '应已进入 Clipboard.setData 挂起空隙');

    bg.dispose();
    await tester.pumpWidget(const SizedBox());
    copyGate.complete();
    await tester.pump();
    await tester.pumpAndSettle(); // 排空点击残留定时器
    expect(tester.takeException(), isNull, reason: '卸载后不得再 setState');
  });

  testWidgets('提问式 finalize 失败：errorMessage 可见且「✨ 生成优化提示词」可重试', (tester) async {
    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '提问输入';
      s.mode = OptimizeMode.ask;
      s.askAnswering = true;
      s.questions = const [ClarifyQuestion(question: '目标？', decides: '范围')];
      s.answers = ['答'];
      s.status = OptimizationRunStatus.error;
      s.errorMessage = '生成失败：服务不可用';
    });
    await pumpPanel(tester, bg);

    expect(find.textContaining('生成失败：服务不可用'), findsOneWidget,
        reason: '提问面板不得让错误不可见');
    final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '✨ 生成优化提示词'));
    expect(btn.onPressed, isNotNull, reason: '按钮即 finalize，必须可重试');
  });

  testWidgets('提问终轮进行中：提问面板显示请求中/流式 partial', (tester) async {
    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '提问输入';
      s.mode = OptimizeMode.ask;
      s.askAnswering = true;
      s.questions = const [ClarifyQuestion(question: '目标？', decides: '范围')];
      s.answers = ['答'];
      s.status = OptimizationRunStatus.loading;
    });
    // optimizing 态含 ProgressRing 无限动画，手动 pump 代替 pumpAndSettle
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(WorkbenchPanel(runtime: bg)));
    await tester.pump();
    expect(find.textContaining('正在请求模型'), findsOneWidget);

    appState.tabs.updateTab(bg.state.id, (s) {
      s.status = OptimizationRunStatus.streaming;
      s.streaming['svc-1'] = '终稿片段';
    });
    await tester.pump();
    expect(find.textContaining('终稿片段'), findsOneWidget);
  });

  testWidgets('提问面板长流式 partial / 长 error 横幅不溢出（限高可滚动）', (tester) async {
    final bg = createBackgroundTab();
    final long = List.filled(80, '很长的流式终稿内容很长的流式终稿内容').join('\n');
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '提问输入';
      s.mode = OptimizeMode.ask;
      s.askAnswering = true;
      s.questions = const [ClarifyQuestion(question: '目标？', decides: '范围')];
      s.answers = ['答'];
      s.status = OptimizationRunStatus.streaming;
      s.streaming['svc-1'] = long;
    });
    // optimizing 态含 ProgressRing 无限动画，手动 pump 代替 pumpAndSettle
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(WorkbenchPanel(runtime: bg)));
    await tester.pump();
    expect(find.textContaining('很长的流式终稿内容'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '长流式 partial 不得溢出提问面板');

    // 长 error 横幅同处同样不得溢出
    appState.tabs.updateTab(bg.state.id, (s) {
      s.status = OptimizationRunStatus.error;
      s.errorMessage = List.filled(80, '错误详情很长错误详情很长').join('\n');
    });
    await tester.pump();
    expect(find.textContaining('错误详情很长'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '长 error 横幅不得溢出');
  });

  testWidgets('窄栏/拖拽极限（720-1000px）：底行无 RenderFlex 溢出', (tester) async {
    final bg = createBackgroundTab();
    appState.tabs.updateTab(bg.state.id, (s) {
      s.rawText = '原文';
      s.currentRecord = _record('结果内容');
      s.status = OptimizationRunStatus.success;
    });
    for (final (w, h) in [(720.0, 900.0), (860.0, 900.0), (1000.0, 900.0)]) {
      await pumpPanel(tester, bg, size: Size(w, h));
      final handle = find.byKey(const Key('split-handle'));
      await tester.drag(handle, const Offset(3000, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: '拖到右极限（结果卡最窄）不得溢出 @${w}px');
      await tester.drag(handle, const Offset(-6000, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: '拖到左极限（输入卡最窄）不得溢出 @${w}px');
    }
  });
}
