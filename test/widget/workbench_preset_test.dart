/// 工作台「编程预置词」下拉 Widget 测试（第 5 步验收）：
/// - 仅「AI 编程 / Bug 修复」场景展示下拉，其他场景不显示
/// - 下拉选项 = 默认空选项 + 已配置预置词名称；无配置时仅空选项
/// - 选择后写入 session.presetId（状态管理与本页控件一致）
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
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

  /// 切换场景 chips
  Future<void> tapScene(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('下拉框显隐（场景条件）', () {
    testWidgets('AI 编程场景显示「编程预置词」下拉', (tester) async {
      await pumpBench(tester);
      await tapScene(tester, 'AI 编程');
      expect(find.text('编程预置词'), findsOneWidget);
    });

    testWidgets('Bug 修复场景显示「编程预置词」下拉', (tester) async {
      await pumpBench(tester);
      await tapScene(tester, 'Bug 修复');
      expect(find.text('编程预置词'), findsOneWidget);
    });

    testWidgets('其他场景（通用/文案写作等）不显示下拉', (tester) async {
      await pumpBench(tester);
      // 默认场景可能是 ai_coding（跟随设置），先切到通用
      await tapScene(tester, '通用');
      expect(find.text('编程预置词'), findsNothing);
      await tapScene(tester, '文案写作');
      expect(find.text('编程预置词'), findsNothing);
    });
  });

  group('下拉选项', () {
    testWidgets('无配置时仅默认空选项', (tester) async {
      await pumpBench(tester);
      await tapScene(tester, 'AI 编程');
      final cb = tester.widget<ComboBox<String>>(
          find.widgetWithText(ComboBox<String>, '（不使用）'));
      expect(cb.items, hasLength(1), reason: '无配置时仅保留默认空选项');
    });

    testWidgets('选项为已配置预置词名称 + 空选项', (tester) async {
      await appState.savePreset(CodingPreset(
          id: 'p1', name: '桌面端', content: 'Electron', createdAt: 1700000000));
      await appState.savePreset(CodingPreset(
          id: 'p2', name: '移动端', content: 'UniApp', createdAt: 1700000001));
      await pumpBench(tester);
      await tapScene(tester, 'AI 编程');
      final cb = tester.widget<ComboBox<String>>(
          find.widgetWithText(ComboBox<String>, '（不使用）'));
      expect(cb.items, hasLength(3), reason: '空选项 + 2 个预置词');
    });
  });

  group('状态管理（与本页表单控件一致）', () {
    // fluent ComboBox 的浮层（_ComboBoxRoute + Acrylic）在 Widget 测试环境
    // hit-test 不可达（tap/tapAt/TestPointer 均被屏障吞掉，已实证），
    // 选项回写逻辑改由控件回调契约验证；用户真实点击链路为控件自身行为。
    testWidgets('选择预置词 → session.presetId 更新；选空 → 清空', (tester) async {
      await appState.savePreset(CodingPreset(
          id: 'p1', name: '桌面端', content: 'Electron', createdAt: 1700000000));
      await pumpBench(tester);
      await tapScene(tester, 'AI 编程');
      expect(appState.session.presetId, isNull);

      final cb = tester.widget<ComboBox<String>>(
          find.widgetWithText(ComboBox<String>, '（不使用）'));
      // 选择「桌面端」（value=p1）
      cb.onChanged!('p1');
      await tester.pump(const Duration(milliseconds: 200));
      expect(appState.session.presetId, 'p1');
      expect(appState.selectedPreset?.name, '桌面端');

      // 切回空选项 → 清空
      cb.onChanged!('');
      await tester.pump(const Duration(milliseconds: 200));
      expect(appState.session.presetId, isNull);
    });

    testWidgets('删除选中的预置词 → session 选择被清空（防悬挂引用）',
        (tester) async {
      await appState.savePreset(CodingPreset(
          id: 'p1', name: '桌面端', content: 'Electron', createdAt: 1700000000));
      await pumpBench(tester);
      await tapScene(tester, 'AI 编程');
      final cb = tester.widget<ComboBox<String>>(
          find.widgetWithText(ComboBox<String>, '（不使用）'));
      cb.onChanged!('p1');
      await tester.pump(const Duration(milliseconds: 200));
      await appState.deletePreset('p1');
      await tester.pump(const Duration(milliseconds: 200));
      expect(appState.session.presetId, isNull);
      expect(appState.selectedPreset, isNull);
    });
  });
}
