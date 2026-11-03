/// 快捷键模型：字符串 ↔ 修饰键 + 主键 的严格解析与匹配。
///
/// 统一规范（持久化 / 展示 / 全局注册共用同一字符串）：
/// - 修饰键固定顺序：`Ctrl` → `Alt` → `Shift` → `Meta`
/// - 主键为字母/数字/F1-F12/空格/回车等；特殊键用可读名称（如 `PageUp`）
/// - 例：`Ctrl+Shift+Space`、`Ctrl+Enter`、`Alt+W`
///
/// 解析失败返回 `null`，由调用方决定提示文案；不在解析器里抛异常。
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart';

/// 固定标签快捷键（不提供修改，避免与可配置快捷键冲突）。
const String kCloseTabShortcut = 'Ctrl+W';
const String kNewTabShortcut = 'Ctrl+T';

/// 支持的修饰键。
enum ShortcutModifier {
  control('Ctrl'),
  alt('Alt'),
  shift('Shift'),
  meta('Meta');

  const ShortcutModifier(this.label);

  /// 持久化 / 展示用标签。
  final String label;
}

/// 一个按键定义：持久化 token、展示文本、Flutter 逻辑键。
@immutable
class ShortcutKeyDef {
  const ShortcutKeyDef(this.token, this.display, this.key);

  final String token;
  final String display;
  final LogicalKeyboardKey key;
}

