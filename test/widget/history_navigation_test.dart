/// 复查编辑导航回归：
/// - 只有「‹ 返回工作台」进入工作台；
/// - 点击左侧菜单或底部「返回历史记录」均不得新增 tab。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/app.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';

import '../fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState? previous;

  setUp(() async {
    previous?.dispose();
    final state = await makeTestAppState(llm: FakeLlmClient());
    previous = state;
    appState = state;
    await state.storage.saveRecord(OptimizeRecord(
      id: 'r1',
      scene: 'ai_coding',
      mode: OptimizeMode.quick,
      rawText: '历史原文',
      versions: [
        OptimizeVersion(
          v: 1,
          result: OptimizeResult.unstructured('历史优化结果'),
        ),
      ],
      providers: const [],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
  });

  testWidgets('左侧菜单与返回历史记录均不新增 tab', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PromptOptimizerApp());
    await tester.pumpAndSettle();

    int tabCount() => appState.tabs.tabs.length;
    expect(tabCount(), 1);

    // 左侧进入历史：不新增
    await tester.tap(find.text('历史记录').first);
    await tester.pumpAndSettle();
    expect(tabCount(), 1);

    // 打开记录进入复查编辑：新增一个 tab 承载该记录
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tabCount(), 2);
    expect(find.text('返回历史记录'), findsOneWidget);
    expect(find.text('一键复制'), findsOneWidget);

    // 左上角返回工作台：不新增
    await tester.tap(find.text('‹ 返回工作台'));
    await tester.pumpAndSettle();
    expect(tabCount(), 2);

    // 左侧菜单回工作台/历史：均不新增
    await tester.tap(find.text('优化工作台').first);
    await tester.pumpAndSettle();
    expect(tabCount(), 2);
    await tester.tap(find.text('历史记录').first);
    await tester.pumpAndSettle();
    expect(tabCount(), 2);

    // 再次打开进入复查编辑
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tabCount(), 3);

    // 底部返回历史记录：不新增
    await tester.tap(find.text('返回历史记录'));
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(tabCount(), 3);
  });
}
