/// 任务 ② / ③ Widget 验收：
/// - 开启「并行对比」开关 → 对比模型下拉默认选中第一个候选
///   （关闭后清空，语义保持）；
/// - 「已配置的AI服务」卡片长按拖动调整排序，顺序持久化
///   （重新加载保持；下拉/并行候选顺序联动）。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/model_config_page.dart';
import 'package:prompt_optimizer/ui/pages/workbench_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    appState = await makeTestAppState(llm: FakeLlmClient());
  });

  Future<void> pumpBench(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const WorkbenchPage()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpConfig(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const ModelConfigPage()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('② 开启并行对比默认选中第一个模型', () {
    testWidgets('开启开关 → parallelServiceId = 候选第一个', (tester) async {
      final a = testService(id: 'a', model: 'alpha');
      final b = testService(id: 'b', model: 'beta');
      final c = testService(id: 'c', model: 'gamma');
      await appState.saveService(a, apiKey: 'k');
      await appState.saveService(b, apiKey: 'k');
      await appState.saveService(c, apiKey: 'k');
      await appState.setDefaultService('a'); // 生效=alpha，候选=[beta, gamma]
      await pumpBench(tester);

      final toggle = find.byType(ToggleSwitch);
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pump(const Duration(milliseconds: 400));

      expect(appState.settings.settings.parallelEnabled, isTrue);
      expect(appState.session.parallelServiceId, 'b',
          reason: '默认选中对比下拉中的第一个候选（beta）');
    });

    testWidgets('关闭开关 → 清空对比选择', (tester) async {
      final a = testService(id: 'a', model: 'alpha');
      final b = testService(id: 'b', model: 'beta');
      await appState.saveService(a, apiKey: 'k');
      await appState.saveService(b, apiKey: 'k');
      await pumpBench(tester);

      await tester.tap(find.byType(ToggleSwitch));
      await tester.pump(const Duration(milliseconds: 400));
      expect(appState.session.parallelServiceId, isNotNull);

      await tester.tap(find.byType(ToggleSwitch));
      await tester.pump(const Duration(milliseconds: 400));
      expect(appState.session.parallelServiceId, isNull);
    });
  });

  group('③ 已配置AI服务拖动排序', () {
    testWidgets('拖动第一张卡到第二张上 → 顺序调整且持久化', (tester) async {
      final a = testService(id: 'a', model: 'alpha');
      final b = testService(id: 'b', model: 'beta');
      final c = testService(id: 'c', model: 'gamma');
      await appState.saveService(a, apiKey: 'k');
      await appState.saveService(b, apiKey: 'k');
      await appState.saveService(c, apiKey: 'k');
      await pumpConfig(tester);

      expect(appState.services.map((s) => s.id), ['a', 'b', 'c']);

      // 长按第一张卡中心 → 拖到第二张卡中心 → 松手（按 _DraggableServiceRow key 定位）
      final start = tester.getCenter(find.byKey(const ValueKey('a')));
      final target = tester.getCenter(find.byKey(const ValueKey('b')));
      final gesture = await tester.startGesture(start,
          kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 600)); // 超过长按阈值
      // 微移激活拖动（越过拖拽 slop），再拖到目标
      await gesture.moveBy(const Offset(2, 2));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(target);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(appState.services.map((s) => s.id), ['b', 'a', 'c'],
          reason: 'alpha 拖到 beta 位置后顺序应为 b, a, c');
      // 持久化：重新从存储加载仍保持新顺序
      final reloaded = await appState.storage.loadServices();
      expect(reloaded.map((s) => s.id), ['b', 'a', 'c']);
    });

    testWidgets('拖动后下拉选项顺序联动（并行候选跟排序）', (tester) async {
      final a = testService(id: 'a', model: 'alpha');
      final b = testService(id: 'b', model: 'beta');
      await appState.saveService(a, apiKey: 'k');
      await appState.saveService(b, apiKey: 'k');
      await pumpConfig(tester);
      // 拖动：beta 拖到 alpha 上
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('b'))),
          kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('a'))));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(appState.services.map((s) => s.id), ['b', 'a']);

      await pumpBench(tester);
      await tester.tap(find.text('通用')); // 切到非预置词场景看清头部
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byType(ToggleSwitch));
      await tester.pump(const Duration(milliseconds: 400));
      expect(appState.session.parallelServiceId, 'a',
          reason: '排序后第一个候选应为 alpha（除生效服务外）');
    });
  });
}
