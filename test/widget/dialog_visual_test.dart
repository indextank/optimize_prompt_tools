/// 修复效果的离屏视觉证据：渲染弹窗+下拉展开态为 PNG（golden）。
/// 运行 `flutter test --update-goldens` 生成/刷新图片。
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/add_service_dialog.dart';

import '../fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 加载真实 CJK 字体（测试默认 Ahem 字体会把文字渲染成黑条）
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

  Future<void> pumpDialog(WidgetTester tester, String provider) async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appWithRealFont(AddServiceDialog(
        modelFetcher: (_, __, ___) async =>
            ['k3', 'k3-256k', 'kimi-for-coding', 'kimi-for-coding-highspeed'])));
    await tester.pumpAndSettle();
    tester
        .state<AddServiceDialogState>(find.byType(AddServiceDialog))
        .debugSelectProvider(provider);
    await tester.pumpAndSettle();
  }

  testWidgets('智谱地址下拉展开（标准+Coding Plan 双地址）', (tester) async {
    await pumpDialog(tester, 'zhipu');
    await tester.tap(find.byKey(const Key('api-url-dropdown')));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MenuFlyout),
        matchesGoldenFile('goldens/dialog-zhipu-url-dropdown.png'));
  });

  testWidgets('Kimi 模型下拉展开（4 模型全量）', (tester) async {
    await pumpDialog(tester, 'kimi');
    await tester.tap(find.byKey(const Key('model-dropdown')));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MenuFlyout),
        matchesGoldenFile('goldens/dialog-kimi-model-dropdown.png'));
  });
}
