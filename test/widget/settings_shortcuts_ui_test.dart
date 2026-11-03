/// 设置页快捷键 UI：悬浮球已移除、四个录制器可改、冲突提示。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/settings_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState? previous;

  setUp(() async {
    previous?.dispose();
    final state = await makeTestAppState(llm: FakeLlmClient());
    previous = state;
    appState = state;
  });

  Future<void> pumpPage(WidgetTester tester,
      {double w = 1300, double h = 1000}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const SettingsPage()));
    await tester.pumpAndSettle();
  }

  Finder recorder(String key) => find.byKey(Key('recorder-$key'));

  Future<void> record(
      WidgetTester tester, String recorderKey, List<LogicalKeyboardKey> keys) async {
    await tester.tap(find.descendant(
        of: recorder(recorderKey), matching: find.text('更改')));
    await tester.pump();
    // 按住全部修饰键，再按主键；最后逆序释放，模拟真实组合键。
    for (final key in keys.take(keys.length - 1)) {
      await tester.sendKeyDownEvent(key);
    }
    await tester.sendKeyDownEvent(keys.last);
    await tester.sendKeyUpEvent(keys.last);
    for (final key in keys.take(keys.length - 1).toList().reversed) {
      await tester.sendKeyUpEvent(key);
    }
    await tester.pump();
  }

  testWidgets('悬浮球开关与标签快捷键设置已移除，仅保留两个录制器', (tester) async {
    await pumpPage(tester);

    expect(find.text('桌面悬浮球'), findsNothing);
    expect(find.byKey(const Key('toggle-floatingBall')), findsNothing);

    for (final key in ['globalHotkey', 'optimizeHotkey']) {
      expect(recorder(key), findsOneWidget, reason: key);
    }
    expect(recorder('closeTabHotkey'), findsNothing);
    expect(recorder('newTabHotkey'), findsNothing);
    expect(find.text('Ctrl+Shift+Space'), findsOneWidget);
    expect(find.text('Ctrl+Enter'), findsOneWidget);
    expect(find.text('关闭当前标签'), findsNothing);
    expect(find.text('新建标签'), findsNothing);
  });

  testWidgets('录制快速优化快捷键并持久化', (tester) async {
    await pumpPage(tester);

    await record(tester, 'optimizeHotkey', [
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.enter,
    ]);
    await tester.pumpAndSettle();

    expect(appState.settings.settings.optimizeHotkey, 'Alt+Enter');
    expect(find.text('Alt+Enter'), findsOneWidget);
  });

  testWidgets('与已有快捷键冲突时提示且不保存', (tester) async {
    await pumpPage(tester);

    // 固定标签快捷键不可被占用
    await record(tester, 'optimizeHotkey', [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyW,
    ]);
    await tester.pump(const Duration(milliseconds: 400));

    expect(appState.settings.settings.optimizeHotkey, 'Ctrl+Enter');
    expect(find.textContaining('固定的标签快捷键'), findsWidgets);

    // 排空 InfoBar 定时器
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('窄屏设置页渲染无溢出', (tester) async {
    await pumpPage(tester, w: 780, h: 1000);
    expect(tester.takeException(), isNull);
  });
}
