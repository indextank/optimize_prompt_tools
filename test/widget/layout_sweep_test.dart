/// 全页面布局健康巡检：
/// 1) 每个页面在 4 档主流分辨率下渲染零异常（溢出会抛 RenderFlex overflow）
/// 2) 像素级断言：头部控件右缘 ≤ 页面右 padding；场景 chips 左缘与卡片标题对齐、间距一致
/// 3) 弹窗右缘控件与滚动条车道间距 ≥12px
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/app.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/add_service_dialog.dart';
import 'package:prompt_optimizer/ui/pages/history_page.dart';
import 'package:prompt_optimizer/ui/pages/model_config_page.dart';
import 'package:prompt_optimizer/ui/pages/review_edit_page.dart';
import 'package:prompt_optimizer/ui/pages/settings_page.dart';
import 'package:prompt_optimizer/ui/pages/workbench_page.dart';

import '../fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmClient llm;

  setUpAll(() async {
    final bytes =
        await File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
            .readAsBytes();
    final loader = FontLoader('NotoCJK')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  setUp(() async {
    llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
  });

  FluentApp app(Widget child) => FluentApp(
        theme: FluentThemeData(
            brightness: Brightness.light, fontFamily: 'NotoCJK'),
        home: child,
      );

  Future<void> pumpAt(WidgetTester tester, Widget child, double w, double h) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(child));
    await tester.pumpAndSettle();
  }

  Rect rectOf(WidgetTester tester, Finder f) =>
      tester.getRect(f);

  const sizes = [
    (1440.0, 900.0),
    (1280.0, 720.0),
    (1024.0, 700.0),
    (390.0, 844.0),
  ];

  group('① 全页面 × 主流分辨率零溢出', () {
    for (final (w, h) in sizes) {
      testWidgets('工作台 $w×$h', (tester) async {
        await pumpAt(tester, const WorkbenchPage(), w, h);
        expect(tester.takeException(), isNull);
      });
      testWidgets('模型配置 $w×$h', (tester) async {
        await appState.saveService(testService(), apiKey: 'sk');
        await pumpAt(tester, const ModelConfigPage(), w, h);
        expect(tester.takeException(), isNull);
      });
      testWidgets('系统设置 $w×$h', (tester) async {
        await pumpAt(tester, const SettingsPage(), w, h);
        expect(tester.takeException(), isNull);
      });
      testWidgets('历史记录 $w×$h', (tester) async {
        await pumpAt(tester, const HistoryPage(), w, h);
        expect(tester.takeException(), isNull);
      });
      testWidgets('复查编辑 $w×$h', (tester) async {
        await appState.saveService(testService(), apiKey: 'sk');
        appState.session.outputStyle = OutputStyle.full;
        appState.session.rawText = '原文';
        appState.session.mode = OptimizeMode.deep;
        llm.enqueueText(kValidContractJson);
        await tester.runAsync(() => appState.startOptimize());
        await pumpAt(tester, const ReviewEditPage(), w, h);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('添加服务弹窗 1280×720 与 390×844', (tester) async {
      await pumpAt(tester, AddServiceDialog(modelFetcher: (_, __, ___) async => []),
          1280, 720);
      expect(tester.takeException(), isNull);
      await pumpAt(tester, AddServiceDialog(modelFetcher: (_, __, ___) async => []),
          390, 844);
      expect(tester.takeException(), isNull);
    });
  });

  group('② 头部控制组右缘不出页面 padding（图1-B 修复回归）', () {
    for (final (w, h) in [(1440.0, 900.0), (1300.0, 770.0), (1024.0, 700.0)]) {
      testWidgets('$w 宽下「并行对比」组右缘 ≤ 宽-26', (tester) async {
        await appState.saveService(
            testService(id: 'k', provider: 'kimi', model: 'k3'), apiKey: 'sk');
        await pumpAt(tester, const WorkbenchPage(), w, h);
        final toggle = rectOf(tester, find.byType(ToggleSwitch));
        expect(toggle.right, lessThanOrEqualTo(w - 26 + 1),
            reason: '开关右缘超出页面右 padding');
        // 会话模型下拉已移除；开启并行后头部出现对比模型下拉，同样不得出界
        await appState.saveService(
            testService(id: 'z', provider: 'zhipu', model: 'glm-4.6'), apiKey: 'sk2');
        await appState.settings.update(
            appState.settings.settings.copyWith(parallelEnabled: true));
        appState.session.parallelServiceId = 'z';
        await tester.pumpWidget(app(const WorkbenchPage()));
        await tester.pumpAndSettle();
        final combo = rectOf(tester, find.byType(ComboBox<String>).first);
        expect(combo.right, lessThanOrEqualTo(w - 26 + 1),
            reason: '对比模型下拉右缘超出页面右 padding');
      });
    }

    testWidgets('390 窄屏头部控制组自动换行且不出界', (tester) async {
      await appState.saveService(
          testService(id: 'k', provider: 'kimi', model: 'k3'), apiKey: 'sk');
      await pumpAt(tester, const WorkbenchPage(), 390, 844);
      final toggle = rectOf(tester, find.byType(ToggleSwitch));
      expect(toggle.right, lessThanOrEqualTo(390 - 14 + 1)); // compact 页边距 14
      expect(tester.takeException(), isNull);
    });
  });

  group('③ 场景 chips 对齐与间距一致（图1-C 验证）', () {
    testWidgets('首 chip 左缘与卡片标题左缘对齐，相邻间距一致', (tester) async {
      await pumpAt(tester, const WorkbenchPage(), 1440, 900);
      final titleLeft = rectOf(tester, find.text('原始提示词')).left;
      final chip1 = rectOf(tester, find.text('通用'));
      final chip2 = rectOf(tester, find.text('AI 编程'));
      final chip3 = rectOf(tester, find.text('Bug 修复'));
      // 首 chip（含自身 padding 的文本会略右于其容器）——容器级对齐误差 ≤ 24px
      expect((chip1.left - titleLeft).abs(), lessThanOrEqualTo(24),
          reason: '「通用」与卡片标题左缘不对齐');
      final gap12 = chip2.left - chip1.right;
      final gap23 = chip3.left - chip2.right;
      expect((gap12 - gap23).abs(), lessThanOrEqualTo(2),
          reason: 'chip 间距不一致：$gap12 vs $gap23');
    });
  });

  group('④ 整壳结果态（含导航栏宽度）', () {
    testWidgets('1440×1000 完成深度优化后卡片头无溢出', (tester) async {
      final l = FakeLlmClient();
      appState = await makeTestAppState(llm: l);
      await appState.saveService(testService(), apiKey: 'sk');
      appState.session.outputStyle = OutputStyle.full;
      appState.session.rawText = '帮我写个爬虫';
      appState.session.mode = OptimizeMode.deep;
      l.enqueueText(kValidContractJson);
      await tester.runAsync(() => appState.startOptimize());
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const PromptOptimizerApp());
      await tester.pumpAndSettle();
      expect(find.textContaining('质量评分'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: '整壳结果态出现布局异常（卡片头 trailing 曾溢出 5.2px）');
    });
  });

  group('⑤ 弹窗右侧滚动条车道（图2 修复回归）', () {
    testWidgets('右端控件到弹窗内容区右缘间距 ≥12px', (tester) async {
      await pumpAt(tester, AddServiceDialog(modelFetcher: (_, __, ___) async => []),
          1280, 720);
      final dialogRect = rectOf(tester, find.byType(ContentDialog));
      // 刷新模型列表按钮是右侧最靠右的交互控件之一
      final refreshBtn = rectOf(tester, find.text('刷新模型列表'));
      final gap = dialogRect.right - refreshBtn.right;
      expect(gap, greaterThanOrEqualTo(12),
          reason: '右侧控件与弹窗边缘间距 $gap < 12px');
      // 「显示密码」复选框文字也不越界
      final showKey = rectOf(tester, find.text('显示密码'));
      expect(dialogRect.right - showKey.right, greaterThanOrEqualTo(12));
    });

    testWidgets('长内容滚动后右侧仍保车道（撑出滚动条场景）', (tester) async {
      // 矮视口迫使弹窗滚动
      await pumpAt(tester, AddServiceDialog(modelFetcher: (_, __, ___) async => []),
          1280, 640);
      expect(tester.takeException(), isNull);
      final dialogRect = rectOf(tester, find.byType(ContentDialog));
      final refreshBtn = rectOf(tester, find.text('刷新模型列表'));
      expect(dialogRect.right - refreshBtn.right, greaterThanOrEqualTo(12));
    });
  });
}