/// 支持的按键集合（token 不区分大小写；特殊键使用可读名称）。
const List<ShortcutKeyDef> kShortcutKeys = [
  ShortcutKeyDef('A', 'A', LogicalKeyboardKey.keyA),
  ShortcutKeyDef('B', 'B', LogicalKeyboardKey.keyB),
  ShortcutKeyDef('C', 'C', LogicalKeyboardKey.keyC),
  ShortcutKeyDef('D', 'D', LogicalKeyboardKey.keyD),
  ShortcutKeyDef('E', 'E', LogicalKeyboardKey.keyE),
  ShortcutKeyDef('F', 'F', LogicalKeyboardKey.keyF),
  ShortcutKeyDef('G', 'G', LogicalKeyboardKey.keyG),
  ShortcutKeyDef('H', 'H', LogicalKeyboardKey.keyH),
  ShortcutKeyDef('I', 'I', LogicalKeyboardKey.keyI),
  ShortcutKeyDef('J', 'J', LogicalKeyboardKey.keyJ),
  ShortcutKeyDef('K', 'K', LogicalKeyboardKey.keyK),
  ShortcutKeyDef('L', 'L', LogicalKeyboardKey.keyL),
  ShortcutKeyDef('M', 'M', LogicalKeyboardKey.keyM),
  ShortcutKeyDef('N', 'N', LogicalKeyboardKey.keyN),
  ShortcutKeyDef('O', 'O', LogicalKeyboardKey.keyO),
  ShortcutKeyDef('P', 'P', LogicalKeyboardKey.keyP),
  ShortcutKeyDef('Q', 'Q', LogicalKeyboardKey.keyQ),
  ShortcutKeyDef('R', 'R', LogicalKeyboardKey.keyR),
  ShortcutKeyDef('S', 'S', LogicalKeyboardKey.keyS),
  ShortcutKeyDef('T', 'T', LogicalKeyboardKey.keyT),
  ShortcutKeyDef('U', 'U', LogicalKeyboardKey.keyU),
  ShortcutKeyDef('V', 'V', LogicalKeyboardKey.keyV),
  ShortcutKeyDef('W', 'W', LogicalKeyboardKey.keyW),
  ShortcutKeyDef('X', 'X', LogicalKeyboardKey.keyX),
  ShortcutKeyDef('Y', 'Y', LogicalKeyboardKey.keyY),
  ShortcutKeyDef('Z', 'Z', LogicalKeyboardKey.keyZ),
  ShortcutKeyDef('0', '0', LogicalKeyboardKey.digit0),
  ShortcutKeyDef('1', '1', LogicalKeyboardKey.digit1),
  ShortcutKeyDef('2', '2', LogicalKeyboardKey.digit2),
  ShortcutKeyDef('3', '3', LogicalKeyboardKey.digit3),
  ShortcutKeyDef('4', '4', LogicalKeyboardKey.digit4),
  ShortcutKeyDef('5', '5', LogicalKeyboardKey.digit5),
  ShortcutKeyDef('6', '6', LogicalKeyboardKey.digit6),
  ShortcutKeyDef('7', '7', LogicalKeyboardKey.digit7),
  ShortcutKeyDef('8', '8', LogicalKeyboardKey.digit8),
  ShortcutKeyDef('9', '9', LogicalKeyboardKey.digit9),
  ShortcutKeyDef('F1', 'F1', LogicalKeyboardKey.f1),
  ShortcutKeyDef('F2', 'F2', LogicalKeyboardKey.f2),
  ShortcutKeyDef('F3', 'F3', LogicalKeyboardKey.f3),
  ShortcutKeyDef('F4', 'F4', LogicalKeyboardKey.f4),
  ShortcutKeyDef('F5', 'F5', LogicalKeyboardKey.f5),
  ShortcutKeyDef('F6', 'F6', LogicalKeyboardKey.f6),
  ShortcutKeyDef('F7', 'F7', LogicalKeyboardKey.f7),
  ShortcutKeyDef('F8', 'F8', LogicalKeyboardKey.f8),
  ShortcutKeyDef('F9', 'F9', LogicalKeyboardKey.f9),
  ShortcutKeyDef('F10', 'F10', LogicalKeyboardKey.f10),
  ShortcutKeyDef('F11', 'F11', LogicalKeyboardKey.f11),
  ShortcutKeyDef('F12', 'F12', LogicalKeyboardKey.f12),
  ShortcutKeyDef('Space', 'Space', LogicalKeyboardKey.space),
  ShortcutKeyDef('Enter', 'Enter', LogicalKeyboardKey.enter),
  ShortcutKeyDef('Escape', 'Escape', LogicalKeyboardKey.escape),
  ShortcutKeyDef('Tab', 'Tab', LogicalKeyboardKey.tab),
  ShortcutKeyDef('Backspace', 'Backspace', LogicalKeyboardKey.backspace),
  ShortcutKeyDef('Delete', 'Delete', LogicalKeyboardKey.delete),
  ShortcutKeyDef('Insert', 'Insert', LogicalKeyboardKey.insert),
  ShortcutKeyDef('Home', 'Home', LogicalKeyboardKey.home),
  ShortcutKeyDef('End', 'End', LogicalKeyboardKey.end),
  ShortcutKeyDef('PageUp', 'PageUp', LogicalKeyboardKey.pageUp),
  ShortcutKeyDef('PageDown', 'PageDown', LogicalKeyboardKey.pageDown),
  ShortcutKeyDef('ArrowUp', '↑', LogicalKeyboardKey.arrowUp),
  ShortcutKeyDef('ArrowDown', '↓', LogicalKeyboardKey.arrowDown),
  ShortcutKeyDef('ArrowLeft', '←', LogicalKeyboardKey.arrowLeft),
  ShortcutKeyDef('ArrowRight', '→', LogicalKeyboardKey.arrowRight),
  ShortcutKeyDef('Minus', 'Minus', LogicalKeyboardKey.minus),
  ShortcutKeyDef('Equal', 'Equal', LogicalKeyboardKey.equal),
  ShortcutKeyDef('BracketLeft', '[', LogicalKeyboardKey.bracketLeft),
  ShortcutKeyDef('BracketRight', ']', LogicalKeyboardKey.bracketRight),
  ShortcutKeyDef('Backslash', r'\', LogicalKeyboardKey.backslash),
  ShortcutKeyDef('Semicolon', ';', LogicalKeyboardKey.semicolon),
  ShortcutKeyDef('Quote', "'", LogicalKeyboardKey.quote),
  ShortcutKeyDef('Comma', ',', LogicalKeyboardKey.comma),
  ShortcutKeyDef('Period', '.', LogicalKeyboardKey.period),
  ShortcutKeyDef('Slash', '/', LogicalKeyboardKey.slash),
  ShortcutKeyDef('Backquote', '`', LogicalKeyboardKey.backquote),
];

final Map<String, ShortcutKeyDef> _keyByToken = {
  for (final def in kShortcutKeys) _normalizeKey(def.token): def,
};

final Map<int, ShortcutKeyDef> _keyByLogicalId = {
  for (final def in kShortcutKeys) def.key.keyId: def,
};

String _normalizeKey(String value) =>
    value.trim().toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');

const _modifierAliases = <String, ShortcutModifier>{
  'CTRL': ShortcutModifier.control,
  'CONTROL': ShortcutModifier.control,
  'ALT': ShortcutModifier.alt,
  'OPTION': ShortcutModifier.alt,
  'SHIFT': ShortcutModifier.shift,
  'META': ShortcutModifier.meta,
  'CMD': ShortcutModifier.meta,
  'COMMAND': ShortcutModifier.meta,
  'WIN': ShortcutModifier.meta,
  'SUPER': ShortcutModifier.meta,
};

/// 一个可持久化的快捷键组合。
@immutable
class ShortcutBinding {
  const ShortcutBinding({
    required this.modifiers,
    required this.keyDef,
  });

  final Set<ShortcutModifier> modifiers;
  final ShortcutKeyDef keyDef;

  LogicalKeyboardKey get key => keyDef.key;

  /// 是否包含至少一个修饰键（应用级/全局快捷键的最低要求）。
  bool get hasModifier => modifiers.isNotEmpty;

  /// 标准化文本，如 `Ctrl+Shift+Space`。
  String get label {
    final ordered = ShortcutModifier.values.where(modifiers.contains);
    return [...ordered.map((m) => m.label), keyDef.token].join('+');
  }

  /// 解析用户输入/配置文本；非法返回 `null`。
  ///
  /// 允许修饰键别名（Control/Option/Cmd/Win/Super），键名不区分大小写，
  /// 允许 `Page Up` 之类带空格的写法。
  static ShortcutBinding? tryParse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final parts = text.split('+').map((e) => e.trim()).toList();
    if (parts.isEmpty) return null;
    final keyToken = _normalizeKey(parts.last);
    final keyDef = _keyByToken[keyToken];
    if (keyDef == null) return null;

    final modifiers = <ShortcutModifier>{};
    for (final part in parts.take(parts.length - 1)) {
      final modifier = _modifierAliases[part.toUpperCase()];
      if (modifier == null) return null;
      if (!modifiers.add(modifier)) return null;
    }
    return ShortcutBinding(modifiers: modifiers, keyDef: keyDef);
  }

  /// 从键盘事件记录组合；只接受已支持的键，修饰键本身不构成组合。
  static ShortcutBinding? fromKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent) return null;
    final def = _keyByLogicalId[event.logicalKey.keyId];
    if (def == null) return null;
    final hardware = HardwareKeyboard.instance;
    final modifiers = <ShortcutModifier>{
      if (hardware.isControlPressed) ShortcutModifier.control,
      if (hardware.isAltPressed) ShortcutModifier.alt,
      if (hardware.isShiftPressed) ShortcutModifier.shift,
      if (hardware.isMetaPressed) ShortcutModifier.meta,
    };
    return ShortcutBinding(modifiers: modifiers, keyDef: def);
  }

  /// 事件是否精确匹配当前组合（修饰键必须完全一致，忽略按键重复）。
  bool matches(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey.keyId != key.keyId) return false;
    final hardware = HardwareKeyboard.instance;
    return hardware.isControlPressed ==
            modifiers.contains(ShortcutModifier.control) &&
        hardware.isAltPressed == modifiers.contains(ShortcutModifier.alt) &&
        hardware.isShiftPressed == modifiers.contains(ShortcutModifier.shift) &&
        hardware.isMetaPressed == modifiers.contains(ShortcutModifier.meta);
  }

  @override
  bool operator ==(Object other) =>
      other is ShortcutBinding &&
      other.key.keyId == key.keyId &&
      other.modifiers.length == modifiers.length &&
      other.modifiers.containsAll(modifiers);

  @override
  int get hashCode => Object.hash(
        key.keyId,
        Object.hashAllUnordered(modifiers),
      );
}

/// 校验快捷键文本：格式合法且至少包含一个修饰键；返回错误文案或 `null`。
String? validateShortcutText(String raw, {String field = '快捷键'}) {
  final binding = ShortcutBinding.tryParse(raw);
  if (binding == null) return '$field格式无效（示例：Ctrl+Shift+Space）';
  if (!binding.hasModifier) return '$field需包含 Ctrl/Alt/Shift/Meta 至少一个修饰键';
  return null;
}
