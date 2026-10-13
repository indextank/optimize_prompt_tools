/// 工作台布局重构验收测试（2026-10-08 需求）：
/// 1) 优化模式移至结果卡上方，原底部操作条整体移除（含「输入后点击开始优化」）
/// 2) 「开始优化」单独一行位于输入卡「粘贴/清空」下方
/// 3) 结果卡底栏无「撤销」按钮
/// 4) 重新优化点击后变为「取消优化」+ 旋转环；首次优化时「开始优化」变为「取消优化」
/// 5) 提问面板无独立「取消」按钮
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/workbench_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLlmClient llm;

  setUp(() async {
    llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
    appState.session.outputStyle = OutputStyle.full; // 结构化契约用例
    await appState.saveService(testService(), apiKey: 'sk');
  });

  Future<void> pumpPage(WidgetTester tester, {double w = 1440, double h = 900}) async {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const WorkbenchPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('① 模式选择器在结果卡上方，旧操作条整体移除', (tester) async {
    await pumpPage(tester);
    // 模式选择器：标签 + 三个分段项
    expect(find.text('优化模式'), findsOneWidget);
    expect(find.text('快速优化'), findsOneWidget);
    expect(find.text('深度优化'), findsOneWidget);
    expect(find.text('提问式优化'), findsOneWidget);
    // 模式选择器垂直位置必须高于结果卡标题
    final modeY = tester.getRect(find.text('优化模式')).top;
    final resultTitleY = tester.getRect(find.text('优化结果')).top;
    expect(modeY, lessThan(resultTitleY), reason: '模式选择器应位于结果卡上方');
    // 独立模块区域：模式选择器被 Card 包裹（底色同结果卡），且与结果卡有间距
    final modeCard = find.ancestor(of: find.text('优化模式'), matching: find.byType(Card)).first;
    final modeCardRect = tester.getRect(modeCard);
    final resultCard = find.ancestor(of: find.text('优化结果'), matching: find.byType(Card)).first;
    final resultCardRect = tester.getRect(resultCard);
    expect(modeCardRect.bottom, lessThan(resultCardRect.top),
        reason: '模式选择器模块与优化结果卡之间应有可见间距（当前重叠或贴合）');
    // 居左：标签左缘与模式卡内容左缘一致（卡内边距 16）
    expect((tester.getRect(find.text('优化模式')).left - modeCardRect.left - 16).abs(),
        lessThanOrEqualTo(4),
        reason: '「优化模式」标签应居左对齐');
    // 宽度与下方「优化结果」卡一致（左右缘对齐）
    expect((modeCardRect.left - resultCardRect.left).abs(), lessThanOrEqualTo(1),
        reason: '模式卡左缘应与结果卡对齐');
    expect((modeCardRect.right - resultCardRect.right).abs(), lessThanOrEqualTo(1),
        reason: '模式卡宽度应与结果卡一致');
    // 旧操作条元素不复存在
    expect(find.text('输入后点击开始优化'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('② 「开始优化」正常宽度居中，位于输入卡「清空」按钮下方', (tester) async {
    await pumpPage(tester);
    final cta = find.widgetWithText(FilledButton, '✨ 开始优化');
    expect(cta, findsOneWidget);
    final clearBtn = find.widgetWithText(Button, '清空');
    expect(clearBtn, findsOneWidget);
    final ctaRect = tester.getRect(cta);
    final clearRect = tester.getRect(clearBtn);
    // 在清空按钮下方
    expect(ctaRect.top, greaterThan(clearRect.bottom));
    // 正常宽度（非通栏）：宽度明显小于输入卡内容宽
    final inputCard = find.ancestor(of: find.text('原始提示词'), matching: find.byType(Card)).first;
    final cardRect = tester.getRect(inputCard);
    expect(ctaRect.width, lessThan(cardRect.width * 0.6),
        reason: '开始优化应为正常宽度而非通栏');
    // 水平居中于输入卡
    expect((ctaRect.center.dx - cardRect.center.dx).abs(), lessThanOrEqualTo(6),
        reason: '开始优化应在输入卡内水平居中（差 ${(ctaRect.center.dx - cardRect.center.dx).abs()}px）');
    // 结果卡标题应在 CTA 右侧（不同栏）
    expect(tester.getRect(find.text('优化结果')).left, greaterThan(ctaRect.left));
  });

  testWidgets('③ 结果卡底栏无「撤销」按钮', (tester) async {
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.deep;
    llm.enqueueText(kValidContractJson);
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    expect(find.text('↩ 撤销'), findsNothing);
    expect(find.text('↻ 重新优化'), findsOneWidget);
    expect(find.text('📝 复查编辑'), findsOneWidget);
    expect(find.text('📄 一键复制'), findsOneWidget);
  });

  testWidgets('④ 首次优化：开始优化变为「取消优化」+ 旋转环，可取消', (tester) async {
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.deep;
    await pumpPage(tester);
    // 手动驱动一个不落完成态的优化：enqueue 后不 runAsync 等待，直接触发
    llm.enqueueText(kValidContractJson);
    final future = appState.startOptimize();
    await tester.pump(); // 构建 optimizing 态
    // 按钮变为取消优化 + 旋转环
    expect(find.text('取消优化'), findsOneWidget);
    expect(find.byType(ProgressRing), findsWidgets);
    expect(find.widgetWithText(FilledButton, '✨ 开始优化'), findsNothing);
    // 点击取消优化 → 回到开始优化
    await tester.tap(find.text('取消优化'));
    await tester.runAsync(() => future);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '✨ 开始优化'), findsOneWidget);
  });

  testWidgets('⑤ 重新优化：按钮变为「取消优化」+ 旋转环，开始优化禁用', (tester) async {
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.deep;
    llm.enqueueText(kValidContractJson);
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    expect(appState.session.currentRecord, isNotNull);
    // 点击重新优化
    llm.enqueueText(kValidContractJson);
    await tester.tap(find.text('↻ 重新优化'));
    await tester.pump(); // optimizing 帧
    // 右侧按钮变为「取消优化」+ 旋转环
    expect(find.text('取消优化'), findsOneWidget);
    expect(find.byType(ProgressRing), findsWidgets);
    // 左侧开始优化禁用（取消入口唯一）
    final cta = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '✨ 开始优化'));
    expect(cta.onPressed, isNull, reason: '重新优化进行中开始优化应禁用');
    await tester.pumpAndSettle();
    // 完成后恢复
    expect(find.text('↻ 重新优化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑥ 提问式面板无独立「取消」按钮，取消入口在主按钮', (tester) async {
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.ask;
    llm.enqueueText(kValidQuestionsJson);
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    expect(find.text('请先回答以下关键问题（可标记跳过，AI 将采用最小安全假设）：'),
        findsOneWidget);
    // 面板内无独立「取消」按钮
    expect(find.widgetWithText(Button, '取消'), findsNothing);
    // 主按钮呈现「取消优化」
    expect(find.text('取消优化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑧ 结果卡底栏：左侧模式下拉默认「简单模式」，按钮组靠右', (tester) async {
    appState.session.outputStyle = OutputStyle.simple; // 恢复代码默认值（setUp 为契约用例覆盖为 full）
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.deep;
    llm.enqueueText(kValidContractJson);
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    // 下拉存在且默认简单模式
    final combo = find.byType(ComboBox<OutputStyle>);
    expect(combo, findsOneWidget);
    expect(tester.widget<ComboBox<OutputStyle>>(combo).value, OutputStyle.simple);
    // 下拉在最左侧：其左缘小于三个按钮的左缘
    final comboLeft = tester.getRect(combo).left;
    for (final label in ['↻ 重新优化', '📝 复查编辑', '📄 一键复制']) {
      expect(tester.getRect(find.text(label)).left, greaterThan(comboLeft));
    }
    // 按钮组靠右：一键复制按钮本体右缘贴近结果卡右缘
    final copyRight =
        tester.getRect(find.widgetWithText(FilledButton, '📄 一键复制')).right;
    final cardRight =
        tester.getRect(find.ancestor(of: find.text('📄 一键复制'), matching: find.byType(Card)).first).right;
    expect(cardRight - copyRight, lessThanOrEqualTo(20), reason: '按钮组应靠右对齐');
    // 切换为完整模式 → 会话状态更新
    await tester.tap(combo);
    await tester.pumpAndSettle();
    await tester.tap(find.text('完整模式').last);
    await tester.pumpAndSettle();
    expect(appState.session.outputStyle, OutputStyle.full);
  });

  testWidgets('⑨ 简单模式优化：结果区展示整段纯文本（无六段结构）', (tester) async {
    appState.session.rawText = '修复红圈布局问题';
    appState.session.mode = OptimizeMode.quick;
    appState.session.outputStyle = OutputStyle.simple; // 显式简单模式
    const simpleOut = '请根据图片中红色圈出的区域，修复所有存在的布局问题：所有文本元素与下拉框组件需补充规范的内边距和外边距。';
    llm.enqueueText(simpleOut);
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    expect(find.textContaining('请根据图片中红色圈出的区域'), findsOneWidget);
    // 无六段标题与评分胶囊
    expect(find.text('角色定位'), findsNothing);
    expect(find.textContaining('质量评分'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑩ 模式切换即刻生效：简单↔完整切换后重新优化输出对应格式', (tester) async {
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.quick;
    // 初始完整模式（setUp），先跑一次 → 结构化六段
    llm.enqueueText(kValidContractJson);
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    expect(find.text('角色定位'), findsOneWidget, reason: '完整模式应显示六段结构');
    // 切换为简单模式 → 重新优化 → 整段纯文本，无六段无评分
    await tester.tap(find.byType(ComboBox<OutputStyle>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简单模式').last);
    await tester.pumpAndSettle();
    expect(appState.session.outputStyle, OutputStyle.simple);
    llm.enqueueText('一段连贯的简单模式提示词正文');
    // 与「重新优化」同一入口（_onOptimize → startOptimize）
    await tester.runAsync(() => appState.startOptimize());
    await tester.pumpAndSettle();
    expect(find.textContaining('一段连贯的简单模式提示词正文'), findsOneWidget);
    expect(find.text('角色定位'), findsNothing, reason: '简单模式不得出现六段结构');
    expect(find.textContaining('质量评分'), findsNothing);
    // 再切回完整模式 → 重新优化 → 恢复六段
    await tester.tap(find.byType(ComboBox<OutputStyle>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完整模式').last);
    await tester.pumpAndSettle();
    llm.enqueueText(kValidContractJson);
    await tester.runAsync(() => appState.startOptimize());
    await tester.pumpAndSettle();
    expect(find.text('角色定位'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑪ 并行对比结果双列展示：两模型结果分栏同屏', (tester) async {
    // 第二服务 + 并行开启 + 选中对比模型
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2');
    await appState.settings
        .update(appState.settings.settings.copyWith(parallelEnabled: true));
    appState.session.parallelServiceId = 'svc-2';
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.deep;
    llm.enqueueText(kValidContractJson);
    llm.enqueueText(kValidContractJson);
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    // 双列：两个模型名列头 + 各自六段结构
    expect(find.text('deepseek-flash'), findsOneWidget); // 列头（生效服务）
    expect(find.text('k3'), findsNWidgets(2), reason: '对比模型列头 + 模式下拉选中值');
    expect(find.textContaining('✓ 完成'), findsNWidgets(2));
    expect(find.text('角色定位'), findsNWidgets(2), reason: '两列均应渲染六段结构');
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑫ 简单模式并行：双列均展示整段纯文本', (tester) async {
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2');
    await appState.settings
        .update(appState.settings.settings.copyWith(parallelEnabled: true));
    appState.session.parallelServiceId = 'svc-2';
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.quick;
    appState.session.outputStyle = OutputStyle.simple;
    llm.enqueueText('主模型输出的一段连贯提示词');
    llm.enqueueText('对比模型输出的一段连贯提示词');
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    expect(find.textContaining('主模型输出的一段连贯提示词'), findsOneWidget);
    expect(find.textContaining('对比模型输出的一段连贯提示词'), findsOneWidget);
    expect(find.text('角色定位'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑬ 分栏拖拽手柄：左右拖动调整两栏宽度且钳制边界', (tester) async {
    await pumpPage(tester); // 1440 桌面
    Rect inputCardRect() => tester.getRect(find
        .ancestor(of: find.text('原始提示词'), matching: find.byType(Card))
        .first);
    final before = inputCardRect();
    final handle = find.byKey(const Key('split-handle'));
    expect(handle, findsOneWidget);
    // 向右拖 120px：输入卡变宽
    await tester.drag(handle, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(inputCardRect().width - before.width, closeTo(120, 2));
    // 向左拖 300px：变窄
    await tester.drag(handle, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(before.width - inputCardRect().width, closeTo(300 - 120, 2));
    // 大幅左拖越过下限：被钳制不缩没
    await tester.drag(handle, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(inputCardRect().width, greaterThan(200),
        reason: '钳制下限 25%，输入卡不可缩没');
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑭ 并行列头显示请求耗时（✓ 完成 总耗时X分XX秒）', (tester) async {
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2');
    await appState.settings
        .update(appState.settings.settings.copyWith(parallelEnabled: true));
    appState.session.parallelServiceId = 'svc-2';
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.deep;
    llm.enqueueText(kValidContractJson);
    llm.enqueueText(kValidContractJson);
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    expect(find.textContaining(RegExp(r'✓ 完成 总耗时(\d+分)?\d+秒')),
        findsNWidgets(2),
        reason: '每个并行列头应在 ✓ 完成后显示分秒级耗时');
  });

  testWidgets('⑮ 字数统计位于输入框最下方、「粘贴」按钮左侧', (tester) async {
    appState.session.rawText = '帮我写个爬虫';
    await pumpPage(tester);
    // 标题行不再显示字数
    final titleRect = tester.getRect(find.text('原始提示词'));
    final lenFinder = find.text('6 字');
    expect(lenFinder, findsOneWidget);
    final lenRect = tester.getRect(lenFinder);
    final pasteRect = tester.getRect(find.text('📋 粘贴'));
    // 在标题行下方（输入框底部区域）
    expect(lenRect.top, greaterThan(titleRect.bottom),
        reason: '字数统计应在标题行下方');
    // 在粘贴按钮左侧且同一行
    expect(lenRect.right, lessThanOrEqualTo(pasteRect.left),
        reason: '字数统计应位于「粘贴」按钮左侧');
    expect((lenRect.center.dy - pasteRect.center.dy).abs(), lessThan(4),
        reason: '字数统计应与粘贴按钮同行');
  });

  testWidgets('⑯ 结果区默认自由编辑：修改内容自动落库为新版本', (tester) async {
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.deep;
    llm.enqueueText(kValidContractJson);
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    expect(appState.session.currentRecord!.versions.length, 1);

    // 结果区的结构性内容以可编辑控件呈现（TextBox 存在于结果卡内）
    expect(find.byType(TextBox), findsWidgets);
    expect(find.textContaining('内容可直接编辑'), findsOneWidget, reason: '应有可编辑提示');
    // 编辑「角色定位」段（结果区第一个 TextBox）
    final resultCardBoxes = find.descendant(
        of: find.ancestor(
            of: find.text('角色定位'), matching: find.byType(Card)).first,
        matching: find.byType(TextBox));
    await tester.enterText(resultCardBoxes.first, '直接在工作台修改的角色');
    await tester.pump(const Duration(milliseconds: 1000)); // 越过 800ms 防抖
    await tester.pumpAndSettle();

    // 自动保存：生成 v2 且内容为编辑值
    final rec = appState.session.currentRecord!;
    expect(rec.versions.length, 2, reason: '编辑应自动落库为新版本');
    expect(rec.latest.result.role, '直接在工作台修改的角色');
    expect(find.textContaining('v2 · '), findsOneWidget);
    // 提交后控制器不回跳（编辑值保持显示）
    expect(find.text('直接在工作台修改的角色'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑰ 简单模式结果区：整段文本直接编辑', (tester) async {
    appState.session.rawText = '原文';
    appState.session.mode = OptimizeMode.quick;
    appState.session.outputStyle = OutputStyle.simple;
    llm.enqueueText('原始的一段优化提示词');
    await tester.runAsync(() => appState.startOptimize());
    await pumpPage(tester);
    expect(appState.session.currentRecord!.versions.length, 1);

    await tester.enterText(find.byType(TextBox).last, '改后的一段提示词');
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    final rec = appState.session.currentRecord!;
    expect(rec.versions.length, 2);
    expect(rec.latest.result.rawText, '改后的一段提示词');
    expect(rec.latest.result.isStructured, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⑦ 并行开关已开但未选对比模型时显示生效提示', (tester) async {
    await appState.saveService(
        testService(id: 'svc-2', provider: 'kimi', model: 'k3', isDefault: false),
        apiKey: 'sk2');
    await appState.settings
        .update(appState.settings.settings.copyWith(parallelEnabled: true));
    await pumpPage(tester);
    expect(find.text('选择对比模型后并行生效'), findsOneWidget);
  });
}
