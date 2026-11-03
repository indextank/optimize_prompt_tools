/// Web 等非 native 平台的空实现：系统级热键不可用，设置页会显示不支持。
library;

import '../core/shortcuts.dart';
import 'global_hotkey_backend_base.dart';

GlobalHotkeyBackend createGlobalHotkeyBackend() =>
    UnsupportedGlobalHotkeyBackend();

class UnsupportedGlobalHotkeyBackend implements GlobalHotkeyBackend {
  @override
  Future<void> register(ShortcutBinding binding, void Function() onPressed) async {
    throw UnsupportedError('system hotkey is unavailable on this platform');
  }

  @override
  Future<void> unregister() async {}

  @override
  Future<void> activateWindow() async {}
}
