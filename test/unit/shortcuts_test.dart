/// 快捷键模型单测：解析/标准化/别名/非法输入/事件匹配。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/shortcuts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('解析与标准化', () {
    test('标准组合解析并按固定顺序输出', () {
      final b = ShortcutBinding.tryParse('Ctrl+Shift+Space')!;
      expect(b.modifiers, {ShortcutModifier.control, ShortcutModifier.shift});
      expect(b.key, LogicalKeyboardKey.space);
      expect(b.label, 'Ctrl+Shift+Space');
    });

    test('大小写/空格/别名归一化', () {
      expect(ShortcutBinding.tryParse(' shift + control + space ')!.label,
          'Ctrl+Shift+Space');
      expect(ShortcutBinding.tryParse('control+alt+w')!.label, 'Ctrl+Alt+W');
      expect(ShortcutBinding.tryParse('Win+K')!.label, 'Meta+K');
      expect(ShortcutBinding.tryParse('Cmd+Enter')!.label, 'Meta+Enter');
      expect(ShortcutBinding.tryParse('Alt+Page Up')!.label, 'Alt+PageUp');
    });

    test('主键与标点符号', () {
      expect(ShortcutBinding.tryParse('Ctrl+1')!.key, LogicalKeyboardKey.digit1);
      expect(ShortcutBinding.tryParse('Ctrl+F12')!.key, LogicalKeyboardKey.f12);
      expect(ShortcutBinding.tryParse('Ctrl+BracketLeft')!.label,
          'Ctrl+BracketLeft');
      expect(ShortcutBinding.tryParse('Ctrl+Slash')!.key,
          LogicalKeyboardKey.slash);
    });

    test('非法输入返回 null', () {
      for (final raw in [
        '',
        '   ',
        'Ctrl',
        'Ctrl+',
        'Ctrl+Unknown',
        'Ctrl+Ctrl+W',
        'Hyper+W',
        'Ctrl+Shift',
        'Ctrl+Page Up Extra',
      ]) {
        expect(ShortcutBinding.tryParse(raw), isNull, reason: raw);
      }
    });

    test('校验要求至少一个修饰键', () {
      expect(validateShortcutText('F5'), contains('修饰键'));
      expect(validateShortcutText('Ctrl+F5'), isNull);
      expect(validateShortcutText('bad'), contains('格式无效'));
    });

    test('相等性按修饰键集合与主键比较', () {
      expect(ShortcutBinding.tryParse('Ctrl+Shift+W'),
          ShortcutBinding.tryParse('Shift+Ctrl+W'));
      expect(ShortcutBinding.tryParse('Ctrl+W'),
          isNot(ShortcutBinding.tryParse('Ctrl+Shift+W')));
    });
  });

  group('键盘事件', () {
    testWidgets('精确匹配修饰键，释放后不匹配', (tester) async {
      final binding = ShortcutBinding.tryParse('Ctrl+Shift+Space')!;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.space,
        logicalKey: LogicalKeyboardKey.space,
        timeStamp: Duration.zero,
        character: ' ',
      );
      expect(binding.matches(event), isTrue);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(binding.matches(event), isFalse);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(binding.matches(event), isFalse);
    });

    testWidgets('从事件记录组合', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyW,
        logicalKey: LogicalKeyboardKey.keyW,
        timeStamp: Duration.zero,
        character: 'w',
      );
      final recorded = ShortcutBinding.fromKeyEvent(event);
      expect(recorded?.label, 'Ctrl+W');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('修饰键本身不构成组合', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.controlLeft,
        logicalKey: LogicalKeyboardKey.controlLeft,
        timeStamp: Duration.zero,
      );
      expect(ShortcutBinding.fromKeyEvent(event), isNull);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });
  });
}
