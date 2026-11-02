/// 用户截图回归（1274×713 浅色主题）：
///
/// 1) TabView 标签条浅色桌面风格：strip 必须有显式浅色不透明背景（不得透明
///    露出外层黑色），激活 tab 为白卡、非激活 tab 浅灰底深字，绝不黑底黑字；
///    新增 tab 标题清晰可读。
///
/// 2) 输入卡/结果卡及各分栏不得出现 RenderFlex 溢出（黄黑斜纹指示条）。
///    加载真实 Windows 中文字体（msyh/simhei/simsun）保证字宽与线上一致，
///    遍历分栏宽度/窗口宽度，收集 "A RenderFlex overflowed by …" 后断言为空，
///    并在失败信息中输出真实溢出文本与 widget 链以便定位。
///
/// 字体：C:\Windows\Fonts\msyh.ttc（或 simhei/simsun）以
/// FontLoader('Microsoft YaHei UI') 注册（与 theme.resolveCjkFontFamily 对齐），
/// 文件不存在时跳过依赖真实字宽的溢出用例。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'
    show DiagnosticLevel, FlutterErrorDetails, FlutterExceptionHandler;
import 'package:flutter/rendering.dart' show DiagnosticsDebugCreator, RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/state/workbench_tabs.dart';
import 'package:prompt_optimizer/ui/pages/workbench_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

/// Windows 系统中文字体候选（按优先级：雅黑 → 宋体 → 黑体）。
const List<String> kWindowsCjkFontCandidates = [
  r'C:\Windows\Fonts\msyh.ttc',
  r'C:\Windows\Fonts\msyh.ttf',
  r'C:\Windows\Fonts\simsun.ttc',
  r'C:\Windows\Fonts\simhei.ttf',
];

/// 以 theme.resolveCjkFontFamily() 在 Windows 返回的族名注册系统中文字体，
/// 使被测 UI 的真实字宽与用户截图环境一致。
Future<bool> loadWindowsCjkFont() async {
  var loaded = false;
  for (final path in kWindowsCjkFontCandidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader('Microsoft YaHei UI');
    loader.addFont(file.readAsBytes().then((bytes) => ByteData.view(
        bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes)));
    try {
      await loader.load();
      loaded = true;
    } catch (_) {
      // 单个字体解析失败（如 ttc 变体）继续尝试下一个候选
    }
  }
  return loaded;
}

/// 收集 FlutterError 中的溢出报错（含像素量与 widget 链）。
///
/// 溢出类错误不再转发给 binding（避免测试直接被 pending exception 判失败），
/// 由用例统一断言并输出完整定位信息；其余错误照常转发。
class _OverflowRecorder {
  final List<String> errors = <String>[];
  FlutterExceptionHandler? _previous;

  void install() {
    _previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final text = describe(details);
      if (text.contains('overflowed')) {
        errors.add(text);
        return;
      }
      _previous?.call(details);
    };
  }

  void restore() => FlutterError.onError = _previous;

  /// 异常文本 + 信息收集器节点（溢出量、RenderFlex 尺寸、widget 创建链）
  static String describe(FlutterErrorDetails details) {
    final buffer = StringBuffer(details.exceptionAsString());
    final collector = details.informationCollector;
    if (collector != null) {
      for (final node in collector()) {
        buffer.writeln();
        if (node is DiagnosticsDebugCreator) {
          // DebugCreator 持有 DebugCreator，toString() 输出 widget 链
          buffer.write('Creator: ${node.value}');
        } else {
          buffer.write(node.toStringDeep(minLevel: DiagnosticLevel.info));
        }
      }
    }
    return buffer.toString();
  }
}

double _luminance(Color color) => color.computeLuminance();

