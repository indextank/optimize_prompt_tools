/// 布局修复视觉证据 golden：与两张用户问题截图同尺寸/同场景对照。
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/add_service_dialog.dart';
import 'package:prompt_optimizer/ui/pages/model_config_page.dart';
import 'package:prompt_optimizer/ui/pages/workbench_page.dart';

import '../fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes =
        await File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
            .readAsBytes();
    final loader = FontLoader('NotoCJK')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  FluentApp app(Widget child) => FluentApp(
        theme: FluentThemeData(
            brightness: Brightness.light, fontFamily: 'NotoCJK'),
        home: child,
      );

  testWidgets('工作台 1300×770（图1 同尺寸：头部右缘+场景chips）', (tester) async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    await appState.saveService(
        testService(id: 'k', provider: 'kimi', model: 'k3')
            .copyWith(apiUrl: 'https://api.kimi.com/coding/v1'),
        apiKey: 'sk');
    appState.session.rawText = '帮我写个爬虫爬豆瓣电影 Top250，要求处理反爬和异常重试';
    tester.view.physicalSize = const Size(1300, 770);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const WorkbenchPage()));
    await tester.pumpAndSettle();
    await expectLater(find.byType(WorkbenchPage),
        matchesGoldenFile('goldens/layout-fixed-workbench-1300.png'));
  });

  testWidgets('添加服务弹窗 1280×720（图2 同场景：右侧滚动条车道）', (tester) async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        app(AddServiceDialog(modelFetcher: (_, __, ___) async => [])));
    await tester.pumpAndSettle();
    // 展开服务商下拉并选中智谱（多接口地址）复现图2场景
    await tester.tap(find.byType(ComboBox<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('智谱开放平台').last);
    await tester.pumpAndSettle();
    await expectLater(find.byType(AddServiceDialog),
        matchesGoldenFile('goldens/layout-fixed-dialog-1280.png'));
  });

  testWidgets('模型配置 1300×770 批量检测后（右对齐证据）', (tester) async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    await appState.saveService(
        testService(id: 'k', provider: 'kimi', model: 'k3')
            .copyWith(apiUrl: 'https://api.kimi.com/coding/v1'),
        apiKey: 'sk');
    await appState.saveService(
        testService(id: 'z', provider: 'zhipu', model: 'glm-5.3-flashx')
            .copyWith(apiUrl: 'https://open.bigmodel.cn/api/paas/v4'),
        apiKey: 'sk2');
    tester.view.physicalSize = const Size(1300, 770);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const ModelConfigPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('📶 批量检测连通性'));
    await tester.pumpAndSettle();
    expect(find.textContaining('连接正常'), findsNWidgets(2));
    await expectLater(find.byType(ModelConfigPage),
        matchesGoldenFile('goldens/layout-fixed-batch-check-1300.png'));
  });

  testWidgets('工作台并行对比双列结果态 1300×770', (tester) async {
    final l = FakeLlmClient();
    appState = await makeTestAppState(llm: l);
    appState.session.outputStyle = OutputStyle.full;
    await appState.saveService(testService(), apiKey: 'sk'); // 默认生效服务
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false)
            .copyWith(apiUrl: 'https://api.kimi.com/coding/v1'),
        apiKey: 'sk2');
    await appState.settings
        .update(appState.settings.settings.copyWith(parallelEnabled: true));
    appState.session.parallelServiceId = 'svc-2';
    appState.session.rawText = '帮我写个爬虫爬豆瓣电影 Top250';
    appState.session.mode = OptimizeMode.deep;
    l.enqueueText(kValidContractJson);
    l.enqueueText(kValidContractJson);
    await tester.runAsync(() => appState.startOptimize());
    tester.view.physicalSize = const Size(1300, 770);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const WorkbenchPage()));
    await tester.pumpAndSettle();
    await expectLater(find.byType(WorkbenchPage),
        matchesGoldenFile('goldens/layout-parallel-compare-1300.png'));
  });

  testWidgets('模型配置 390×844 紧凑态（移动端窄屏适配）', (tester) async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    await appState.saveService(testService(), apiKey: 'sk');
    await appState.saveService(
        testService(id: 's2', provider: 'zhipu', model: 'glm-4.6'),
        apiKey: 'sk2');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const ModelConfigPage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(ModelConfigPage),
        matchesGoldenFile('goldens/layout-fixed-config-390.png'));
  });
}
