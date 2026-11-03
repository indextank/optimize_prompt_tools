/// 工作台应用内快捷键测试：
/// - 默认 Ctrl+T / Ctrl+W / Ctrl+Enter 生效；
/// - 修改设置后旧组合失效、新组合生效；
/// - 首标签对关闭快捷键免疫。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/workbench_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState? previous;
  late FakeLlmClient llm;

  setUp(() async {
    previous?.dispose();
    llm = FakeLlmClient();
    final state = await makeTestAppState(llm: llm);
    previous = state;
    appState = state;
    await appState.saveService(testService(), apiKey: 'sk-test');
    appState.tabs.activeTab.state.rawText = '帮我写一个爬虫';
  });

  tearDown(() {
    // 由下一个用例的 setUp 释放，避免 tabs/runtime 泄漏
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const WorkbenchPage()));
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  testWidgets('默认 Ctrl+T 新建、Ctrl+W 关闭、首标签免疫', (tester) async {
    await pumpPage(tester);
    expect(appState.tabs.tabs, hasLength(1));

    await press(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyT);
    expect(appState.tabs.tabs, hasLength(2));

    await press(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyW);
    expect(appState.tabs.tabs, hasLength(1));

    // 只剩固定首标签时 Ctrl+W 不再关闭
    await press(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyW);
    expect(appState.tabs.tabs, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+Enter 触发当前标签优化', (tester) async {
    llm.enqueueText('优化后的结果');
    await pumpPage(tester);
    expect(llm.capturedRequests, isEmpty);

    await press(
        tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.enter);
    // 等 FakeLlmClient 的零延迟分片全部完成，避免测试结束残留 Timer。
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(llm.capturedRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义 Alt+Enter 生效，标签快捷键仍为固定 Ctrl+T/Ctrl+W', (tester) async {
    await appState.settings.update(appState.settings.settings.copyWith(
      optimizeHotkey: 'Alt+Enter',
    ));
    llm.enqueueText('自定义快捷键结果');
    await pumpPage(tester);

    // 标签快捷键固定，不受优化快捷键影响
    await press(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyT);
    expect(appState.tabs.tabs, hasLength(2));
    await press(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyW);
    expect(appState.tabs.tabs, hasLength(1));

    // 旧优化组合失效、新组合生效
    await press(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.enter);
    await tester.pump();
    expect(llm.capturedRequests, isEmpty);
    await press(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(llm.capturedRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