double _contrast(Color a, Color b) {
  final l1 = _luminance(a);
  final l2 = _luminance(b);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 字体文件存在性在用例定义期同步判定（skip 参数早于 setUpAll 求值）；
  // 缺字体时跳过依赖真实字宽的溢出用例（原因见文件头注释 noFontSkip 说明）
  final bool hasFontFile =
      kWindowsCjkFontCandidates.any((p) => File(p).existsSync());

  setUpAll(() async {
    if (hasFontFile) {
      final loaded = await loadWindowsCjkFont();
      expect(loaded, isTrue,
          reason: '字体文件存在但加载失败时不得静默退回测试方块字体');
    }
  });

  late FakeLlmClient llm;
  final _OverflowRecorder recorder = _OverflowRecorder();

  setUp(() async {
    llm = FakeLlmClient();
    appState = await makeTestAppState(llm: llm);
    await appState.saveService(testService(), apiKey: 'sk');
    await appState.savePreset(const CodingPreset(
      id: 'preset-desktop',
      name: 'Windows 桌面应用（Flutter + fluent_ui 组件库）',
      content: '目标平台 Windows 桌面端，Flutter 框架，fluent_ui 组件库。',
      createdAt: 1,
    ));
    recorder.install();
  });

  tearDown(() {
    recorder.restore();
  });

  /// 复现用户截图会话状态：新增「会话 1」并激活（首个「工作台」保持非激活），
  /// 切「AI 编程」场景显示编程预置词行，并选中长中文预置词。
  WorkbenchTabRuntime arrangeScreenshotSession() {
    final runtime = appState.tabs.addTab(); // 「会话 1」→ 激活
    appState.tabs.updateTab(runtime.state.id, (s) {
      s.sceneId = 'ai_coding';
      s.presetId = 'preset-desktop';
      s.rawText = '帮我写个爬虫爬豆瓣电影 Top250，要存到 Excel 里，'
          '字段要有电影名、评分、引言，遇到反爬要自动换 UA。';
    });
    return runtime;
  }

  Future<void> pumpScreenshot(WidgetTester tester,
      {Size size = const Size(1274, 713)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('shot'),
        child: wrapWithFluentApp(const WorkbenchPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 拖拽分栏手柄遍历窄/宽分栏（含钳制边界），每步等待布局稳定
  Future<void> sweepSplits(WidgetTester tester) async {
    final handle = find.byKey(const Key('split-handle'));
    if (handle.evaluate().isEmpty) return; // 紧凑布局无分栏手柄
    for (final dx in <double>[-2400, 2400, -180, 120, -80]) {
      await tester.drag(handle, Offset(dx, 0));
      await tester.pumpAndSettle();
    }
  }

  void expectNoOverflow() {
    expect(
      recorder.errors,
      isEmpty,
      reason: recorder.errors.isEmpty
          ? ''
          : '发现 ${recorder.errors.length} 处 RenderFlex 溢出：\n'
              '${recorder.errors.join('\n---\n')}',
    );
  }

  Future<ui.Image> captureShot(WidgetTester tester) async {
    final boundary = tester.renderObject(find.byKey(const Key('shot')))
        as RenderRepaintBoundary;
    final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1.0));
    return image!;
  }

  /// 解码整幅 RGBA 像素（1274×713），返回 (x<<16|y) → Color 采样表
  Future<Map<int, Color>> readPixels(WidgetTester tester, ui.Image image) async {
    final data = await tester
        .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
    final bytes = data!.buffer.asUint8List();
    final map = <int, Color>{};
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final i = (y * image.width + x) * 4;
        map[(x << 16) | y] =
            Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
      }
    }
    return map;
  }

  // ------------------------------------------------------------ 溢出回归

  testWidgets('截图尺寸 1274×713：AI 编程场景输入卡遍历分栏无 RenderFlex 溢出',
      (tester) async {
    arrangeScreenshotSession();
    await pumpScreenshot(tester);
    await sweepSplits(tester);
    expectNoOverflow();
  }, skip: !hasFontFile);

  testWidgets('遍历窗口宽度/分栏宽度：无 RenderFlex 溢出', (tester) async {
    arrangeScreenshotSession();
    await pumpScreenshot(tester);
    for (final w in <double>[1274, 1180, 1040, 920, 830, 760, 730, 700, 620, 540, 460]) {
      tester.view.physicalSize = Size(w, 713);
      await tester.pumpAndSettle();
      await sweepSplits(tester);
    }
    // 高度收紧（输入卡纵向空间变小）
    tester.view.physicalSize = const Size(1274, 600);
    await tester.pumpAndSettle();
    await sweepSplits(tester);
    expectNoOverflow();
  }, skip: !hasFontFile);

  testWidgets('中文长标题 + 窄屏/拖拽：tab 标题收缩省略且无溢出', (tester) async {
    final runtime = arrangeScreenshotSession();
    appState.tabs.updateTab(runtime.state.id, (s) {
      s.title = '这是一个非常长的中文会话标题用于验证标签条省略收缩与窄窗口布局';
    });
    await pumpScreenshot(tester);
    for (final w in <double>[1274, 980, 760, 640, 460]) {
      tester.view.physicalSize = Size(w, 713);
      await tester.pumpAndSettle();
      await sweepSplits(tester);
    }
    // 长标题仍在（省略号截断不丢语义文本），且未撑爆标签条
    expect(
        find.text('这是一个非常长的中文会话标题用于验证标签条省略收缩与窄窗口布局'),
        findsOneWidget);
    expectNoOverflow();
  }, skip: !hasFontFile);

  testWidgets('并行对比开启（头部控制组 + 双服务）：遍历窗口宽度无溢出',
      (tester) async {
    await appState.saveService(
        testService(
            id: 'svc-2',
            provider: 'kimi',
            model: 'claude-3-5-sonnet-20241022-with-a-very-long-model-name',
            isDefault: false),
        apiKey: 'sk2');
    final runtime = arrangeScreenshotSession();
    appState.tabs.updateTab(runtime.state.id, (s) {
      s.parallelEnabled = true;
      s.parallelServiceId = 'svc-2';
    });
    await pumpScreenshot(tester);
    for (final w in <double>[1274, 1040, 830, 760, 700, 560]) {
      tester.view.physicalSize = Size(w, 713);
      await tester.pumpAndSettle();
      await sweepSplits(tester);
    }
    expectNoOverflow();
  }, skip: !hasFontFile);

  // ------------------------------------------------------- TabView 浅色主题

  testWidgets('Tab 显式浅底深字：激活白卡/非激活浅灰，文本可读', (tester) async {
    arrangeScreenshotSession();
    await pumpScreenshot(tester);

    final tabView = tester.widget<TabView>(find.byType(TabView));
    expect(tabView.tabs.length, 2, reason: '工作台 + 会话 1');
    for (final tab in tabView.tabs) {
      expect(tab.backgroundColor, isA<WidgetStateColor>(),
          reason: '非激活 tab 背景必须显式设置（默认透明会露出外层黑色）');
      expect(tab.selectedBackgroundColor, isA<WidgetStateColor>(),
          reason: '激活 tab 背景必须显式设置');
      expect(tab.foregroundColor, isA<WidgetStateColor>(),
          reason: '非激活 tab 文字色必须显式设置');
      expect(tab.selectedForegroundColor, isA<WidgetStateColor>(),
          reason: '激活 tab 文字色必须显式设置');
      for (final states in const <Set<WidgetState>>{
        <WidgetState>{},
        <WidgetState>{WidgetState.hovered},
        <WidgetState>{WidgetState.pressed},
      }) {
        final bg = tab.backgroundColor!.resolve(states);
        final fg = tab.foregroundColor!.resolve(states);
        final selBg = tab.selectedBackgroundColor!.resolve(states);
        final selFg = tab.selectedForegroundColor!.resolve(states);
        expect(_luminance(bg), greaterThan(0.6),
            reason: '非激活 tab 底色必须为浅色，实际 $bg');
        expect(_luminance(selBg), greaterThan(0.6),
            reason: '激活 tab 底色必须为浅色，实际 $selBg');
        expect(_luminance(fg), lessThan(0.4),
            reason: '非激活 tab 文字必须为深色，实际 $fg');
        expect(_luminance(selFg), lessThan(0.4),
            reason: '激活 tab 文字必须为深色，实际 $selFg');
        expect(_contrast(bg, fg), greaterThan(4.0),
            reason: '非激活 tab 文本对比度不足（$fg on $bg）');
        expect(_contrast(selBg, selFg), greaterThan(4.0),
            reason: '激活 tab 文本对比度不足（$selFg on $selBg）');
      }
    }
    // 新增 tab 标题清晰可读
    expect(find.text('会话 1'), findsOneWidget);
    expect(find.text('工作台'), findsOneWidget);
  });

  testWidgets('标签条实绘采样：strip 底色浅色不透明，tab 底色非黑', (tester) async {
    arrangeScreenshotSession();
    await pumpScreenshot(tester);
    final image = await captureShot(tester);
    final pixels = await readPixels(tester, image);

    Color at(double x, double y) => pixels[(x.toInt() << 16) | y.toInt()]!;

    // 1) strip 空白区（末个 tab 右侧）：必须浅色且不透明（透明=露外层黑）
    final lastTabRight = tester.getRect(find.byType(Tab).last).right;
    final strip = at(lastTabRight + 20, 20);
    expect(strip.a, greaterThan(0.999),
        reason: '标签条背景必须显式不透明（透明会露出外层黑色），实际 $strip');
    expect(_luminance(strip), greaterThan(0.5),
        reason: '标签条空白底色必须为浅色（截图回归：不得近黑），实际 $strip');

    // 2) 非激活 tab「工作台」背景（标题左侧 padding 内采样）
    final unselText = tester.getRect(find.text('工作台'));
    final unselBg = at(unselText.left - 5, unselText.center.dy);
    expect(_luminance(unselBg), greaterThan(0.5),
        reason: '非激活 tab 底色必须为浅色，实际 $unselBg');

    // 3) 激活 tab「会话 1」背景：白卡
    final selText = tester.getRect(find.text('会话 1'));
    final selBg = at(selText.left - 5, selText.center.dy);
    expect(_luminance(selBg), greaterThan(0.8),
        reason: '激活 tab 应为白卡底色，实际 $selBg');
  });
}
