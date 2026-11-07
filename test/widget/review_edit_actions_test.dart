/// 复查编辑页底部操作：返回历史记录、一键复制、复制失败重试。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/review_edit_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState? previous;
  String? clipboardText;
  bool failClipboard = false;

  setUp(() async {
    previous?.dispose();
    final state = await makeTestAppState(llm: FakeLlmClient());
    previous = state;
    appState = state;
    clipboardText = null;
    failClipboard = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (failClipboard) {
          throw PlatformException(code: 'clipboard-error', message: 'copy failed');
        }
        clipboardText = call.arguments['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final record = OptimizeRecord(
      id: 'r1',
      scene: 'ai_coding',
      mode: OptimizeMode.quick,
      rawText: '原始输入',
      versions: [
        OptimizeVersion(
          v: 1,
          result: OptimizeResult.unstructured('当前优化结果内容'),
        ),
      ],
      providers: const [],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await appState.openRecord(record);

    await tester.pumpWidget(wrapWithFluentApp(const ReviewEditPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('底栏提供返回历史记录与一键复制', (tester) async {
    await pumpPage(tester);
    expect(find.text('返回历史记录'), findsOneWidget);
    expect(find.text('导出 Markdown'), findsOneWidget);
    expect(find.text('一键复制'), findsOneWidget);
    // 顶部「返回工作台」保持原状
    expect(find.text('‹ 返回工作台'), findsOneWidget);
  });

  testWidgets('复制内容与当前优化结果完全一致，并给出成功反馈', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('一键复制'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // InfoBar 入场

    expect(clipboardText, '当前优化结果内容');
    expect(find.text('已复制优化结果'), findsOneWidget);

    // 排空 InfoBar 定时器
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('复制失败显示错误并可重试，重试后内容一致', (tester) async {
    await pumpPage(tester);
    failClipboard = true;
    await tester.tap(find.text('一键复制'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(clipboardText, isNull);
    expect(find.text('复制失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    failClipboard = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(clipboardText, '当前优化结果内容');
    expect(find.text('已复制优化结果'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
