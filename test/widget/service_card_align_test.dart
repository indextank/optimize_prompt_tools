/// 批量检测连通性后「状态+编辑/删除」区域右对齐回归测试。
/// 用户截图（旧构建）：检测完成后状态文本与按钮悬在卡片中部、右侧留大片空白。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/model_config_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> seedTwoServices() async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    await appState.saveService(
        testService(id: 'k', provider: 'kimi', model: 'k3')
            .copyWith(apiUrl: 'https://api.kimi.com/coding/v1'),
        apiKey: 'sk');
    await appState.saveService(
        testService(id: 'z', provider: 'zhipu', model: 'glm-5.3-flashx')
            .copyWith(apiUrl: 'https://open.bigmodel.cn/api/paas/v4'),
        apiKey: 'sk2');
  }

  /// 断言两张服务卡片的「删除」按钮都贴住所在行（Row）的右缘
  void expectButtonsRightAligned(WidgetTester tester, {required String stage}) {
    final delBtns = find.widgetWithText(Button, '🗑 删除');
    expect(delBtns, findsNWidgets(2), reason: '$stage：应有两张服务卡片');
    for (var i = 0; i < 2; i++) {
      final btnRect = tester.getRect(delBtns.at(i));
      final row =
          find.ancestor(of: delBtns.at(i), matching: find.byType(Row)).first;
      final rowRect = tester.getRect(row);
      expect((rowRect.right - btnRect.right).abs(), lessThanOrEqualTo(2),
          reason: '$stage：第 ${i + 1} 张卡片按钮未贴行右缘（差 ${rowRect.right - btnRect.right}px）');
      // 行本身应接近满宽（防止整行缩成自然宽导致按钮悬在中部——旧构建截图症状）
      expect(rowRect.width,
          greaterThan(tester.view.physicalSize.width * 0.55),
          reason: '$stage：卡片内容行未铺满（宽 ${rowRect.width}）');
    }
  }

  testWidgets('批量检测进行中按钮置灰防重复点击，完成后恢复', (tester) async {
    final llm = FakeLlmClient()
      ..connectionLatency = const Duration(milliseconds: 200);
    appState = await makeTestAppState(llm: llm);
    await appState.saveService(testService(), apiKey: 'sk');
    tester.view.physicalSize = const Size(1300, 770);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const ModelConfigPage()));
    await tester.pumpAndSettle();

    final btn = find.widgetWithText(Button, '📶 批量检测连通性');
    expect(tester.widget<Button>(btn).onPressed, isNotNull);
    await tester.tap(btn);
    await tester.pump(); // 检测进行中
    // 按钮置灰 + 文案切换
    final during = find.widgetWithText(Button, '⏳ 检测中…');
    expect(during, findsOneWidget);
    expect(tester.widget<Button>(during).onPressed, isNull,
        reason: '检测未完成前按钮必须置灰');
    expect(find.widgetWithText(Button, '📶 批量检测连通性'), findsNothing);
    // 重复点击无效（onPressed 为 null，无法再次触发）
    // 完成检测（推进假时钟跑完注入的延迟）
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final after = find.widgetWithText(Button, '📶 批量检测连通性');
    expect(tester.widget<Button>(after).onPressed, isNotNull,
        reason: '检测完成后按钮应恢复可用');
  });

  testWidgets('桌面宽屏：检测前后状态与按钮均保持右对齐', (tester) async {
    await seedTwoServices();
    tester.view.physicalSize = const Size(1300, 770);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const ModelConfigPage()));
    await tester.pumpAndSettle();

    expectButtonsRightAligned(tester, stage: '检测前');

    await tester.tap(find.text('📶 批量检测连通性'));
    await tester.pumpAndSettle();
    expect(find.textContaining('连接正常'), findsNWidgets(2));

    expectButtonsRightAligned(tester, stage: '检测后');
    expect(tester.takeException(), isNull);
  });

  testWidgets('紧凑窄屏：检测前后按钮行同样右对齐', (tester) async {
    await seedTwoServices();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const ModelConfigPage()));
    await tester.pumpAndSettle();

    expectButtonsRightAligned(tester, stage: '紧凑检测前');
    await tester.tap(find.text('📶 批量检测连通性'));
    await tester.pumpAndSettle();
    expectButtonsRightAligned(tester, stage: '紧凑检测后');
    expect(tester.takeException(), isNull);
  });
}
