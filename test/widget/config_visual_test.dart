/// 模型配置页两种关键状态的离屏视觉证据（真实 CJK 字体）
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/model_config_page.dart';

import '../fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bytes =
        await File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
            .readAsBytes();
    final loader = FontLoader('NotoCJK')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  FluentApp appWithRealFont(Widget child) => FluentApp(
        theme: FluentThemeData(
            brightness: Brightness.light, fontFamily: 'NotoCJK'),
        home: child,
      );

  Future<void> pumpAt(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWithRealFont(const ModelConfigPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('A：未配置服务（空态+默认下拉未配置）', (tester) async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    await pumpAt(tester);
    await expectLater(find.byType(ModelConfigPage),
        matchesGoldenFile('goldens/config-empty.png'));
  });

  testWidgets('C：2 个服务（默认下拉无未配置+计数标题）', (tester) async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    await appState.saveService(testService(), apiKey: 'sk');
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false)
            .copyWith(apiUrl: 'https://api.kimi.com/coding/v1'),
        apiKey: 'sk2');
    await pumpAt(tester);
    await expectLater(find.byType(ModelConfigPage),
        matchesGoldenFile('goldens/config-two-services.png'));
  });
}
