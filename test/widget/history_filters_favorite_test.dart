/// 历史页筛选/收藏 widget 测试：
/// - 预置词下拉随场景显隐，隐藏时清空选中值；
/// - 收藏筛选与预置词/场景叠加；
/// - 爱心在浅色/深色下的图标与配色；
/// - 空态与加载错误 + 重试。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/storage/sqlite_storage.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/history_page.dart';
import 'package:prompt_optimizer/ui/theme.dart';
import 'package:sqlite3/sqlite3.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

OptimizeRecord rec(String id, {String? presetId, bool favorite = false, String scene = 'ai_coding'}) =>
    OptimizeRecord(
      id: id,
      scene: scene,
      mode: OptimizeMode.deep,
      rawText: '原始提示词-$id',
      versions: [
        OptimizeVersion(v: 1, result: OptimizeResult.unstructured('结果-$id')),
      ],
      providers: const [],
      favorite: favorite,
      presetId: presetId,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

/// 可注入首次加载失败的存储，用于错误态与重试验证。
class FlakyHistoryStorage extends SqliteStorage {
  FlakyHistoryStorage() : super(sqlite3.openInMemory());

  bool fail = true;

  @override
  Future<List<OptimizeRecord>> searchRecords({
    String keyword = '',
    String scene = '',
    String provider = '',
    String presetId = '',
    bool onlyFavorites = false,
  }) async {
    if (fail) throw Exception('disk read error');
    return super.searchRecords(
      keyword: keyword,
      scene: scene,
      provider: provider,
      presetId: presetId,
      onlyFavorites: onlyFavorites,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState? previous;

  setUp(() async {
    previous?.dispose();
    final state = await makeTestAppState(llm: FakeLlmClient());
    previous = state;
    appState = state;
    await state.savePreset(CodingPreset(
      id: 'p1',
      name: 'Vue 技术栈',
      content: 'Vue3',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
  });

  Future<void> pumpPage(WidgetTester tester, {Brightness brightness = Brightness.light}) async {
    tester.view.physicalSize = const Size(1300, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (brightness == Brightness.light) {
      await tester.pumpWidget(wrapWithFluentApp(const HistoryPage()));
    } else {
      await tester.pumpWidget(FluentApp(
        theme: buildFluentTheme(Brightness.dark),
        home: const HistoryPage(),
      ));
    }
    await tester.pumpAndSettle();
  }

  ComboBox<String> presetCombo(WidgetTester tester) =>
      tester.widget<ComboBox<String>>(
          find.byKey(const Key('history-preset-filter')));

  testWidgets('预置词下拉随场景显隐，隐藏后清空选中值', (tester) async {
    await pumpPage(tester);
    expect(find.byKey(const Key('history-preset-filter')), findsOneWidget);

    // 选中预置词
    await tester.tap(find.byKey(const Key('history-preset-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vue 技术栈').last);
    await tester.pumpAndSettle();
    expect(presetCombo(tester).value, 'p1');

    // 切到「文案写作」：隐藏且清空
    await tester.tap(find.byType(ComboBox<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('文案写作').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-preset-filter')), findsNothing);

    // 切回「全部场景」：回到未选中状态
    await tester.tap(find.byType(ComboBox<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部场景').last);
    await tester.pumpAndSettle();
    expect(presetCombo(tester).value, isEmpty);
    expect(find.text('全部预置词'), findsOneWidget);
  });

  testWidgets('预置词与只看收藏组合筛选结果正确', (tester) async {
    await appState.storage.saveRecord(rec('a', presetId: 'p1', favorite: true));
    await appState.storage.saveRecord(rec('b', presetId: 'p1'));
    await appState.storage.saveRecord(rec('c'));
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('history-preset-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vue 技术栈').last);
    await tester.pumpAndSettle();
    expect(find.text('原始提示词-a'), findsOneWidget);
    expect(find.text('原始提示词-b'), findsOneWidget);
    expect(find.text('原始提示词-c'), findsNothing);

    await tester.tap(find.text('只看收藏'));
    await tester.pumpAndSettle();
    expect(find.text('原始提示词-a'), findsOneWidget);
    expect(find.text('原始提示词-b'), findsNothing);
  });

  testWidgets('浅色：未收藏描边灰，点击后填充红并持久化', (tester) async {
    await appState.storage.saveRecord(rec('a', presetId: 'p1'));
    await pumpPage(tester);

    Icon heart() => tester.widget<Icon>(
        find.byWidgetPredicate((w) => w is Icon && w.icon == FluentIcons.heart));
    expect(heart().color, AppColors.light.textSecondary);

    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();

    final filled = tester.widget<Icon>(find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.heart_fill));
    expect(filled.color, AppColors.light.danger);
    expect((await appState.loadHistory(onlyFavorites: true)).single.id, 'a');

    // 日期后追加预置词名称
    expect(find.textContaining('预置词：Vue 技术栈'), findsOneWidget);
  });

  testWidgets('深色：爱心描边/填充颜色使用深色令牌', (tester) async {
    await appState.storage.saveRecord(rec('a', favorite: true));
    await pumpPage(tester, brightness: Brightness.dark);

    final icon = tester.widget<Icon>(find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.heart_fill));
    expect(icon.color, AppColors.dark.danger);

    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();
    final outline = tester.widget<Icon>(find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.heart));
    expect(outline.color, AppColors.dark.textSecondary);
  });

  testWidgets('空状态与加载错误重试', (tester) async {
    await pumpPage(tester);
    expect(find.text('暂无历史记录'), findsOneWidget);
  });

  testWidgets('加载失败展示错误与重试入口', (tester) async {
    previous?.dispose();
    final flaky = FlakyHistoryStorage();
    final state = await makeTestAppState(storage: flaky);
    previous = state;
    appState = state;

    tester.view.physicalSize = const Size(1300, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const HistoryPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    flaky.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无历史记录'), findsOneWidget);
    expect(find.textContaining('加载失败'), findsNothing);
  });
}
