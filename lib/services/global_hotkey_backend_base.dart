/// 全局热键后端接口（与平台实现解耦，便于测试与 Web 编译）。
library;

import '../core/shortcuts.dart';

abstract class GlobalHotkeyBackend {
  Future<void> register(ShortcutBinding binding, void Function() onPressed);

  Future<void> unregister();

  /// 将应用窗口恢复/前置；不支持的平台为空实现。
  Future<void> activateWindow();
}
