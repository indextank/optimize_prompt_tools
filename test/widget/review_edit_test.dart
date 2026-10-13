/// 复查编辑页 Widget 测试：三栏渲染 / 编辑自动保存 / 撤销重做 / 版本链 / 清单。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/review_edit_page.dart';

import 'dart:convert';

import 'package:prompt_optimizer/services/export_service.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmClient llm;

  setUp(() async {
    llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
    appState.session.outputStyle = OutputStyle.full; // 结构化契约用例
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const ReviewEditPage()));
    await tester.pumpAndSettle();
  }

  Future<void> seedRecord(WidgetTester tester) async {
    await appState.saveService(testService(), apiKey: 'sk');
    appState.session.rawText = '帮我写个爬虫爬豆瓣 Top250';
    appState.session.mode = OptimizeMode.deep;
    appState.session.outputStyle = OutputStyle.full; // 结构化契约用例显式指定完整模式 // 显式深度模式（默认为快速）
    llm.enqueueText(kValidContractJson);
    // runAsync：假客户端流式分片依赖真实事件循环（FakeAsync 的裸 await 不推进定时器）
    await tester.runAsync(() => appState.startOptimize());
  }

  testWidgets('并行对比模式：结果来源切换与编辑落库', (tester) async {
    // 并行种子：默认服务 + 对比服务，两个不同内容的结构化结果
    await appState.saveService(testService(), apiKey: 'sk');
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2');
    await appState.settings
        .update(appState.settings.settings.copyWith(parallelEnabled: true));
    appState.session.parallelServiceId = 'svc-2';
    appState.session.rawText = '帮我写个爬虫爬豆瓣 Top250';
    appState.session.mode = OptimizeMode.deep;
    llm.enqueueText(kValidContractJson); // 主（deepseek）
    llm.enqueueText(kValidContractJson.replaceAll('资深 Python 工程师', 'Kimi 爬虫专家'));
    await tester.runAsync(() => appState.startOptimize());
    expect(appState.session.parallelStates, hasLength(2));

    await pumpPage(tester);
    await tester.pump();
    // 来源下拉存在，默认显示主结果内容
    final srcCombo = find.byType(ComboBox<String>);
    expect(srcCombo, findsWidgets);
    expect(find.text('资深 Python 工程师'), findsOneWidget);
    // 切换到 kimi → 编辑器内容更换
    await tester.tap(srcCombo.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('k3').last);
    await tester.pumpAndSettle();
    expect(find.text('Kimi 爬虫专家'), findsOneWidget);
    expect(find.text('资深 Python 工程师'), findsNothing);
    // 编辑 kimi 结果 → 自动保存生成新版本（采纳该模型结果）
    await tester.enterText(find.byType(TextBox).at(0), '采纳并修订后的 Kimi 角色');
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(appState.session.currentRecord!.versions.length, 2);
    expect(appState.session.currentRecord!.latest.result.role, '采纳并修订后的 Kimi 角色');
    // 切回主结果：显示当前记录内容（即刚保存的修订版）
    await tester.tap(srcCombo.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('deepseek-flash').last);
    await tester.pumpAndSettle();
    expect(find.text('采纳并修订后的 Kimi 角色'), findsOneWidget,
        reason: '编辑落库后记录主结果即修订内容');
    expect(tester.takeException(), isNull);
  });

  testWidgets('无记录时显示引导空态', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('暂无待复查的优化结果'), findsOneWidget);
  });

  testWidgets('三栏渲染：原文 / 编辑器 / 复查清单', (tester) async {
    await seedRecord(tester);
    await pumpPage(tester);
    await tester.pump(); // post-frame 同步
    expect(find.text('原始提示词'), findsOneWidget);
    expect(find.text('优化结果（可编辑）'), findsOneWidget);
    expect(find.text('复查清单'), findsOneWidget);
    expect(find.text('帮我写个爬虫爬豆瓣 Top250'), findsOneWidget);
    expect(find.text('62'), findsOneWidget); // 评分对比
    expect(find.text('92'), findsOneWidget);
    expect(find.textContaining('1 项诊断'), findsOneWidget);
    expect(find.text('版本 v1（当前）'), findsOneWidget);
  });

  testWidgets('编辑段落触发自动保存生成新版本', (tester) async {
    await seedRecord(tester);
    await pumpPage(tester);
    await tester.pump();
    // 第一个 TextBox 是「角色定位」
    await tester.enterText(find.byType(TextBox).at(0), '改后的角色定位文本');
    await tester.pump(const Duration(milliseconds: 1000)); // 越过 800ms 自动保存
    await tester.pumpAndSettle();
    expect(appState.session.currentRecord!.versions.length, 2);
    expect(appState.session.currentRecord!.latest.result.role, '改后的角色定位文本');
    expect(find.textContaining('版本 v2'), findsOneWidget);
  });

  testWidgets('撤销/重做按钮状态与行为', (tester) async {
    await seedRecord(tester);
    await pumpPage(tester);
    await tester.pump();
    // 初始无撤销可用
    final undoBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, FluentIcons.undo));
    expect(undoBtn.onPressed, isNull);

    await tester.enterText(find.byType(TextBox).at(0), '第一次修改');
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();

    final undo2 = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, FluentIcons.undo));
    expect(undo2.onPressed, isNotNull);
    await tester.tap(find.widgetWithIcon(IconButton, FluentIcons.undo));
    await tester.pumpAndSettle();
    // 撤销后回到原内容（追加式版本链，latest 是撤销产生的新版本）
    expect(appState.session.currentRecord!.latest.result.role, '资深 Python 工程师');
  });

  testWidgets('「保存并一键复制」按钮已移除', (tester) async {
    await seedRecord(tester);
    await pumpPage(tester);
    await tester.pump();
    expect(find.text('✓ 保存并一键复制'), findsNothing);
    expect(find.text('导出 Markdown'), findsOneWidget);
    expect(find.text('返回工作台'), findsWidgets);
  });

  testWidgets('导出 Markdown 仅含优化结果正文（无标题/元信息/原始输入）', (tester) async {
    final saver = FakeFileSaver();
    ReviewEditPage.debugExporter = ExportService(fileSaver: saver);
    addTearDown(() => ReviewEditPage.debugExporter = null);
    await seedRecord(tester);
    await pumpPage(tester);
    await tester.pump();
    await tester.tap(find.text('导出 Markdown'));
    await tester.pumpAndSettle();
    expect(saver.lastExt, 'md');
    final content = utf8.decode(saver.lastBytes!);
    expect(content, contains('【任务目标】'), reason: '应含结果正文');
    expect(content, isNot(contains('# 优化提示词')), reason: '不得含导出标题');
    expect(content, isNot(contains('场景：')), reason: '不得含元信息描述');
    expect(content, isNot(contains('质量评分')), reason: '不得含评分元信息');
    expect(content, isNot(contains('帮我写个爬虫爬豆瓣 Top250')), reason: '不得含原始输入');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('返回工作台时未落盘的变更自动保存', (tester) async {
    await seedRecord(tester);
    await pumpPage(tester);
    await tester.pump();
    // 编辑角色段（触发 800ms 防抖前立刻返回）
    await tester.enterText(find.byType(TextBox).at(0), '返回前刚改的角色文本');
    await tester.pump(); // 仅一帧，远未到 800ms 防抖
    expect(appState.session.currentRecord!.versions.length, 1);
    await tester.tap(find.text('返回工作台').last);
    await tester.pumpAndSettle();
    expect(appState.session.currentRecord!.versions.length, 2,
        reason: '返回工作台应自动保存未落盘变更为新版本');
    expect(appState.session.currentRecord!.latest.result.role, '返回前刚改的角色文本');
  });

  testWidgets('列表段落添加与删除条目', (tester) async {
    await seedRecord(tester);
    await pumpPage(tester);
    await tester.pump();
    final before = appState.session.currentRecord!.latest.result.requirements.length;
    expect(before, 2);
    // 点击「＋ 添加条目」（具体要求段是第一个列表段）
    await tester.tap(find.text('＋ 添加条目').first);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(appState.session.currentRecord!.latest.result.requirements.length, 2); // 空条目被清理
  });

  testWidgets('AI 重写此段', (tester) async {
    await seedRecord(tester);
    await pumpPage(tester);
    await tester.pump();
    // 点击角色定位段落进入编辑态（第一个为编辑器段落标签，另一个在复查清单）
    await tester.tap(find.text('角色定位').first);
    await tester.pumpAndSettle();
    llm.enqueueText('AI 重写后的角色');
    await tester.tap(find.text('让 AI 重写此段'));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(appState.session.currentRecord!.latest.result.role, 'AI 重写后的角色');
  });
}
