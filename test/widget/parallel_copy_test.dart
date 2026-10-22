/// 并行对比结果复制按钮回归测试：
/// - 并行对比开启 + 双列结果完成后，「一键复制」拆为「复制结果1/2」，
///   各复制对应列的优化结果（列序与双列展示一致）
/// - 关闭并行对比开关后，按钮复原为单一「一键复制」
/// - 单结果（非并行）始终保持单一「一键复制」
/// - 某列失败时，其复制按钮禁用（无结果可复制）
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/optimize_engine.dart';
import 'package:prompt_optimizer/services/parallel_scheduler.dart';
import 'package:prompt_optimizer/state/app_state.dart';
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

  /// 构造一个并行完成态（success 可控），并写入 session.parallelStates
  ParallelRunState doneState(ServiceConfig svc, String apiKey,
      {bool success = true, String resultText = '结果'}) {
    final st = ParallelRunState(service: svc, apiKey: apiKey);
    if (success) {
      st.done = true;
      st.runResult = EngineRunResult(
        result: OptimizeResult(role: resultText),
        elapsedMs: 100,
      );
    } else {
      st.done = true;
      st.error = Exception('调用失败');
    }
    return st;
  }

  Future<void> pumpBench(WidgetTester tester, {double w = 1440}) async {
    tester.view.physicalSize = Size(w, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const WorkbenchPage()));
    await tester.pumpAndSettle();
  }

  ToggleSwitch parallelToggle(WidgetTester tester) => tester
      .widgetList(find.byType(ToggleSwitch))
      .map((w) => w as ToggleSwitch)
      .firstWhere((t) => (t.content as Text?)?.data == '并行对比');

  /// 剪贴板捕获（Clipboard.setData 走 SystemChannels.platform）
  String? captured;
  late TestDefaultBinaryMessenger messenger;

  setUp(() {
    captured = null;
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        captured = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('并行对比结果：复制按钮拆分', () {
    testWidgets('双列结果完成 → 显示「复制结果1/2」且无「一键复制」', (tester) async {
      final svcA = testService(id: 'a', model: 'model-A');
      final svcB = testService(id: 'b', model: 'model-B');
      await appState.saveService(svcA, apiKey: 'k1');
      await appState.saveService(svcB, apiKey: 'k2');
      await appState.settings
          .update(appState.settings.settings.copyWith(parallelEnabled: true));
      appState.session.parallelServiceId = 'b';
      appState.session.parallelStates['a'] =
          doneState(svcA, 'k1', resultText: '列一结果');
      appState.session.parallelStates['b'] =
          doneState(svcB, 'k2', resultText: '列二结果');

      await pumpBench(tester);

      expect(find.text('复制结果1'), findsOneWidget);
      expect(find.text('复制结果2'), findsOneWidget);
      expect(find.text('📄 一键复制'), findsNothing);
    });

    testWidgets('点击「复制结果1/2」分别复制对应列结果', (tester) async {
      final svcA = testService(id: 'a', model: 'model-A');
      final svcB = testService(id: 'b', model: 'model-B');
      await appState.saveService(svcA, apiKey: 'k1');
      await appState.saveService(svcB, apiKey: 'k2');
      await appState.settings
          .update(appState.settings.settings.copyWith(parallelEnabled: true));
      appState.session.parallelServiceId = 'b';
      final stA = doneState(svcA, 'k1', resultText: '列一结果');
      final stB = doneState(svcB, 'k2', resultText: '列二结果');
      appState.session.parallelStates['a'] = stA;
      appState.session.parallelStates['b'] = stB;

      await pumpBench(tester);

      await tester.tap(find.text('复制结果1'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(captured, stA.runResult!.result.toPlainText(),
          reason: '复制结果1 必须复制第一列结果');

      await tester.tap(find.text('复制结果2'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(captured, stB.runResult!.result.toPlainText(),
          reason: '复制结果2 必须复制第二列结果');

      // 排空 InfoBar 自动关闭 Timer（displayInfoBar 入场延迟 + 自动关闭）
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('关闭并行对比开关后复原单一「一键复制」', (tester) async {
      final svcA = testService(id: 'a', model: 'model-A');
      final svcB = testService(id: 'b', model: 'model-B');
      await appState.saveService(svcA, apiKey: 'k1');
      await appState.saveService(svcB, apiKey: 'k2');
      await appState.settings
          .update(appState.settings.settings.copyWith(parallelEnabled: true));
      appState.session.parallelServiceId = 'b';
      appState.session.parallelStates['a'] = doneState(svcA, 'k1');
      appState.session.parallelStates['b'] = doneState(svcB, 'k2');

      await pumpBench(tester);
      expect(find.text('复制结果1'), findsOneWidget, reason: '开启态为双按钮');

      // 关闭并行对比开关 → 按钮复原
      parallelToggle(tester).onChanged!(false);
      await tester.pumpAndSettle();
      expect(find.text('📄 一键复制'), findsOneWidget);
      expect(find.text('复制结果1'), findsNothing);
      expect(find.text('复制结果2'), findsNothing);
    });

    testWidgets('某列失败时该列复制按钮禁用', (tester) async {
      final svcA = testService(id: 'a', model: 'model-A');
      final svcB = testService(id: 'b', model: 'model-B');
      await appState.saveService(svcA, apiKey: 'k1');
      await appState.saveService(svcB, apiKey: 'k2');
      await appState.settings
          .update(appState.settings.settings.copyWith(parallelEnabled: true));
      appState.session.parallelServiceId = 'b';
      appState.session.parallelStates['a'] = doneState(svcA, 'k1');
      appState.session.parallelStates['b'] =
          doneState(svcB, 'k2', success: false);

      await pumpBench(tester);

      final btn2 = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '复制结果2'));
      expect(btn2.onPressed, isNull, reason: '失败列无结果可复制，按钮必须禁用');
      final btn1 = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '复制结果1'));
      expect(btn1.onPressed, isNotNull, reason: '成功列复制按钮保持可用');
    });
  });

  group('非并行结果：保持单一按钮', () {
    testWidgets('单结果（并行关闭）始终为「一键复制」', (tester) async {
      final svcA = testService(id: 'a', model: 'model-A');
      await appState.saveService(svcA, apiKey: 'k1');
      appState.session.parallelStates['a'] = doneState(svcA, 'k1');

      await pumpBench(tester);

      expect(find.text('📄 一键复制'), findsOneWidget);
      expect(find.text('复制结果1'), findsNothing);
    });

    testWidgets('并行开启但仅 1 路结果（对比服务被丢弃）→ 仍单一按钮', (tester) async {
      final svcA = testService(id: 'a', model: 'model-A');
      final svcB = testService(id: 'b', model: 'model-B');
      await appState.saveService(svcA, apiKey: 'k1');
      await appState.saveService(svcB, apiKey: 'k2');
      await appState.settings
          .update(appState.settings.settings.copyWith(parallelEnabled: true));
      appState.session.parallelServiceId = 'b';
      // 仅一路成功（另一路因缺 key 被调度器丢弃，未进 parallelStates）
      appState.session.parallelStates['a'] = doneState(svcA, 'k1');

      await pumpBench(tester);

      expect(find.text('📄 一键复制'), findsOneWidget);
      expect(find.text('复制结果1'), findsNothing);
    });
  });
}
