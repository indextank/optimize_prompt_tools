/// 本轮布局改动视觉证据 golden：预置词列表（列宽/操作右对齐/内容完整显示）
/// 与可调尺寸弹框（默认 640×507）。
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/preset_page.dart';

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

  FluentApp app(Widget child) => FluentApp(
        theme: FluentThemeData(
            brightness: Brightness.light, fontFamily: 'NotoCJK'),
        home: child,
      );

  CodingPreset p(String id, String name, String content) =>
      CodingPreset(id: id, name: name, content: content, createdAt: 1700000000);

  testWidgets('预置词列表 1300×770（内容列加宽/操作右对齐/长短内容混排）',
      (tester) async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    await appState.savePreset(p('p1', '桌面端', 'Windows 11 桌面端，Electron + Vue3 + TypeScript，\n打包目标 nsis 与 deb。'));
    await appState.savePreset(p('p2', '移动端', 'UniApp + Vue3 移动端，兼容微信小程序与 H5。'));
    await appState.savePreset(p('p3', '长内容',
        List.generate(12, (i) => '第${i + 1}行技术背景内容').join('\n')));
    tester.view.physicalSize = const Size(1300, 770);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const PresetPage()));
    await tester.pumpAndSettle();
    await expectLater(find.byType(PresetPage),
        matchesGoldenFile('goldens/preset-list-1300.png'));
  });

  testWidgets('预置词弹框默认尺寸 1300×770（640×507）', (tester) async {
    appState = await makeTestAppState(llm: FakeLlmClient());
    await appState.savePreset(p('p1', '桌面端', 'Windows 11 桌面端，Electron + Vue3。'));
    tester.view.physicalSize = const Size(1300, 770);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const PresetPage()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('＋ 新增'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('新增预置词'), findsOneWidget, reason: 'golden 必须抓到弹框本体');
    // 弹框在 Navigator overlay（PresetPage 子树外），须截整个应用根
    await expectLater(find.byType(FluentApp),
        matchesGoldenFile('goldens/preset-dialog-1300.png'));
  });
}
