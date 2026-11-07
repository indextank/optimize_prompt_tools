/// 「全部模型」只展示当前历史中实际使用过的服务商。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/history_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

OptimizeRecord rec(String id, String serviceId) => OptimizeRecord(
      id: id,
      scene: 'ai_coding',
      mode: OptimizeMode.deep,
      rawText: '记录-$id',
      versions: [
        OptimizeVersion(v: 1, result: OptimizeResult.unstructured('结果-$id')),
      ],
      providers: [serviceId],
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState? previous;

  setUp(() async {
    previous?.dispose();
    final state = await makeTestAppState(llm: FakeLlmClient());
    previous = state;
    appState = state;
    await state.saveService(testService(), apiKey: 'sk');
    await state.saveService(
        testService(id: 'svc-kimi', provider: 'kimi', model: 'k3'),
        apiKey: 'sk2');
    await state.storage.saveRecord(rec('deepseek-r', 'svc-1'));
    await state.storage.saveRecord(rec('kimi-r', 'svc-kimi'));
  });

  testWidgets('模型下拉只展示已使用服务商，未使用的九家不列出', (tester) async {
    tester.view.physicalSize = const Size(1300, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const HistoryPage()));
    await tester.pumpAndSettle();

    // 场景框后依次是预置词、模型框
    await tester.tap(find.byType(ComboBox<String>).at(2));
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek'), findsOneWidget);
    expect(find.text('Kimi CN'), findsOneWidget);
    expect(find.text('豆包（火山方舟）'), findsNothing);
    expect(find.text('通义千问（阿里云百炼）'), findsNothing);

    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();
    expect(find.text('记录-deepseek-r'), findsOneWidget);
    expect(find.text('记录-kimi-r'), findsNothing);
  });
}
