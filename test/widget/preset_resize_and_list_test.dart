/// 本轮需求验收：
/// ① 预置词弹框可拖拽边缘/四角调整宽高；默认尺寸 = 旧 480×380 各 ×4/3；
///    调整后内部布局随尺寸自适应（内容输入框弹性伸缩），无溢出/错位/遮挡。
/// ② 列表「操作」列右对齐；水平空间让给「内容」列（flex 3→5）；
///    内容按编辑时格式完整显示（行数内不截断），超长时以「下拉框」浮层展现全文。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/preset_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

CodingPreset _preset(String id, {String name = '桌面端', String content = '内容'}) =>
    CodingPreset(id: id, name: name, content: content, createdAt: 1700000000);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    appState = await makeTestAppState();
  });

  Future<void> pumpPage(WidgetTester tester, {double w = 1280}) async {
    tester.view.physicalSize = Size(w, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const PresetPage()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('＋ 新增'));
    await tester.pumpAndSettle();
  }

  final panel = find.byKey(const Key('preset-dialog-panel'));

  /// 面板设计尺寸（paintBounds，不受路由过渡缩放影响）
  Size panelSize(WidgetTester t) =>
      (t.renderObject(panel) as RenderBox).paintBounds.size;

  /// 拖拽命中带：左边缘中心
  // 命中点取面板边缘内侧 2px（手柄带内侧半段，hit-test 需在面板边界内）
  Offset leftEdge(WidgetTester t) {
    final r = t.getRect(panel);
    return Offset(r.left + 2, r.center.dy);
  }

  Offset rightEdge(WidgetTester t) {
    final r = t.getRect(panel);
    return Offset(r.right - 2, r.center.dy);
  }

  Offset bottomRight(WidgetTester t) {
    final r = t.getRect(panel);
    return Offset(r.right - 2, r.bottom - 2);
  }

  group('① 弹框拖拽调整大小', () {
    testWidgets('默认尺寸 = 旧 480×380 各 ×4/3（640×507）', (tester) async {
      await pumpPage(tester);
      await openDialog(tester);
      final size = panelSize(tester);
      expect(size.width, 640);
      expect(size.height, closeTo(380 * 4 / 3, 3), reason: '默认高 = 旧高 ×4/3');
    });

    testWidgets('拖右边缘改变宽度（向右 +80 → 宽 +80）', (tester) async {
      await pumpPage(tester);
      await openDialog(tester);
      final before = panelSize(tester);
      final g = await tester.startGesture(rightEdge(tester),
          kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(80, 0));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      final after = panelSize(tester);
      expect(after.width, closeTo(before.width + 80, 5));
      expect(after.height, before.height, reason: '纯水平拖不改高');
    });

    testWidgets('拖左边缘向左（dx=-50）→ 宽度增加 50', (tester) async {
      await pumpPage(tester);
      await openDialog(tester);
      final before = panelSize(tester);
      final g = await tester.startGesture(leftEdge(tester),
          kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(-50, 0));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(panelSize(tester).width, closeTo(before.width + 50, 5));
    });

    testWidgets('拖右下角同时改宽高（+60, +40）', (tester) async {
      await pumpPage(tester);
      await openDialog(tester);
      final before = panelSize(tester);
      final g = await tester.startGesture(bottomRight(tester),
          kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(60, 40));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      final after = panelSize(tester);
      expect(after.width, closeTo(before.width + 60, 5));
      expect(after.height, closeTo(before.height + 40, 5));
    });

    testWidgets('缩到最小尺寸钳制（不小于 420×320）', (tester) async {
      await pumpPage(tester);
      await openDialog(tester);
      // 连续向左上狠拖，尺寸应钳在最小值
      final g = await tester.startGesture(bottomRight(tester),
          kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(-900, -900));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      final size = panelSize(tester);
      expect(size.width, 420);
      expect(size.height, 320);
    });

    testWidgets('放大后内容输入框随高度伸缩且无溢出', (tester) async {
      await pumpPage(tester);
      await openDialog(tester);
      final contentBox = find.byType(TextBox).at(1);
      final h0 = tester.getRect(contentBox).height;
      final g = await tester.startGesture(bottomRight(tester),
          kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(60, 120));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      final h1 = tester.getRect(contentBox).height;
      expect(h1, greaterThan(h0 + 100), reason: '内容输入框吃掉弹框新增高度');
      expect(tester.takeException(), isNull, reason: 'resize 后无溢出异常');
      // 保存/取消按钮仍可见不被遮挡
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('新增'), findsOneWidget);
    });
  });

  group('③ 弹框视觉（用户反馈修正）', () {
    testWidgets('弹框面板完全不透明', (tester) async {
      await pumpPage(tester);
      await openDialog(tester);
      // 面板白底不透明：Container 的背景色 alpha == 1
      final containers = find.descendant(
          of: panel, matching: find.byType(Container));
      Color? bg;
      for (final w in containers.evaluate()) {
        final dec = (w.widget as Container).decoration;
        if (dec is BoxDecoration && dec.color != null && dec.borderRadius != null) {
          bg = dec.color;
          break;
        }
      }
      expect(bg, isNotNull, reason: '找到面板装饰容器');
      expect(bg!.a, 1.0, reason: '背景色不透明（取消弹框透明度）');
    });

    testWidgets('提示文字与系统字体一致（14）', (tester) async {
      await pumpPage(tester);
      await openDialog(tester);
      for (final text in [
        '技术背景仅作为优化上下文，不会作为待优化内容',
        '内容超过 300 字禁止输入',
      ]) {
        final t = tester.widget<Text>(find.text(text));
        expect(t.style?.fontSize, 14, reason: '「$text」字号应为 14');
      }
    });
  });

  group('② 列表列调整与内容展示', () {
    testWidgets('操作列右对齐：删除按钮贴近行右缘', (tester) async {
      await appState.savePreset(_preset('p1'));
      await pumpPage(tester);
      final row = tester.getRect(find.text('桌面端')); // 行内名称文本
      final del = tester.getRect(find.text('删除'));
      expect(del.right, greaterThan(row.right + 100),
          reason: '操作列在行右侧且按钮组贴右缘');
      // 行容器右缘 = 表头右缘：删除按钮右缘距行右缘 ≤ 24（12 padding + 按钮内距）
      final head = tester.getRect(find.text('操作'));
      expect(del.right, greaterThan(head.right - 40));
    });

    testWidgets('内容列宽于名称列（水平空间向内容列倾斜）', (tester) async {
      await appState.savePreset(_preset('p1', content: '一二三四五六七八九十' * 3));
      await pumpPage(tester);
      final nameCol = tester.getRect(find.text('桌面端'));
      final contentText = find.text('一二三四五六七八九十' * 3);
      expect(contentText, findsOneWidget);
      final contentCol = tester.getRect(contentText);
      expect(contentCol.width, greaterThan(nameCol.width),
          reason: '内容列 flex 5 > 名称列 flex 2');
    });

    testWidgets('短内容按编辑格式完整显示（保留换行、无截断控件）', (tester) async {
      await appState.savePreset(
          _preset('p1', content: '第一行内容\n第二行内容\n第三行内容'));
      await pumpPage(tester);
      expect(find.text('第一行内容\n第二行内容\n第三行内容'), findsOneWidget,
          reason: '格式与编辑时一致（换行保留）');
      expect(find.textContaining('点击下拉查看完整内容'), findsNothing);
    });

    testWidgets('8 行以内多行内容完整显示', (tester) async {
      final content = List.generate(8, (i) => '第${i + 1}行内容').join('\n');
      await appState.savePreset(_preset('p1', content: content));
      await pumpPage(tester);
      expect(find.text(content), findsOneWidget);
      expect(find.textContaining('点击下拉查看完整内容'), findsNothing);
    });

    testWidgets('超长内容 → 下拉框形式展现全文（浮层可查全量）', (tester) async {
      final content = List.generate(20, (i) => '第${i + 1}行技术背景内容').join('\n');
      await appState.savePreset(_preset('p1', content: content));
      await pumpPage(tester);
      // 超过 8 行 → 下拉框式控件
      expect(find.textContaining('点击下拉查看完整内容'), findsOneWidget);
      // 点击展开下拉浮层，查看全文
      await tester.tap(find.textContaining('点击下拉查看完整内容'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('第20行技术背景内容'), findsOneWidget,
          reason: '浮层展示完整内容，不截断');
    });
  });
}
