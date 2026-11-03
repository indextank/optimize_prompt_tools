/// 快捷键录制控件：点击后直接按下组合键完成录入。
///
/// 规则：
/// - 必须包含 Ctrl/Alt/Shift/Meta 至少一个修饰键（避免抢占普通输入）；
/// - 单独按修饰键不会结束录制；
/// - Escape 取消，非法按键给出就地提示。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../core/shortcuts.dart';
import '../theme.dart';

class ShortcutRecorder extends StatefulWidget {
  const ShortcutRecorder({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<ShortcutRecorder> createState() => _ShortcutRecorderState();
}

class _ShortcutRecorderState extends State<ShortcutRecorder> {
  bool _recording = false;
  String? _hint;

  @override
  void dispose() {
    if (_recording) {
      HardwareKeyboard.instance.removeHandler(_handleKey);
    }
    super.dispose();
  }

  void _start() {
    if (!widget.enabled) return;
    setState(() {
      _recording = true;
      _hint = null;
    });
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  void _stop() {
    if (!_recording) return;
    HardwareKeyboard.instance.removeHandler(_handleKey);
    setState(() {
      _recording = false;
    });
  }

  bool _handleKey(KeyEvent event) {
    if (!_recording || event is KeyUpEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _stop();
      return true;
    }
    // 单独按下修饰键时继续等待主键。
    if (_isModifier(event.logicalKey)) return false;

    final binding = ShortcutBinding.fromKeyEvent(event);
    if (binding == null) {
      setState(() => _hint = '不支持该按键，请换一个');
      return true;
    }
    if (!binding.hasModifier) {
      setState(() => _hint = '需包含 Ctrl / Alt / Shift / Meta 至少一个修饰键');
      return true;
    }
    _stop();
    widget.onChanged(binding.label);
    return true;
  }

  static final Set<LogicalKeyboardKey> _modifierKeys = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
  };

  bool _isModifier(LogicalKeyboardKey key) => _modifierKeys.contains(key);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shown = _recording ? '请按下组合键…' : widget.value;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _recording ? colors.accentSubtle : colors.surfaceSubtle,
            border: Border.all(
                color: _recording ? colors.accent : colors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            shown,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _recording ? colors.accentText : colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Button(
          onPressed: widget.enabled
              ? (_recording ? _stop : _start)
              : null,
          child: Text(_recording ? '取消' : '更改',
              style: const TextStyle(fontSize: 12)),
        ),
      ]),
      if (_hint != null) ...[
        const SizedBox(height: 4),
        Text(_hint!,
            style: TextStyle(fontSize: 11, color: context.colors.danger)),
      ],
    ]);
  }
}
