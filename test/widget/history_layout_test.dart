/// 历史记录卡片布局回归：超长原始提示词的省略与无溢出。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/history_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('超长原始提示词：单行省略且卡片行无溢出（历史页红圈问题回归）', (tester) async {
    final llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
    await appState.saveService(testService(), apiKey: 'sk');
    // 造 3 条超长 rawText 记录（复现用户场景）
    for (var i = 0; i < 3; i++) {
      appState.session.rawText =
          '${'1、适当加宽一点当前「回访详细」弹框宽度，解决当前左侧回访日期输入框超过当前分割线的问题，并处理时间控件选择日期时触发接口异常的场景；' * 6} 记录$i';
      appState.session.mode = OptimizeMode.quick;
      llm.enqueueText('结果$i');
      await tester.runAsync(() => appState.startOptimize());
    }

    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const HistoryPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('适当加宽一点当前'), findsWidgets);
    expect(tester.takeException(), isNull, reason: '超长文本卡片不得出现 RenderFlex 溢出');

    // 标题文本应为省略渲染（宽度被约束），且不超出卡片右缘
    final title = find.textContaining('适当加宽一点当前').first;
    final titleRect = tester.getRect(title);
    final openBtn = tester.getRect(find.text('打开').first);
    expect(titleRect.right, lessThan(openBtn.left),
        reason: '标题不得压到「打开」按钮区域');
  });

  testWidgets('390 紧凑态：长文本卡片无溢出', (tester) async {
    final llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
    await appState.saveService(testService(), apiKey: 'sk');
    appState.session.rawText = '请按照以下步骤完成接口请求日志记录的开发工作：${'记录每个请求的耗时与状态码；' * 20}';
    appState.session.mode = OptimizeMode.quick;
    llm.enqueueText('结果');
    await tester.runAsync(() => appState.startOptimize());

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const HistoryPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
