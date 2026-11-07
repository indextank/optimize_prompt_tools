/// 复查清单交互与版本生成规则回归测试。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/review_edit_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

OptimizeRecord structuredRecord({bool emptyDiagnosis = false, bool withEmptyItem = false}) {
  return OptimizeRecord(
    id: 'r1',
    scene: 'ai_coding',
    mode: OptimizeMode.deep,
    rawText: '原始输入',
    versions: [
      OptimizeVersion(
        v: 1,
        result: OptimizeResult(
          role: '资深 Python 工程师',
          goal: '抓取豆瓣 Top250',
          requirements: withEmptyItem ? ['', '自动分页'] : ['自动分页'],
          diagnosis: emptyDiagnosis
              ? const []
              : const [
                  DiagnosisItem(
                      item: '角色定位', status: 'fixed', before: '未指定角色', action: '已补充'),
                  DiagnosisItem(
                      item: '验收标准', status: 'need_confirm', before: '缺少验收', action: '需补充'),
                ],
        ),
      ),
    ],
    providers: const [],
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState? previous;

  setUp(() async {
    previous?.dispose();
    final state = await makeTestAppState(llm: FakeLlmClient());
    previous = state;
    appState = state;
  });

  Future<void> pumpPage(WidgetTester tester, OptimizeRecord record) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await appState.openRecord(record);
    await tester.pumpWidget(wrapWithFluentApp(const ReviewEditPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('无手动编辑返回工作台不生成新版本（含空条目清理差异）', (tester) async {
    final record = structuredRecord(withEmptyItem: true);
    await pumpPage(tester, record);
    expect(record.versions, hasLength(1));

    await tester.tap(find.text('‹ 返回工作台'));
    await tester.pumpAndSettle();
    expect(appState.session.currentRecord!.versions, hasLength(1),
        reason: '仅程序化清理/格式化不得生成新版本');
  });

  testWidgets('单条诊断可切换已修复并产生新版本', (tester) async {
    final record = structuredRecord();
    await pumpPage(tester, record);

    expect(find.byTooltip('标记为已修复'), findsOneWidget);
    await tester.tap(find.byTooltip('标记为已修复'));
    await tester.pumpAndSettle();

    final latest = appState.session.currentRecord!.latest;
    expect(latest.v, 2);
    expect(latest.result.diagnosis[1].isFixed, isTrue);
    expect(latest.edited, isTrue);
  });

  testWidgets('一键全部标记已修复，清单计数同步', (tester) async {
    final record = structuredRecord();
    await pumpPage(tester, record);

    await tester.tap(find.text('全部已修复'));
    await tester.pumpAndSettle();

    final latest = appState.session.currentRecord!.latest;
    expect(latest.v, 2);
    expect(latest.result.diagnosis.every((d) => d.isFixed), isTrue);
    expect(find.textContaining('2 项已修复'), findsOneWidget);
    expect(find.textContaining('0 项待确认'), findsOneWidget);
  });

  testWidgets('无诊断时展示空提示，不显示全部修复按钮', (tester) async {
    await pumpPage(tester, structuredRecord(emptyDiagnosis: true));
    expect(find.textContaining('无诊断数据'), findsOneWidget);
    expect(find.text('全部已修复'), findsNothing);
    expect(find.text('0 项诊断 · 0 项已修复 · 0 项待确认'), findsOneWidget);
  });
}
