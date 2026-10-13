/// 历史记录页 Widget 测试：列表 / 搜索 / 筛选 / 打开 / 删除。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/history_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    appState = await makeTestAppState(llm: FakeLlmClient());
  });

  Future<void> seed() async {
    // 真实场景：先配置服务，记录 providers 存服务 id（与生产落库一致）
    await appState.saveService(
        testService(id: 'svc-ds', provider: 'deepseek', model: 'deepseek-flash'),
        apiKey: 'sk');
    await appState.saveService(
        testService(id: 'svc-kimi', provider: 'kimi', model: 'k3'),
        apiKey: 'sk2');
    final storage = appState.storage;
    await storage.saveRecord(OptimizeRecord(
      id: 'r1',
      scene: 'ai_coding',
      mode: OptimizeMode.deep,
      rawText: '帮我写个爬虫',
      versions: [
        OptimizeVersion(v: 1, result: const OptimizeResult(role: '工程师'))
      ],
      providers: const ['svc-ds'],
      scoreBefore: 62,
      scoreAfter: 92,
      createdAt: 1759700000,
    ));
    await storage.saveRecord(OptimizeRecord(
      id: 'r2',
      scene: 'writing',
      mode: OptimizeMode.quick,
      rawText: '写一首关于秋天的诗',
      versions: [
        OptimizeVersion(v: 1, result: const OptimizeResult(role: '诗人'))
      ],
      providers: const ['svc-kimi'],
      createdAt: 1759700100,
    ));
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const HistoryPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('空列表提示', (tester) async {
    await pumpPage(tester);
    expect(find.text('暂无历史记录'), findsOneWidget);
  });

  testWidgets('记录渲染：原文/场景/模式/评分', (tester) async {
    await seed();
    await pumpPage(tester);
    expect(find.text('帮我写个爬虫'), findsOneWidget);
    expect(find.text('写一首关于秋天的诗'), findsOneWidget);
    expect(find.textContaining('AI 编程'), findsOneWidget);
    expect(find.textContaining('深度优化'), findsOneWidget);
    expect(find.text('92'), findsOneWidget);
  });

  testWidgets('关键字搜索过滤', (tester) async {
    await seed();
    await pumpPage(tester);
    await tester.enterText(find.byType(TextBox).first, '爬虫');
    await tester.pumpAndSettle();
    expect(find.text('帮我写个爬虫'), findsOneWidget);
    expect(find.text('写一首关于秋天的诗'), findsNothing);
  });

  testWidgets('场景筛选', (tester) async {
    await seed();
    await pumpPage(tester);
    await tester.tap(find.byType(ComboBox<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('文案写作').last);
    await tester.pumpAndSettle();
    expect(find.text('写一首关于秋天的诗'), findsOneWidget);
    expect(find.text('帮我写个爬虫'), findsNothing);
  });

  testWidgets('模型筛选：按提供商类型正确筛出对应记录（筛选 bug 回归）', (tester) async {
    await seed();
    await pumpPage(tester);
    // 选「Kimi CN」——记录 providers 存服务 id 'svc-kimi'，需反查匹配
    await tester.tap(find.byType(ComboBox<String>).at(1)); // 场景框之后是模型框
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kimi CN').last);
    await tester.pumpAndSettle();
    expect(find.text('写一首关于秋天的诗'), findsOneWidget, reason: 'Kimi 记录应被筛出');
    expect(find.text('帮我写个爬虫'), findsNothing, reason: 'DeepSeek 记录应被过滤');
    // 切回全部模型：两条都回来
    await tester.tap(find.byType(ComboBox<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部模型').last);
    await tester.pumpAndSettle();
    expect(find.text('帮我写个爬虫'), findsOneWidget);
    expect(find.text('写一首关于秋天的诗'), findsOneWidget);
  });

  testWidgets('标题与描述已移除，筛选区左对齐', (tester) async {
    await pumpPage(tester);
    expect(find.text('历史记录'), findsNothing, reason: '页面标题应已移除');
    expect(find.textContaining('留存版本链'), findsNothing, reason: '描述文案应已移除');
    // 搜索框左缘贴近页面左 padding（26）
    final searchBox = tester.getRect(find.byType(TextBox).first);
    expect(searchBox.left, lessThanOrEqualTo(30), reason: '搜索筛选区应直接左对齐');
  });

  testWidgets('清空所有：二次确认弹框，取消保留、确认清空', (tester) async {
    await seed();
    await pumpPage(tester);
    // 按钮位于筛选区最右侧（模型下拉右边，贴近页面右缘）
    final btn = find.text('🗑 清空所有');
    expect(btn, findsOneWidget);
    final btnRect = tester.getRect(btn);
    final comboRect = tester.getRect(find.byType(ComboBox<String>).at(1));
    expect(btnRect.left, greaterThan(comboRect.right), reason: '清空所有应在筛选控件右侧');
    expect(1440 - btnRect.right, lessThanOrEqualTo(40), reason: '应贴近页面右缘');

    // 点击 → 弹框（含条数与不可恢复说明）
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.text('清空历史记录'), findsOneWidget);
    expect(find.textContaining('全部 2 条'), findsOneWidget);

    // 取消 → 记录保留
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await appState.storage.recordCount(), 2);
    expect(find.text('帮我写个爬虫'), findsOneWidget);

    // 再次点击 → 确认清空 → 全空
    await tester.tap(btn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(await appState.storage.recordCount(), 0);
    expect(find.text('暂无历史记录'), findsOneWidget);
  });

  testWidgets('删除记录', (tester) async {
    await seed();
    await pumpPage(tester);
    expect(find.byType(Card), findsNWidgets(2));
    await tester.tap(find.byIcon(FluentIcons.delete).first);
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    expect(await appState.storage.recordCount(), 1);
  });

  testWidgets('打开记录回填会话', (tester) async {
    await seed();
    await pumpPage(tester);
    await tester.tap(find.text('打开').first);
    await tester.pumpAndSettle();
    expect(appState.session.currentRecord, isNotNull);
    expect(appState.session.rawText, isNotEmpty);
  });
}
