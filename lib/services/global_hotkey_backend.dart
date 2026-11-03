/// 根据编译目标选择全局热键后端：
/// - 桌面/移动 native（dart:io）：hotkey_manager + window_manager
/// - Web：空实现（避免引入桌面 FFI 依赖，系统级热键本身不支持）
library;

export 'global_hotkey_backend_stub.dart'
    if (dart.library.io) 'global_hotkey_backend_io.dart';
