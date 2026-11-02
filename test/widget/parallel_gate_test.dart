/// 并行对比门槛与下拉规则回归测试（2026-10-08 架构调整后）：
/// - 门槛 UI 位于「优化工作台-优化模式」模块（配置页并行区块已移除）
/// - <2 服务：开关锁定 + 原因提示；≥2 服务：开关可用
/// - 开关开启后展示对比模型下拉（仅模型名、排除当前生效服务、单选）
/// - 配置页默认服务下拉「未配置」显隐逻辑保留在本文件回归
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/model_config_page.dart';
import 'package:prompt_optimizer/ui/pages/workbench_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmClient llm;

  setUp(() async {
    llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
  });

  Future<void> pumpConfig(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const ModelConfigPage()));
    await tester.pumpAndSettle();
  }

  Future<void> pumpBench(WidgetTester tester, {double w = 1440}) async {
    tester.view.physicalSize = Size(w, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const WorkbenchPage()));
    await tester.pumpAndSettle();
  }

  Future<void> addService(String id,
      {String provider = 'deepseek',
      String model = 'deepseek-flash',
      bool isDefault = false}) {
    return appState.saveService(
        testService(id: id, provider: provider, model: model, isDefault: isDefault),
        apiKey: 'sk-$id');
  }

  ToggleSwitch parallelToggle(WidgetTester tester) => tester
      .widgetList(find.byType(ToggleSwitch))
      .map((w) => w as ToggleSwitch)
      .firstWhere((t) => (t.content as Text?)?.data == '并行对比');

  group('配置页：并行区块已移除', () {
    testWidgets('AI模型配置页不再出现「多模型并行优化」设置项', (tester) async {
      await addService('a');
      await pumpConfig(tester);
      expect(find.text('多模型并行优化'), findsNothing);
      expect(find.text('请至少配置2个AI服务后再开启此功能'), findsNothing);
    });
  });

  group('工作台门槛：开关锁定与提示', () {
    testWidgets('0 服务：开关禁用 + 原因提示', (tester) async {
      await pumpBench(tester);
      expect(parallelToggle(tester).onChanged, isNull);
      expect(find.text('配置 ≥2 个 AI 服务后可开启并行对比'), findsOneWidget);
    });

    testWidgets('仅 1 个服务：开关锁定为不可开启（即使设置曾被开启）', (tester) async {
      await addService('a');
      // 全局设置曾被开启 + 该 tab 开关曾被开启：均不得绕过 <2 服务锁定
      await appState.settings.update(
          appState.settings.settings.copyWith(parallelEnabled: true));
      appState.session.parallelEnabled = true;
      await pumpBench(tester);
      final t = parallelToggle(tester);
      expect(t.onChanged, isNull, reason: '仅 1 个可用模型时开关必须锁定');
      expect(t.checked, isFalse, reason: '锁定时不显示开启态，避免歧义');
      expect(find.text('配置 ≥2 个 AI 服务后可开启并行对比'), findsOneWidget);
      // 下拉框不出现
      expect(find.text('选择对比模型'), findsNothing);
    });

    testWidgets('≥2 服务：开关可用且无锁定提示', (tester) async {
      await addService('a');
      await addService('b', provider: 'kimi', model: 'k3');
      await pumpBench(tester);
      expect(parallelToggle(tester).onChanged, isNotNull);
      expect(find.text('配置 ≥2 个 AI 服务后可开启并行对比'), findsNothing);
    });

    testWidgets('从 2 个删到 1 个：开关自动回到锁定+提示', (tester) async {
      await addService('a');
      await addService('b', provider: 'kimi', model: 'k3');
      // 并行开关为 tab 级状态：直接开启当前 tab 的并行（不再写全局 settings）
      appState.session.parallelEnabled = true;
      appState.session.parallelServiceId = 'b';
      await pumpBench(tester);
      expect(parallelToggle(tester).onChanged, isNotNull);
      await appState.deleteService(appState.services.firstWhere((s) => s.id == 'b'));
      await tester.pumpAndSettle();
      expect(appState.configuredServiceCount, 1);
      expect(parallelToggle(tester).onChanged, isNull);
      expect(find.text('配置 ≥2 个 AI 服务后可开启并行对比'), findsOneWidget);
      expect(appState.session.parallelServiceId, isNull, reason: '删除服务应清空会话并行选择');
    });
  });

  group('优化请求中的并行控制', () {
    testWidgets('并行开启时禁用开关和对比模型下拉，完成后恢复', (tester) async {
      await addService('a');
      await addService('b', provider: 'kimi', model: 'k3');
      // 并行开关为 tab 级状态：直接开启当前 tab 的并行（不再写全局 settings）
      appState.session.parallelEnabled = true;
      appState.session.parallelServiceId = 'b';
      appState.session.rawText = '原文';
      llm.enqueueText(kValidContractJson);
      llm.enqueueText(kValidContractJson);
      await pumpBench(tester);
      llm.chunkDelay = const Duration(milliseconds: 1);

      late final Future<Object?> future;
      await tester.runAsync(() async {
        future = appState.startOptimize();
      });
      await tester.pump();

      expect(appState.session.optimizing, isTrue);
      expect(parallelToggle(tester).onChanged, isNull);
      final comboFinder = find.widgetWithText(ComboBox<String>, 'k3');
      final combo = tester.widget<ComboBox<String>>(comboFinder);
      expect(combo.onChanged, isNull);
      expect(parallelToggle(tester).checked, isTrue);
      expect(combo.value, 'b');

      await tester.runAsync(() => future);
      await tester.pumpAndSettle();

      expect(appState.session.optimizing, isFalse);
      expect(parallelToggle(tester).onChanged, isNotNull);
      expect(tester.widget<ComboBox<String>>(comboFinder).onChanged, isNotNull);
    });

    testWidgets('单模型优化时也禁用并行开关，完成后恢复', (tester) async {
      await addService('a');
      await addService('b', provider: 'kimi', model: 'k3');
      appState.session.rawText = '原文';
      llm.enqueueText(kValidContractJson);
      await pumpBench(tester);
      llm.chunkDelay = const Duration(milliseconds: 1);

      late final Future<Object?> future;
      await tester.runAsync(() async {
        future = appState.startOptimize();
      });
      await tester.pump();

      expect(appState.session.optimizing, isTrue);
      expect(parallelToggle(tester).onChanged, isNull);

      await tester.runAsync(() => future);
      await tester.pumpAndSettle();

      expect(appState.session.optimizing, isFalse);
      expect(parallelToggle(tester).onChanged, isNotNull);
    });
  });

  group('下拉框显隐与选项规则', () {
    testWidgets('默认仅展示开关，开启后实时展示下拉，关闭后自动隐藏', (tester) async {
      await addService('a');
      await addService('b', provider: 'kimi', model: 'k3');
      await pumpBench(tester);
      // 默认（关）：无下拉
      expect(find.text('k3'), findsNothing);
      // 开启：默认选中下拉中的第一个模型（k3），不再停留在空选项
      await tester.tap(find.text('并行对比'));
      await tester.pumpAndSettle();
      expect(find.text('k3'), findsOneWidget, reason: '开启后默认选中第一个模型');
      expect(appState.session.parallelServiceId, 'b');
      expect(find.text('选择对比模型'), findsNothing);
      // 关闭：下拉隐藏
      await tester.tap(find.text('并行对比'));
      await tester.pumpAndSettle();
      expect(find.text('k3'), findsNothing);
      expect(appState.session.parallelServiceId, isNull, reason: '关闭开关应清空对比选择');
    });

    testWidgets('下拉仅展示模型名、排除当前生效服务、单选生效', (tester) async {
      await addService('a', isDefault: true); // 生效服务 deepseek-flash
      await addService('b', provider: 'kimi', model: 'k3');
      await addService('c', provider: 'zhipu', model: 'glm-4.6');
      // 并行开关为 tab 级状态：直接开启当前 tab 的并行（不再写全局 settings）
      appState.session.parallelEnabled = true;
      await pumpBench(tester);
      // 展开下拉
      await tester.tap(find.text('选择对比模型'));
      await tester.pumpAndSettle();
      // 包含非默认服务模型名
      expect(find.text('k3'), findsWidgets);
      expect(find.text('glm-4.6'), findsWidgets);
      // 不包含当前生效（默认）服务的模型名
      expect(find.text('deepseek-flash'), findsNothing);
      // 不显示提供商名称
      expect(find.textContaining('Kimi'), findsNothing);
      expect(find.textContaining('智谱'), findsNothing);
      // 单选：选择 k3 后会话记录且候选数变 2
      await tester.tap(find.text('k3').last);
      await tester.pumpAndSettle();
      expect(appState.session.parallelServiceId, 'b');
      expect(appState.parallelCandidateCount, 2);
      expect(find.text('选择对比模型后并行生效'), findsNothing);
    });

    testWidgets('已开启但未选择：显示「选择对比模型后并行生效」提示', (tester) async {
      await addService('a');
      await addService('b', provider: 'kimi', model: 'k3');
      // 并行开关为 tab 级状态：直接开启当前 tab 的并行（不再写全局 settings）
      appState.session.parallelEnabled = true;
      await pumpBench(tester);
      expect(find.text('选择对比模型后并行生效'), findsOneWidget);
      expect(appState.parallelCandidateCount, 1);
    });

    testWidgets('会话切换生效服务后，冲突的对比选择被清空', (tester) async {
      await addService('a', isDefault: true);
      await addService('b', provider: 'kimi', model: 'k3');
      appState.session.parallelServiceId = 'b';
      appState.setSessionService('b'); // 生效服务切到 b（同步清空冲突选择）
      expect(appState.session.parallelServiceId, isNull);
    });
  });

  group('配置页默认服务下拉（保留回归）', () {
    testWidgets('0 服务：默认下拉保留「未配置」，计数为 0', (tester) async {
      await pumpConfig(tester);
      expect(find.text('已配置的AI服务（0）'), findsOneWidget);
      expect(find.text('未配置'), findsOneWidget);
    });

    testWidgets('≥1 服务：默认下拉移除「未配置」', (tester) async {
      await addService('a');
      await pumpConfig(tester);
      expect(find.text('已配置的AI服务（1）'), findsOneWidget);
      expect(find.text('未配置'), findsNothing);
    });
  });
}
