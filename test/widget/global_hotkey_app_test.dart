/// 全局热键接入测试：启动注册、设置变更重绑、触发唤起、退出解绑。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/app.dart';
import 'package:prompt_optimizer/core/shortcuts.dart';
import 'package:prompt_optimizer/services/global_hotkey_service.dart';
import 'package:prompt_optimizer/state/app_state.dart';

import '../fakes.dart';

class _FakeBackend implements GlobalHotkeyBackend {
  ShortcutBinding? binding;
  VoidCallback? onPressed;
  int registerCalls = 0;
  int unregisterCalls = 0;

  @override
  Future<void> register(ShortcutBinding binding, VoidCallback onPressed) async {
    registerCalls++;
    this.binding = binding;
    this.onPressed = onPressed;
  }

  @override
  Future<void> activateWindow() async {}

  @override
  Future<void> unregister() async {
    unregisterCalls++;
    binding = null;
    onPressed = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState? previous;
  late _FakeBackend backend;
  late GlobalHotkeyService service;
  var windowActivations = 0;

  setUp(() async {
    previous?.dispose();
    final state = await makeTestAppState(llm: FakeLlmClient());
    previous = state;
    appState = state;

    backend = _FakeBackend();
    service = GlobalHotkeyService(backend: backend);
    GlobalHotkeyService.instance = service;
    windowActivations = 0;
    GlobalHotkeyService.debugActivateWindow = () async => windowActivations++;
  });

  tearDown(() {
    GlobalHotkeyService.debugActivateWindow = null;
    service.dispose();
    GlobalHotkeyService.instance = GlobalHotkeyService();
  });

  testWidgets('启动即注册默认热键；修改设置重绑；触发回到工作台并激活窗口',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PromptOptimizerApp());
    await tester.pumpAndSettle();

    expect(backend.registerCalls, 1);
    expect(backend.binding?.label, 'Ctrl+Shift+Space');

    // 先切到设置页，模拟“任意界面”触发
    await tester.tap(find.text('系统设置').first);
    await tester.pumpAndSettle();
    expect(find.text('优化工作台'), findsOneWidget); // 仅导航项

    backend.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('优化工作台'), findsNWidgets(2)); // 导航项 + 页面标题
    expect(windowActivations, 1);

    // 修改全局热键 → 旧注册被替换
    final err = await appState.settings.update(
        appState.settings.settings.copyWith(hotkey: 'Alt+Shift+P'));
    expect(err, isNull);
    await tester.pumpAndSettle();
    expect(backend.binding?.label, 'Alt+Shift+P');

    // 卸载 AppShell 时必须解绑
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(backend.unregisterCalls, greaterThan(0));
  });
}
