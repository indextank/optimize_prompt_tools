/// 全局唤起热键：真实系统级注册 + 窗口激活，并提供可注入后端用于测试。
///
/// 历史问题：设置里只存了 `hotkey` 字符串并展示，代码从未调用任何注册 API，
/// 因此默认 `Ctrl+Shift+Space` 完全不生效。本服务统一负责：
/// 1) 解析/校验组合（[ShortcutBinding]）；
/// 2) 通过平台后端注册系统级热键（Web 为空实现）；
/// 3) 触发时把应用窗口恢复/前置；
/// 4) 冲突/不支持时给出可展示状态，而不是静默失败。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/shortcuts.dart';
import 'global_hotkey_backend.dart';
import 'global_hotkey_backend_base.dart';

export 'global_hotkey_backend_base.dart' show GlobalHotkeyBackend;

/// 全局热键当前状态。
enum GlobalHotkeyStatus {
  /// 尚未注册。
  idle,

  /// 已成功注册。
  registered,

  /// 当前平台不支持系统级热键（Web / Android / iOS）。
  unsupported,

  /// 配置文本非法。
  invalid,

  /// 注册失败（通常被其他应用占用或系统保留）。
  conflict,
}

/// 全局热键服务（单例 + 可注入后端）。
class GlobalHotkeyService extends ChangeNotifier {
  GlobalHotkeyService({GlobalHotkeyBackend? backend})
      : _backend = backend ?? createGlobalHotkeyBackend(),
        _injectedBackend = backend != null;

  /// 应用运行的共享实例；测试可替换。
  static GlobalHotkeyService instance = GlobalHotkeyService();

  /// 测试注入：替换窗口激活实现，避免依赖真实桌面窗口。
  @visibleForTesting
  static Future<void> Function()? debugActivateWindow;

  final GlobalHotkeyBackend _backend;
  final bool _injectedBackend;

  GlobalHotkeyStatus _status = GlobalHotkeyStatus.idle;
  String _message = '';
  ShortcutBinding? _bound;

  GlobalHotkeyStatus get status => _status;
  String get message => _message;
  String? get boundLabel => _bound?.label;

  /// 平台是否支持系统级热键（桌面三端）。
  bool get _platformSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// 注册（并替换旧的）全局热键。返回最终状态，不向调用方抛异常。
  Future<GlobalHotkeyStatus> bind(
    String raw, {
    required Future<void> Function() onActivate,
  }) async {
    await unbind();
    final binding = ShortcutBinding.tryParse(raw);
    if (binding == null || !binding.hasModifier) {
      _set(GlobalHotkeyStatus.invalid, '快捷键格式无效或缺少修饰键');
      return _status;
    }
    if (!_platformSupported && !_injectedBackend) {
      _set(GlobalHotkeyStatus.unsupported, '当前平台不支持系统级热键');
      return _status;
    }
    try {
      await _backend.register(binding, () {
        unawaited(onActivate());
      });
      _bound = binding;
      _set(GlobalHotkeyStatus.registered, '已生效：${binding.label}');
    } on PlatformException catch (e) {
      _set(GlobalHotkeyStatus.conflict,
          e.message ?? '注册失败：快捷键可能已被其他应用占用');
    } catch (_) {
      _set(GlobalHotkeyStatus.conflict, '注册失败：快捷键可能已被其他应用占用');
    }
    return _status;
  }

  /// 解除当前全局热键（幂等）。
  Future<void> unbind() async {
    _bound = null;
    try {
      await _backend.unregister();
    } catch (_) {
      // 忽略卸载异常：不阻塞设置变更。
    }
    if (_status != GlobalHotkeyStatus.idle) {
      _set(GlobalHotkeyStatus.idle, '');
    }
  }

  /// 将应用窗口恢复到前台并聚焦。
  Future<void> activateWindow() async {
    final override = debugActivateWindow;
    if (override != null) {
      await override();
      return;
    }
    if (!_platformSupported) return;
    await _backend.activateWindow();
  }

  void _set(GlobalHotkeyStatus status, String message) {
    _status = status;
    _message = message;
    notifyListeners();
  }
}
