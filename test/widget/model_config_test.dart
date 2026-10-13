/// 模型配置页与添加服务弹窗 Widget 测试。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/services/llm_client.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/add_service_dialog.dart';
import 'package:prompt_optimizer/ui/pages/model_config_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmClient llm;

  setUp(() async {
    llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
  });

  Future<void> pumpBig(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(child));
    await tester.pumpAndSettle();
  }

  AddServiceDialogState dialogState(WidgetTester tester) =>
      tester.state(find.byType(AddServiceDialog));

  group('配置页', () {
    testWidgets('空状态提示 + 分组标题', (tester) async {
      await pumpBig(tester, const ModelConfigPage());
      expect(find.text('AI 模型配置'), findsOneWidget);
      expect(find.text('默认优化服务'), findsOneWidget);
      expect(find.text('已配置的AI服务（0）'), findsOneWidget);
      expect(find.textContaining('暂未配置任何AI服务'), findsOneWidget);
    });

    testWidgets('服务卡片渲染 + 默认徽标 + 编辑删除按钮', (tester) async {
      await appState.saveService(testService(), apiKey: 'sk');
      await appState.saveService(
          testService(id: 'b', provider: 'kimi', model: 'k3', isDefault: false),
          apiKey: 'sk2');
      await pumpBig(tester, const ModelConfigPage());
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text('Kimi CN'), findsOneWidget);
      expect(find.textContaining('★ 默认'), findsOneWidget);
      expect(find.text('✏️ 编辑'), findsNWidgets(2));
      expect(find.text('🗑 删除'), findsNWidgets(2));
      expect(find.textContaining('模型: deepseek-flash'), findsOneWidget);
    });
  });

  group('添加服务弹窗', () {
    testWidgets('字段完整渲染（对齐基准弹窗）', (tester) async {
      await pumpBig(tester, AddServiceDialog(modelFetcher: (_, __, ___) async => ['m1']));
      for (final t in [
        '添加AI服务', 'AI服务提供商', 'API接口地址', 'API KEY', '模型',
        'Temperature', '最大输入Token', '最大输出Token', '思考模式', '支持图片输入',
        '测试连接', '取消', '保存', '显示密码', '刷新模型列表',
      ]) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      // 默认服务商为豆包，地址联动到火山方舟
      expect(dialogState(tester).form.provider, 'doubao');
      expect(dialogState(tester).form.apiUrl,
          'https://ark.cn-beijing.volces.com/api/v3');
    });

    testWidgets('切换服务商联动地址与模型规格', (tester) async {
      await pumpBig(tester, AddServiceDialog(modelFetcher: (_, __, ___) async => []));
      // 打开服务商下拉并选择 DeepSeek
      await tester.tap(find.byType(ComboBox<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('DeepSeek').last);
      await tester.pumpAndSettle();
      expect(dialogState(tester).form.apiUrl, 'https://api.deepseek.com');
      expect(dialogState(tester).form.model, 'deepseek-flash');
      expect(dialogState(tester).form.maxInputTokens, 1048576);
    });

    testWidgets('输入 KEY 停顿后自动拉取模型列表', (tester) async {
      var fetchCalled = 0;
      await pumpBig(
          tester,
          AddServiceDialog(modelFetcher: (p, url, key) async {
            fetchCalled++;
            return ['doubao-seed-1-6-250615', 'doubao-flash'];
          }));
      await tester.enterText(find.byType(PasswordBox), 'sk-test-key');
      await tester.pump(const Duration(milliseconds: 900)); // 越过防抖
      await tester.pumpAndSettle();
      expect(fetchCalled, greaterThanOrEqualTo(1));
      expect(find.textContaining('获取成功，共 2 个可用模型'), findsOneWidget);
    });

    testWidgets('拉取失败展示错误，不崩溃', (tester) async {
      await pumpBig(
          tester,
          AddServiceDialog(modelFetcher: (_, __, ___) async =>
              throw Exception('network down')));
      await tester.enterText(find.byType(PasswordBox), 'sk-x');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(find.textContaining('获取模型列表失败'), findsOneWidget);
    });

    testWidgets('测试连接成功展示延迟', (tester) async {
      await pumpBig(
          tester,
          AddServiceDialog(
            modelFetcher: (_, __, ___) async => [],
            connectionTester: (svc, key) async =>
                const ConnectionTestResult(success: true, latencyMs: 318),
          ));
      // 测试连接按钮位于滚动区底部，先滚动到可见再点击
      await tester.scrollUntilVisible(find.text('测试连接'), 120,
          scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(find.text('✓ 连接成功，延迟 318ms'), findsOneWidget);
    });

    testWidgets('非法地址保存被拦截并提示', (tester) async {
      await pumpBig(tester, AddServiceDialog(modelFetcher: (_, __, ___) async => []));
      // 清空地址
      final state = dialogState(tester);
      state.form.apiUrl = '';
      // 直接点保存（AutoSuggestBox 文本仍显示旧值，但 form 已清）
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('✗'), findsOneWidget);
      expect(find.byType(AddServiceDialog), findsOneWidget); // 弹窗未关闭
    });

    testWidgets('合法保存返回配置与密钥', (tester) async {
      AddServiceResult? result;
      await tester.pumpWidget(wrapWithFluentApp(Builder(builder: (ctx) {
        return Button(
          child: const Text('open'),
          onPressed: () async {
            result = await showAddServiceDialog(ctx,
                modelFetcher: (_, __, ___) async => ['model-a']);
          },
        );
      })));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(PasswordBox), 'sk-secret');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.apiKey, 'sk-secret');
      expect(result!.config.provider, 'doubao');
      expect(result!.config.keyRef, isEmpty); // 密钥不入配置对象
    });

    testWidgets('编辑模式：服务商锁定 + 已存参数回读', (tester) async {
      final saved = testService(id: 'e1').copyWith(
          temperature: 0.3, maxOutputTokens: 8000, thinkingMode: 'on');
      await pumpBig(
          tester,
          AddServiceDialog(
            editing: saved,
            editingApiKey: 'sk-old',
            modelFetcher: (_, __, ___) async => [],
          ));
      final combo = tester.widget<ComboBox<String>>(find.byType(ComboBox<String>).first);
      expect(combo.onChanged, isNull); // 服务商锁定
      expect(find.text('编辑AI服务'), findsOneWidget);
      expect(dialogState(tester).form.temperature, 0.3);
      expect(dialogState(tester).form.maxOutputTokens, 8000);
      expect(dialogState(tester).form.thinkingMode, 'on');
    });
  });
}
