/// 工作台页 Widget 测试：渲染 / 输入校验联动 / 优化流程 / 复制。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/workbench_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmClient llm;
  String? clipboardText;

  setUp(() async {
    llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
    appState.session.outputStyle = OutputStyle.full; // 结构化契约用例默认完整模式
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = call.arguments['text'] as String?;
      }
      if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': ''};
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const WorkbenchPage()));
    await tester.pumpAndSettle();
  }

  Future<void> addDefaultService() async {
    await appState.saveService(testService(), apiKey: 'sk-test');
  }

  testWidgets('初始渲染：标题/卡片/模式/空状态', (tester) async {
    await pumpPage(tester);
    expect(find.text('优化工作台'), findsOneWidget);
    expect(find.text('原始提示词'), findsOneWidget);
    expect(find.text('优化结果'), findsOneWidget);
    expect(find.text('快速优化'), findsWidgets);
    expect(find.text('深度优化'), findsWidgets);
    expect(find.text('提问式优化'), findsWidgets);
    expect(find.textContaining('优化结果将在这里展示'), findsOneWidget);
    // 未配置服务：并行开关锁定并显示原因提示（会话模型下拉已移除）
    expect(find.text('配置 ≥2 个 AI 服务后可开启并行对比'), findsOneWidget);
  });

  testWidgets('空输入时开始优化按钮禁用，输入后启用', (tester) async {
    await pumpPage(tester);
    await addDefaultService();
    await tester.pump();

    FilledButton startBtn() => tester.widget(find.widgetWithText(FilledButton, '✨ 开始优化'));
    expect(startBtn().onPressed, isNull);

    await tester.enterText(find.byType(TextBox).first, '帮我写个爬虫');
    await tester.pump();
    expect(startBtn().onPressed, isNotNull);
  });

  testWidgets('深度优化全流程：流式→六段结果→评分徽章→复制', (tester) async {
    await pumpPage(tester);
    await addDefaultService();
    appState.session.mode = OptimizeMode.deep;
    appState.session.outputStyle = OutputStyle.full; // 结构化契约用例显式指定完整模式 // 显式深度模式（默认为快速）
    await tester.enterText(find.byType(TextBox).first, '帮我写个爬虫爬豆瓣');
    await tester.pump();

    llm.enqueueText(kValidContractJson);
    await tester.tap(find.widgetWithText(FilledButton, '✨ 开始优化'));
    await tester.pumpAndSettle();

    // 六段标签
    expect(find.text('角色定位'), findsOneWidget);
    expect(find.text('任务目标'), findsOneWidget);
    expect(find.text('验收标准'), findsOneWidget);
    // 内容
    expect(find.text('资深 Python 工程师'), findsOneWidget);
    // 评分徽章
    expect(find.text('质量评分 62 → 92'), findsOneWidget);
    // 版本与模式
    expect(find.textContaining('深度优化'), findsWidgets);

    // 一键复制
    await tester.tap(find.widgetWithText(FilledButton, '📄 一键复制'));
    await tester.pumpAndSettle();
    expect(clipboardText, contains('【角色定位】'));
    expect(clipboardText, contains('资深 Python 工程师'));
    // 排空 InfoBar 自动关闭 Timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('优化模式分段切换与场景选择', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('快速优化').first);
    await tester.pump();
    expect(appState.session.mode, OptimizeMode.quick);

    await tester.tap(find.text('文案写作'));
    await tester.pump();
    expect(appState.session.sceneId, 'writing');
  });

  testWidgets('提问式优化：问题面板渲染与提交', (tester) async {
    await addDefaultService();
    await pumpPage(tester);
    appState.session.mode = OptimizeMode.ask; // 模式切换由专项测试覆盖
    await tester.enterText(find.byType(EditableText).first, '帮我写个爬虫');
    await tester.pump();

    llm.enqueueText(kValidQuestionsJson);
    await tester.tap(find.widgetWithText(FilledButton, '✨ 开始优化'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Q1'), findsOneWidget);
    expect(find.textContaining('目标站点有反爬吗？'), findsOneWidget);
    expect(find.text('✨ 生成优化提示词'), findsOneWidget);

    // 回答第一题后生成终稿（定位提问列表内第一个可编辑框）
    llm.enqueueText(kValidContractJson);
    await tester.enterText(
        find
            .descendant(
                of: find.byType(ListView),
                matching: find.byType(EditableText))
            .first,
        '有反爬');
    await tester.tap(find.widgetWithText(FilledButton, '✨ 生成优化提示词'));
    await tester.pumpAndSettle();
    expect(find.text('资深 Python 工程师'), findsOneWidget);
  });

  testWidgets('错误提示展示', (tester) async {
    await pumpPage(tester);
    await addDefaultService();
    await tester.enterText(find.byType(TextBox).first, '原文');
    await tester.pump();
    llm.enqueueError(Exception('boom'));
    await tester.tap(find.widgetWithText(FilledButton, '✨ 开始优化'));
    await tester.pumpAndSettle();
    expect(appState.session.errorMessage, isNotNull);
    // 排空 InfoBar 自动关闭 Timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
