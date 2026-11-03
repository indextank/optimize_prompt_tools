/// native 平台全局热键实现：hotkey_manager 注册 + window_manager 窗口激活。
library;

import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/shortcuts.dart';
import 'global_hotkey_backend_base.dart';

GlobalHotkeyBackend createGlobalHotkeyBackend() => HotkeyManagerBackend();

class HotkeyManagerBackend implements GlobalHotkeyBackend {
  HotKey? _hotKey;

  @override
  Future<void> register(ShortcutBinding binding, void Function() onPressed) async {
    await unregister();
    final hotKey = HotKey(
      key: binding.key,
      modifiers: binding.modifiers.map(_toModifier).toList(growable: false),
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(hotKey, keyDownHandler: (_) => onPressed());
    _hotKey = hotKey;
  }

  @override
  Future<void> unregister() async {
    final hotKey = _hotKey;
    _hotKey = null;
    if (hotKey != null) {
      try {
        await hotKeyManager.unregister(hotKey);
      } catch (_) {
        // 卸载失败不应阻塞后续重绑；下次注册会再次覆盖。
      }
    }
  }

  @override
  Future<void> activateWindow() async {
    try {
      final window = WindowManager.instance.getCurrent();
      if (window == null) return;
      if (window.isMinimized) window.restore();
      window.show();
      window.focus();
    } catch (_) {
      // 窗口尚未就绪/平台未初始化时静默忽略，下次按键仍会重试。
    }
  }

  HotKeyModifier _toModifier(ShortcutModifier modifier) => switch (modifier) {
        ShortcutModifier.control => HotKeyModifier.control,
        ShortcutModifier.alt => HotKeyModifier.alt,
        ShortcutModifier.shift => HotKeyModifier.shift,
        ShortcutModifier.meta => HotKeyModifier.meta,
      };
}
