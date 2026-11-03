/// 快捷键录制控件测试：录制成功/取消/仅修饰键/无修饰键提示。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/ui/widgets/shortcut_recorder.dart';

import '../widget_test_helper.dart';

void main() {
  String? recorded;

  Widget build(String value) => wrapWithFluentApp(
        Center(
          child: ShortcutRecorder(
            value: value,
            onChanged: (v) => recorded = v,
          ),
        ),
      );

  setUp(() => recorded = null);

  testWidgets('录制 Ctrl+Shift+P 并标准化显示', (tester) async {
    await tester.pumpWidget(build('Ctrl+Enter'));
    await tester.tap(find.text('更改'));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
    await tester.pump();

    expect(recorded, 'Ctrl+Shift+P');
    expect(find.text('Ctrl+Enter'), findsOneWidget); // 父级负责回写 value
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('Escape 取消录制，不产生变更', (tester) async {
    await tester.pumpWidget(build('Ctrl+Enter'));
    await tester.tap(find.text('更改'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(recorded, isNull);
    expect(find.text('更改'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('仅按修饰键不结束录制', (tester) async {
    await tester.pumpWidget(build('Ctrl+Enter'));
    await tester.tap(find.text('更改'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(recorded, isNull);
    expect(find.text('请按下组合键…'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('无修饰键按键给出提示且不提交', (tester) async {
    await tester.pumpWidget(build('Ctrl+Enter'));
    await tester.tap(find.text('更改'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.pump();

    expect(recorded, isNull);
    expect(find.textContaining('需包含'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 200));
  });
}
