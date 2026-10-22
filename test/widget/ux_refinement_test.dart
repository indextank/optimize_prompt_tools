/// 本轮细节优化回归测试：
/// ① 并行开关交互修复 ② 导航栏版本模块 ③ 会话默认值跟随设置
/// ④ 主流分辨率（含窄屏）渲染无溢出
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prompt_optimizer/app.dart';
import 'package:prompt_optimizer/services/update_service.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/llm_client.dart';
import 'package:prompt_optimizer/services/settings_service.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/model_config_page.dart';
import 'package:prompt_optimizer/ui/pages/review_edit_page.dart';
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

  Future<void> pumpAt(WidgetTester tester, Widget child, double w, double h) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(child));
    await tester.pumpAndSettle();
  }

  group('③ 会话默认值跟随设置（默认模式=快速优化，默认场景=AI编程）', () {
    test('新 AppState 会话初始值来自设置', () async {
      expect(appState.session.mode, OptimizeMode.quick);
      expect(appState.session.sceneId, 'ai_coding');
    });

    test('设置项变更后新会话生效', () async {
      await appState.settings.update(
          appState.settings.settings.copyWith(defaultMode: OptimizeMode.quick));
      final s2 = await makeTestAppState(llm: llm, storage: appState.storage);
      expect(s2.session.mode, OptimizeMode.quick);
      expect(s2.session.sceneId, 'ai_coding'); // 场景保持
    });

    test('设置变更通知转发到 AppState（开关可重绘的根因修复）', () async {
      var notified = 0;
      appState.addListener(() => notified++);
      await appState.settings
          .update(appState.settings.settings.copyWith(parallelEnabled: true));
      expect(notified, greaterThan(0));
    });
  });

  group('① 并行对比开关（工作台）设置持久化', () {
    testWidgets('运行时开关联动；重载（模拟重启）后默认关闭', (tester) async {
      await appState.saveService(testService(), apiKey: 'sk');
      await appState.saveService(
          testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
          apiKey: 'sk2');
      await pumpAt(tester, const WorkbenchPage(), 1440, 900);
      expect(appState.settings.settings.parallelEnabled, isFalse);
      await tester.tap(find.text('并行对比'));
      await tester.pumpAndSettle();
      expect(appState.settings.settings.parallelEnabled, isTrue);
      final reloaded = await SettingsService.load(appState.storage);
      // 新语义（覆盖旧持久化行为）：每次运行软件默认关闭，不沿用上次开启状态
      expect(reloaded.settings.parallelEnabled, isFalse,
          reason: '重新加载（模拟重启）默认关闭，不沿用上次开启状态');
      await tester.tap(find.text('并行对比'));
      await tester.pumpAndSettle();
      expect(appState.settings.settings.parallelEnabled, isFalse);
    });
  });

  group('② 导航栏版本模块', () {
    testWidgets('底部展示版本号与检查更新按钮，无平台标注', (tester) async {
      PackageInfo.setMockInitialValues(
          appName: 'prompt_optimizer',
          packageName: 'dev.promptoptimizer.prompt_optimizer',
          version: '1.0.0',
          buildNumber: '1',
          buildSignature: '');
      UpdateService.debugOverride = () => _FakeLatestService();
      await pumpAt(tester, const PromptOptimizerApp(), 1440, 900);
      expect(find.text('提示词优化工具'), findsWidgets); // 导航底部版本模块
      expect(find.text('v1.0.0 · Build 1'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);
      expect(find.textContaining('Win / Linux / Android'), findsNothing);
    });

    testWidgets('点击检查更新弹出结果提示', (tester) async {
      PackageInfo.setMockInitialValues(
          appName: 'prompt_optimizer',
          packageName: 'dev.promptoptimizer.prompt_optimizer',
          version: '1.0.0',
          buildNumber: '1',
          buildSignature: '');
      UpdateService.debugOverride = () => _FakeLatestService();
      await pumpAt(tester, const PromptOptimizerApp(), 1440, 900);
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // InfoBar 入场延迟
      expect(find.textContaining('已是最新版本'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // 排空定时器
      await tester.pumpAndSettle();
    });
  });

  group('④ 主流分辨率渲染兼容（无溢出/异常）', () {
    testWidgets('工作台 1440×900 桌面态', (tester) async {
      await pumpAt(tester, const WorkbenchPage(), 1440, 900);
      expect(tester.takeException(), isNull);
    });

    testWidgets('工作台 390×844 手机竖屏紧凑态', (tester) async {
      await pumpAt(tester, const WorkbenchPage(), 390, 844);
      expect(tester.takeException(), isNull);
      expect(find.text('优化工作台'), findsOneWidget);
      expect(find.text('原始提示词'), findsOneWidget);
    });

    testWidgets('复查编辑 1020×700 最小桌面窗口', (tester) async {
      await appState.saveService(testService(), apiKey: 'sk');
      appState.session.rawText = '原文';
      appState.session.mode = OptimizeMode.deep;
    appState.session.outputStyle = OutputStyle.full; // 结构化契约用例显式指定完整模式 // 显式深度模式（默认为快速）
      llm.enqueueText(kValidContractJson);
      await tester.runAsync(() => appState.startOptimize());
      await pumpAt(tester, const ReviewEditPage(), 1020, 700);
      await tester.pump();
      expect(tester.takeException(), isNull);
      // 1020 宽：原文栏自动折叠，清单栏保留
      expect(find.text('原始提示词'), findsNothing);
      expect(find.text('复查清单'), findsOneWidget);
    });

    testWidgets('复查编辑 860 宽仅编辑器', (tester) async {
      await appState.saveService(testService(), apiKey: 'sk');
      appState.session.rawText = '原文';
      appState.session.mode = OptimizeMode.deep;
    appState.session.outputStyle = OutputStyle.full; // 结构化契约用例显式指定完整模式 // 显式深度模式（默认为快速）
      llm.enqueueText(kValidContractJson);
      await tester.runAsync(() => appState.startOptimize());
      await pumpAt(tester, const ReviewEditPage(), 860, 700);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('原始提示词'), findsNothing);
      expect(find.text('复查清单'), findsNothing);
    });

    testWidgets('模型配置页 1024 宽含长状态文本不溢出', (tester) async {
      await appState.saveService(testService(), apiKey: 'sk');
      llm.connectionResult =
          const ConnectionTestResult(success: false, latencyMs: 0, message: '网络连接失败，请检查网络与代理设置（长错误文案压力测试）');
      await pumpAt(tester, const ModelConfigPage(), 1024, 800);
      await tester.tap(find.text('📶 批量检测连通性'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('✗'), findsOneWidget);
    });
  });
}

/// 假更新服务：固定返回"已是最新"（避免 widget 测试触网）
class _FakeLatestService extends UpdateService {
  @override
  Future<UpdateCheckResult?> checkLatest(String currentVersion,
          {String? platform}) async =>
      null;
}
