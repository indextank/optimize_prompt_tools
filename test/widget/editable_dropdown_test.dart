/// 「添加AI服务」弹窗接口地址/模型下拉修复回归测试。
///
/// 根因：AutoSuggestBox 按输入文本过滤候选，预填值导致合法预设项被隐藏。
/// 修复：EditableDropdown 全量展示 + 可编辑。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/constants.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/add_service_dialog.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmClient llm;

  setUp(() async {
    llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
  });

  Future<void> pumpDialog(WidgetTester tester,
      {ModelFetcher? fetcher, String initial = 'doubao'}) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(AddServiceDialog(
        modelFetcher: fetcher ?? (_, __, ___) async => [])));
    await tester.pumpAndSettle();
    if (initial != kProviderList.first) {
      tester.state<AddServiceDialogState>(find.byType(AddServiceDialog))
          .debugSelectProvider(initial);
      await tester.pumpAndSettle();
    }
  }

  AddServiceDialogState dialog(WidgetTester tester) =>
      tester.state(find.byType(AddServiceDialog));

  /// 打开下拉并返回 flyout 中的全部条目文本
  /// （fluent_ui 的 MenuFlyoutItem 是数据类非 Widget，须按文本收集）
  Future<List<String>> openDropdownItems(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    return tester
        .widgetList(find.descendant(
            of: find.byType(MenuFlyout), matching: find.byType(Text)))
        .map((w) => (w as Text).data ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
  }

  Future<void> closeFlyout(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  group('① 接口地址全量展示（多地址服务商）', () {
    testWidgets('智谱：标准+Coding Plan 两个地址全部展示（预填不过滤）', (tester) async {
      await pumpDialog(tester, initial: 'zhipu');
      // 字段已预填默认地址——旧实现此时下拉只剩匹配项
      expect(dialog(tester).form.apiUrl, 'https://open.bigmodel.cn/api/paas/v4');
      final items = await openDropdownItems(tester, const Key('api-url-dropdown'));
      expect(items, hasLength(2));
      expect(items, contains('https://open.bigmodel.cn/api/paas/v4'));
      expect(items, contains('https://open.bigmodel.cn/api/coding/paas/v4'));
      await closeFlyout(tester);
    });

    testWidgets('Kimi：Coding Plan 与标准地址全部展示', (tester) async {
      await pumpDialog(tester, initial: 'kimi');
      final items = await openDropdownItems(tester, const Key('api-url-dropdown'));
      expect(items, hasLength(2));
      expect(items, contains('https://api.kimi.com/coding/v1'));
      expect(items, contains('https://api.moonshot.cn/v1'));
      await closeFlyout(tester);
    });

    testWidgets('选中预设项写回文本框与表单', (tester) async {
      await pumpDialog(tester, initial: 'zhipu');
      await openDropdownItems(tester, const Key('api-url-dropdown'));
      await tester.tap(find.text('https://open.bigmodel.cn/api/coding/paas/v4'));
      await tester.pumpAndSettle();
      expect(dialog(tester).form.apiUrl,
          'https://open.bigmodel.cn/api/coding/paas/v4');
      expect(find.text('https://open.bigmodel.cn/api/coding/paas/v4'), findsWidgets);
    });

    testWidgets('手动编辑自定义地址生效，且预设项仍全量展示', (tester) async {
      await pumpDialog(tester, initial: 'zhipu');
      // 键入与任何预设都不匹配的自定义地址
      await tester.enterText(
          find.byKey(const Key('api-url-field')), 'https://my-proxy.internal/v1');
      await tester.pump();
      expect(dialog(tester).form.apiUrl, 'https://my-proxy.internal/v1');
      // 打开下拉：两个预设项一个不少（不因自定义文本被过滤）
      final items = await openDropdownItems(tester, const Key('api-url-dropdown'));
      expect(items, hasLength(2));
      expect(items, contains('https://open.bigmodel.cn/api/paas/v4'));
      expect(items, contains('https://open.bigmodel.cn/api/coding/paas/v4'));
      await closeFlyout(tester);
      // 保存校验接受自定义 https 地址
      expect(dialog(tester).form.validate(), isNull);
    });
  });

  group('② 模型下拉全量展示', () {
    testWidgets('Kimi：提示共 4 个可用模型，下拉完整展示 4 个', (tester) async {
      await pumpDialog(
          tester,
          initial: 'kimi',
          // Kimi 不支持在线自动拉取：输入 KEY 后点「刷新模型列表」走内置清单兜底
          fetcher: (_, __, ___) async =>
              ['k3', 'k3-256k', 'kimi-for-coding', 'kimi-for-coding-highspeed']);
      await tester.enterText(find.byType(PasswordBox), 'sk-correct-key');
      await tester.tap(find.text('刷新模型列表'));
      await tester.pumpAndSettle();
      expect(find.textContaining('共 4 个可用模型'), findsOneWidget);
      final items = await openDropdownItems(tester, const Key('model-dropdown'));
      for (final m in ['k3', 'k3-256k', 'kimi-for-coding', 'kimi-for-coding-highspeed']) {
        expect(items, contains(m), reason: '缺少模型 $m');
      }
      expect(items, hasLength(4));
      await closeFlyout(tester);
    });

    testWidgets('预填模型名不导致其他模型被过滤（原缺陷复现场景）', (tester) async {
      // 直接构造「k3 已预填」的场景——旧实现此时下拉仅 k3/k3-256k 两项
      await pumpDialog(tester, initial: 'kimi');
      expect(dialog(tester).form.model, 'k3'); // 预填值
      final items = await openDropdownItems(tester, const Key('model-dropdown'));
      expect(items, hasLength(4)); // 旧实现此处为 2
      await closeFlyout(tester);
    });

    testWidgets('在线拉取模型与内置清单合并去重全展示', (tester) async {
      await pumpDialog(
          tester,
          initial: 'deepseek',
          fetcher: (_, __, ___) async =>
              ['deepseek-flash', 'deepseek-v4-pro', 'deepseek-new-online']);
      await tester.enterText(find.byType(PasswordBox), 'sk-x');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      final items = await openDropdownItems(tester, const Key('model-dropdown'));
      expect(items, containsAll(
          ['deepseek-flash', 'deepseek-v4-pro', 'deepseek-new-online']));
      // 内置 2 + 在线新增 1，去重后共 3
      expect(items, hasLength(3));
      await closeFlyout(tester);
    });
  });

  group('③ 九家服务商全量巡检', () {
    testWidgets('每家预设地址数量与下拉展示数量完全一致', (tester) async {
      await pumpDialog(tester, fetcher: (_, __, ___) async => []);
      for (final p in kProviderList) {
        dialog(tester).debugSelectProvider(p);
        await tester.pumpAndSettle();
        final expectUrls = getProviderUrlOptions(p).map((e) => e.url).toList();
        final items = await openDropdownItems(tester, const Key('api-url-dropdown'));
        expect(items.toSet(), expectUrls.toSet(),
            reason: '$p 地址展示不完整');
        await closeFlyout(tester);
      }
    });

    testWidgets('每家内置模型数量与下拉展示数量一致（无过滤）', (tester) async {
      await pumpDialog(tester, fetcher: (_, __, ___) async => []);
      for (final p in kProviderList) {
        dialog(tester).debugSelectProvider(p);
        await tester.pumpAndSettle();
        final expectModels = getProviderConfig(p)!.models;
        final items = await openDropdownItems(tester, const Key('model-dropdown'));
        for (final m in expectModels) {
          expect(items, contains(m), reason: '$p 缺少模型 $m');
        }
        await closeFlyout(tester);
      }
    });

    testWidgets('切换服务商后模型清单不残留上一家（旧 cfg 闭包缺陷回归）',
        (tester) async {
      await pumpDialog(tester, initial: 'doubao');
      dialog(tester).debugSelectProvider('minimax');
      await tester.pumpAndSettle();
      final items = await openDropdownItems(tester, const Key('model-dropdown'));
      expect(items, contains('MiniMax-M3'));
      expect(items, isNot(contains('doubao-seed-1-6-250615')));
      await closeFlyout(tester);
    });
  });

  group('④ 既有交互与校验未受影响', () {
    testWidgets('校验拦截仍生效（空地址/非法地址）', (tester) async {
      await pumpDialog(tester, initial: 'zhipu');
      final form = dialog(tester).form;
      form.apiUrl = '';
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('✗'), findsOneWidget);
      expect(find.byType(AddServiceDialog), findsOneWidget); // 未关闭
      form.apiUrl = 'ftp://bad';
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AddServiceDialog), findsOneWidget);
    });

    testWidgets('模型参数联动仍按规格自动填充', (tester) async {
      await pumpDialog(tester, initial: 'deepseek');
      await openDropdownItems(tester, const Key('model-dropdown'));
      await tester.tap(find.text('deepseek-v4-pro'));
      await tester.pumpAndSettle();
      expect(dialog(tester).form.maxInputTokens, 1048576);
      expect(dialog(tester).form.temperature, 1.0);
    });
  });
}
