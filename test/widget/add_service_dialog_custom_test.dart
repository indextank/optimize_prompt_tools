/// 添加 AI 服务弹窗新增需求回归：
/// - 服务商「自定义」：URL/模型为空，可手动输入；
/// - 移除「显示密码」复选项，改为输入框内眼睛图标切换；
/// - 模型输入框缩短，刷新按钮紧随其后。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/constants.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/add_service_dialog.dart';
import 'package:prompt_optimizer/ui/widgets/editable_dropdown.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int fetchCalls;
  late List<(String, String, String)> fetchArgs;

  setUp(() async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    fetchCalls = 0;
    fetchArgs = [];
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(AddServiceDialog(
      modelFetcher: (provider, url, key) async {
        fetchCalls++;
        fetchArgs.add((provider, url, key));
        return ['custom-model', 'fallback-model'];
      },
    )));
    await tester.pumpAndSettle();
  }

  AddServiceDialogState dialog(WidgetTester tester) =>
      tester.state(find.byType(AddServiceDialog));

  Future<void> selectCustomProvider(WidgetTester tester) async {
    await tester.tap(find.byType(ComboBox<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义').last);
    await tester.pumpAndSettle();
  }

  testWidgets('自定义服务商：URL/模型为空，可手动填写并保存', (tester) async {
    await pumpDialog(tester);
    await selectCustomProvider(tester);

    final state = dialog(tester);
    expect(state.form.provider, kCustomProvider);
    expect(state.form.apiUrl, '');
    expect(state.form.model, '');
    expect(find.text('自定义'), findsWidgets);

    await tester.enterText(
        find.byKey(const Key('api-url-field')), 'https://example.com/v1');
    await tester.enterText(
        find.byKey(const Key('model-field')), 'my-custom-model');
    await tester.pump();

    expect(state.form.apiUrl, 'https://example.com/v1');
    expect(state.form.model, 'my-custom-model');
    expect(state.form.validate(), isNull);
    final cfg = state.form.toServiceConfig();
    expect(cfg.provider, kCustomProvider);
    expect(cfg.apiUrl, 'https://example.com/v1');
    expect(cfg.model, 'my-custom-model');
  });

  testWidgets('自定义服务商 URL 为空时不会自动拉取模型', (tester) async {
    await pumpDialog(tester);
    await selectCustomProvider(tester);

    await tester.enterText(
        find.byKey(const Key('api-key-field')), 'sk-test');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(fetchCalls, 0, reason: 'URL 为空时不应请求模型列表');

    await tester.enterText(
        find.byKey(const Key('api-url-field')), 'https://example.com/v1');
    await tester.enterText(
        find.byKey(const Key('api-key-field')), 'sk-test-2');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(fetchCalls, 1);
    expect(fetchArgs.single.$1, kCustomProvider);
    expect(fetchArgs.single.$2, 'https://example.com/v1');
  });

  testWidgets('API KEY 内嵌眼睛图标切换明文/密文，无「显示密码」复选框', (tester) async {
    await pumpDialog(tester);
    expect(find.text('显示密码'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);

    TextBox keyBox() =>
        tester.widget<TextBox>(find.byKey(const Key('api-key-field')));
    expect(keyBox().obscureText, isTrue);

    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(keyBox().obscureText, isFalse);
    expect(find.byTooltip('隐藏密码'), findsOneWidget);

    await tester.tap(find.byTooltip('隐藏密码'));
    await tester.pump();
    expect(keyBox().obscureText, isTrue);
    expect(find.byTooltip('显示密码'), findsOneWidget);
    // 排空 fluent IconButton 的 hover/press 定时器
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('模型输入框缩短，刷新按钮紧邻其后且同一行', (tester) async {
    await pumpDialog(tester);

    final dialogRect = tester.getRect(find.byType(ContentDialog));
    final modelRect = tester.getRect(find.ancestor(
        of: find.byKey(const Key('model-field')),
        matching: find.byType(EditableDropdown)));
    final refreshRect = tester.getRect(find.ancestor(
        of: find.text('刷新模型列表'), matching: find.byType(Button)));

    expect(modelRect.width, lessThan(dialogRect.width * 0.85),
        reason: '模型输入框应比整行宽度明显缩短');
    expect(refreshRect.left, greaterThanOrEqualTo(modelRect.right),
        reason: '刷新按钮应位于模型输入框右侧');
    expect(refreshRect.left - modelRect.right, lessThanOrEqualTo(20),
        reason: '刷新按钮应紧邻模型输入框');
    expect((refreshRect.center.dy - modelRect.center.dy).abs(), lessThan(12),
        reason: '按钮与输入框同一行且垂直居中');
  });
}
