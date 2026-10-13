/// 全应用集成测试：真实启动 App，走完
/// 「添加服务(含自动拉模型/测试连接) → 工作台优化 → 一键复制 → 历史记录」全链路。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/app.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/add_service_dialog.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('全链路：配置服务 → 深度优化 → 复制 → 历史 → 设置页', (tester) async {
    final llm = FakeLlmClient();
    llm.listModelsResult = ['deepseek-flash', 'deepseek-v4-pro'];
    appState = await makeTestAppState(llm: llm);
    appState.session.outputStyle = OutputStyle.full; // 全链路验证六段式契约

    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = call.arguments['text'] as String?;
      }
      if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': ''};
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // ---------- 启动 ----------
    await tester.pumpWidget(const PromptOptimizerApp());
    await tester.pumpAndSettle();
    expect(find.text('优化工作台'), findsWidgets);

    // ---------- 进入模型配置 ----------
    await tester.tap(find.text('AI 模型配置').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('已配置的AI服务'), findsOneWidget);

    // ---------- 添加服务 ----------
    await tester.tap(find.text('＋ 添加AI服务'));
    await tester.pumpAndSettle();
    expect(find.text('添加AI服务'), findsOneWidget);

    // 选服务商 DeepSeek（ComboBox 限定在弹窗内，页面上的默认服务下拉同名）
    final dialogCombo = find
        .descendant(
            of: find.byType(AddServiceDialog),
            matching: find.byType(ComboBox<String>))
        .first;
    await tester.tap(dialogCombo);
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();

    // 输入 KEY（停顿后自动拉模型）
    await tester.enterText(find.byType(PasswordBox), 'sk-integration');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.textContaining('获取成功，共 2 个可用模型'), findsOneWidget);

    // 测试连接（按钮在弹窗滚动区底部，先滚动入视口）
    final dialogScrollable = find
        .descendant(
            of: find.byType(AddServiceDialog), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('测试连接'), 120,
        scrollable: dialogScrollable);
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(find.textContaining('连接成功'), findsOneWidget);

    // 保存
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5)); // 排空 InfoBar Timer
    await tester.pumpAndSettle();
    expect(find.text('DeepSeek'), findsWidgets); // 卡片出现
    expect(appState.services, hasLength(1));
    expect(appState.defaultService!.provider, 'deepseek');

    // ---------- 工作台优化 ----------
    await tester.tap(find.text('优化工作台').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('深度优化').first); // 默认模式为快速，切到深度
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).first, '帮我写个爬虫爬豆瓣电影 Top250');
    await tester.pump();
    llm.enqueueText(kValidContractJson);
    await tester.tap(find.widgetWithText(FilledButton, '✨ 开始优化'));
    await tester.pumpAndSettle();
    expect(find.text('资深 Python 工程师'), findsOneWidget);
    expect(find.textContaining('质量评分'), findsOneWidget);

    // ---------- 一键复制 ----------
    await tester.tap(find.widgetWithText(FilledButton, '📄 一键复制'));
    await tester.pumpAndSettle();
    expect(clipboardText, contains('【角色定位】'));
    await tester.pump(const Duration(seconds: 5)); // 排空 InfoBar Timer
    await tester.pumpAndSettle();

    // ---------- 复查编辑 ----------
    await tester.tap(find.widgetWithText(Button, '📝 复查编辑'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.text('复查清单'), findsOneWidget);
    expect(find.text('帮我写个爬虫爬豆瓣电影 Top250'), findsOneWidget);

    // ---------- 历史记录 ----------
    await tester.tap(find.text('历史记录').first);
    await tester.pumpAndSettle();
    expect(find.text('帮我写个爬虫爬豆瓣电影 Top250'), findsOneWidget);

    // ---------- 系统设置 ----------
    await tester.tap(find.text('系统设置').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('网络与代理'), findsOneWidget);
  });
}
