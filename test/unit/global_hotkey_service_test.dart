/// 全局热键服务单测：注册/替换/冲突/非法/平台降级/窗口激活。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/shortcuts.dart';
import 'package:prompt_optimizer/services/global_hotkey_service.dart';

class _FakeBackend implements GlobalHotkeyBackend {
  ShortcutBinding? binding;
  VoidCallback? onPressed;
  int registerCalls = 0;
  int unregisterCalls = 0;
  bool fail = false;

  @override
  Future<void> register(ShortcutBinding binding, VoidCallback onPressed) async {
    registerCalls++;
    if (fail) {
      throw PlatformException(code: 'conflict', message: '已被占用');
    }
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

  late _FakeBackend backend;
  late GlobalHotkeyService service;

  setUp(() {
    backend = _FakeBackend();
    service = GlobalHotkeyService(backend: backend);
    GlobalHotkeyService.debugActivateWindow = null;
  });

  tearDown(() {
    GlobalHotkeyService.debugActivateWindow = null;
    service.dispose();
  });

  test('合法组合注册成功并可触发回调', () async {
    var activated = 0;
    final status = await service.bind('Ctrl+Shift+Space',
        onActivate: () async => activated++);

    expect(status, GlobalHotkeyStatus.registered);
    expect(service.status, GlobalHotkeyStatus.registered);
    expect(service.boundLabel, 'Ctrl+Shift+Space');
    expect(backend.registerCalls, 1);
    expect(backend.binding?.label, 'Ctrl+Shift+Space');

    backend.onPressed!();
    expect(activated, 1);
  });

  test('非法格式/缺少修饰键直接拒绝，不调用后端', () async {
    expect(await service.bind('bad', onActivate: _noop),
        GlobalHotkeyStatus.invalid);
    expect(await service.bind('F5', onActivate: _noop),
        GlobalHotkeyStatus.invalid);
    expect(service.message, contains('修饰键'));
    expect(backend.registerCalls, 0);
  });

  test('重新绑定会先卸载旧组合', () async {
    await service.bind('Ctrl+Shift+Space', onActivate: _noop);
    await service.bind('Alt+Shift+P', onActivate: _noop);

    expect(backend.unregisterCalls, 2); // bind 前 + 替换前
    expect(service.boundLabel, 'Alt+Shift+P');
    expect(service.status, GlobalHotkeyStatus.registered);
  });

  test('被占用时返回 conflict 并给出原因', () async {
    backend.fail = true;
    final status =
        await service.bind('Ctrl+Shift+Space', onActivate: _noop);
    expect(status, GlobalHotkeyStatus.conflict);
    expect(service.message, contains('已被占用'));
    expect(service.boundLabel, isNull);
  });

  test('unbind 幂等并回到 idle', () async {
    await service.bind('Ctrl+Shift+Space', onActivate: _noop);
    await service.unbind();
    expect(service.status, GlobalHotkeyStatus.idle);
    expect(service.boundLabel, isNull);
    final calls = backend.unregisterCalls;
    await service.unbind();
    expect(backend.unregisterCalls, calls + 1);
  });

  test('非桌面平台返回 unsupported（不注入后端）', () async {
    // flutter test 默认 targetPlatform = android
    final real = GlobalHotkeyService();
    addTearDown(real.dispose);
    final status = await real.bind('Ctrl+Shift+Space', onActivate: _noop);
    expect(status, GlobalHotkeyStatus.unsupported);
    expect(real.message, contains('不支持'));
  });

  test('window activation 可注入并执行', () async {
    var called = 0;
    GlobalHotkeyService.debugActivateWindow = () async => called++;
    await service.activateWindow();
    expect(called, 1);
  });
}

Future<void> _noop() async {}
