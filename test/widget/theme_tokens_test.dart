/// 主题语义令牌验收测试：
/// 1) 浅/深两套令牌的正文与大字号组合满足 WCAG AA（≥4.5:1 / ≥3:1）；
/// 2) 页面实际渲染取令牌值，而非固定白色/深色；
/// 3) 切换主题即时生效、无旧主题残留，且工作台面板 State/输入不丢失；
/// 4) 浮层（对话框）使用浮层表面令牌且文字对比度达标；
/// 5) lib 源码除 theme.dart 外无硬编码颜色。
library;

import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/history_page.dart';
import 'package:prompt_optimizer/ui/pages/model_config_page.dart';
import 'package:prompt_optimizer/ui/pages/preset_page.dart';
import 'package:prompt_optimizer/ui/pages/settings_page.dart';
import 'package:prompt_optimizer/ui/pages/workbench_page.dart';
import 'package:prompt_optimizer/ui/pages/workbench_panel.dart';
import 'package:prompt_optimizer/ui/theme.dart';

import '../fakes.dart';

/// WCAG 2.x 相对对比度。
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Widget themed(Widget child, ThemeMode mode) => FluentApp(
      theme: buildFluentTheme(Brightness.light),
      darkTheme: buildFluentTheme(Brightness.dark),
      themeMode: mode,
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;

  setUp(() async {
    state = await makeTestAppState();
    appState = state;
  });

  tearDown(() {
    state.dispose();
  });

  group('① 语义令牌对比度（WCAG AA）', () {
    // (说明, 前景, 背景, 最小对比度)
    List<(String, Color, Color, double)> cases(AppColors c) => [
          ('主文字/页面', c.textPrimary, c.pageBg, 4.5),
          ('主文字/卡片', c.textPrimary, c.surface, 4.5),
          ('主文字/次级表面', c.textPrimary, c.surfaceSubtle, 4.5),
          ('次文字/页面', c.textSecondary, c.pageBg, 4.5),
          ('次文字/卡片', c.textSecondary, c.surface, 4.5),
          ('三级文字/页面', c.textTertiary, c.pageBg, 4.5),
          ('三级文字/卡片', c.textTertiary, c.surface, 4.5),
          ('三级文字/次级表面', c.textTertiary, c.surfaceSubtle, 4.5),
          ('强调文字/卡片', c.accentText, c.surface, 4.5),
          ('强调文字/强调底', c.accentText, c.accentSubtle, 4.5),
          ('强调底上的文字', c.textOnAccent, c.accent, 4.5),
          ('错误/卡片', c.danger, c.surface, 4.5),
          ('错误/错误底', c.danger, c.dangerSubtle, 4.5),
          ('警告/卡片', c.warning, c.surface, 4.5),
          ('警告/警告底', c.warning, c.warningSubtle, 4.5),
          ('成功/卡片', c.success, c.surface, 4.5),
          ('成功/成功底', c.success, c.successSubtle, 4.5),
          ('信息/卡片', c.info, c.surface, 4.5),
          ('信息/信息底', c.info, c.infoSubtle, 4.5),
          ('品牌块文字/品牌深色', c.textOnBrand, AppBrandColors.deepseek, 4.5),
          ('Tab 非激活文字/标签底', c.textSecondary, c.surfaceSubtle, 4.5),
          ('Tab 激活文字/标签底', c.textPrimary, c.surface, 4.5),
        ];

    for (final (mode, palette) in [
      ('浅色', AppColors.light),
      ('深色', AppColors.dark),
    ]) {
      test('$mode：正文与状态色均 ≥ 4.5:1', () {
        for (final (name, fg, bg, min) in cases(palette)) {
          final ratio = contrastRatio(fg, bg);
          expect(ratio, greaterThanOrEqualTo(min),
              reason: '$name 对比度 ${ratio.toStringAsFixed(2)} 低于 $min');
        }
      });
    }

    test('浅色/深色确实是两套不同取值', () {
      expect(AppColors.light.pageBg, isNot(AppColors.dark.pageBg));
      expect(AppColors.light.textPrimary, isNot(AppColors.dark.textPrimary));
      expect(AppColors.light.surface, isNot(AppColors.dark.surface));
      // 深色页面必须比浅色页面暗
      expect(AppColors.dark.pageBg.computeLuminance(),
          lessThan(AppColors.light.pageBg.computeLuminance()));
    });
  });

  group('② 令牌读取与主题绑定', () {
    testWidgets('未注入扩展时按亮度回退到对应令牌', (tester) async {
      AppColors? captured;
      await tester.pumpWidget(FluentApp(
        theme: FluentThemeData(brightness: Brightness.light),
        home: Builder(builder: (context) {
          captured = context.colors;
          return const SizedBox();
        }),
      ));
      expect(identical(captured, AppColors.light), isTrue);

      await tester.pumpWidget(FluentApp(
        theme: FluentThemeData(brightness: Brightness.dark),
        home: Builder(builder: (context) {
          captured = context.colors;
          return const SizedBox();
        }),
      ));
      await tester.pumpAndSettle();
      expect(identical(captured, AppColors.dark), isTrue);
    });

    testWidgets('buildFluentTheme 注入扩展并同步 scaffold/card 色', (tester) async {
      for (final (brightness, palette) in [
        (Brightness.light, AppColors.light),
        (Brightness.dark, AppColors.dark),
      ]) {
        final theme = buildFluentTheme(brightness);
        expect(identical(theme.extension<AppColors>(), palette), isTrue);
        expect(theme.scaffoldBackgroundColor, palette.pageBg);
        expect(theme.cardColor, palette.surface);
        expect(theme.brightness, brightness);
      }
    });
  });

  group('③ 双主题实际渲染取令牌值', () {
    for (final (mode, palette, label) in [
      (ThemeMode.light, AppColors.light, '浅色'),
      (ThemeMode.dark, AppColors.dark, '深色'),
    ]) {
      testWidgets('$label：工作台背景/标题/卡片/标签均来自令牌', (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(themed(const WorkbenchPage(), mode));
        await tester.pumpAndSettle();

        // 页面画布：TabView 外壳用 scaffoldBackgroundColor（= pageBg）
        expect(
            find.byWidgetPredicate(
                (w) => w is ColoredBox && w.color == palette.pageBg),
            findsWidgets);

        // 标题与卡片标题显式取 textPrimary，弱提示取 textTertiary
        expect(tester.widget<Text>(find.text('优化工作台')).style?.color,
            palette.textPrimary);
        expect(tester.widget<Text>(find.text('原始提示词')).style?.color,
            palette.textPrimary);
        expect(tester.widget<Text>(find.textContaining('输入原始想法')).style?.color,
            palette.textTertiary);

        // 标签状态色随主题：激活=surface，非激活=surfaceSubtle
        final tab = tester.widget<Tab>(find.byType(Tab).first);
        expect(tab.selectedBackgroundColor!.resolve({WidgetState.selected}),
            palette.surface);
        expect(tab.backgroundColor!.resolve({}), palette.surfaceSubtle);
        expect(tab.selectedForegroundColor!.resolve({WidgetState.selected}),
            palette.textPrimary);

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('深色：关键页面渲染无异常且不再使用浅色画布', (tester) async {
      tester.view.physicalSize = const Size(1300, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      for (final page in [
        const HistoryPage(),
        const ModelConfigPage(),
        const PresetPage(),
        const SettingsPage(),
      ]) {
        await tester.pumpWidget(themed(page, ThemeMode.dark));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '${page.runtimeType} 深色渲染不得异常');
        expect(
            find.byWidgetPredicate(
                (w) => w is ColoredBox && w.color == AppColors.light.pageBg),
            findsNothing,
            reason: '${page.runtimeType} 不得残留浅色画布');
        final ctx = tester.element(find.byType(ScaffoldPage).first);
        expect(identical(ctx.colors, AppColors.dark), isTrue);
        expect(
            FluentTheme.of(ctx).scaffoldBackgroundColor, AppColors.dark.pageBg);
      }
    });
  });

  group('④ 主题切换即时生效且不丢状态', () {
    testWidgets('浅→深：一帧内完成重绘，面板 State/输入保留，无旧色残留', (tester) async {
      final mode = ValueNotifier<ThemeMode>(ThemeMode.light);
      addTearDown(mode.dispose);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (_, m, __) => themed(const WorkbenchPage(), m),
      ));
      await tester.pumpAndSettle();

      final panelState = tester.state(find.byType(WorkbenchPanel));
      await tester.enterText(find.byType(TextBox).first, '主题切换前的输入');
      await tester.pump();
      expect(appState.tabs.tabs.first.controller.text, '主题切换前的输入');

      mode.value = ThemeMode.dark;
      await tester.pumpAndSettle();

      // 画布与标签立即换成深色令牌，且不残留浅色画布
      expect(
          find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color == AppColors.dark.pageBg),
          findsWidgets);
      expect(
          find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color == AppColors.light.pageBg),
          findsNothing);
      final tab = tester.widget<Tab>(find.byType(Tab).first);
      expect(tab.backgroundColor!.resolve({}), AppColors.dark.surfaceSubtle);
      expect(tab.selectedBackgroundColor!.resolve({WidgetState.selected}),
          AppColors.dark.surface);

      // 面板不被主题切换销毁：同一 State，输入仍在
      expect(identical(tester.state(find.byType(WorkbenchPanel)), panelState),
          isTrue,
          reason: '主题切换不得重建 WorkbenchPanel（会中断 SSE/丢输入）');
      expect(appState.tabs.tabs.first.controller.text, '主题切换前的输入');
      expect(tester.takeException(), isNull);
    });

    testWidgets('跟随系统：platformBrightness 变化即时重绘、无旧色残留', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(themed(const WorkbenchPage(), ThemeMode.system));
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color == AppColors.light.pageBg),
          findsWidgets);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color == AppColors.dark.pageBg),
          findsWidgets);
      expect(
          find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color == AppColors.light.pageBg),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('⑤ 浮层（对话框）', () {
    testWidgets('深色对话框使用 surfaceRaised，标题/正文对比度达标', (tester) async {
      tester.view.physicalSize = const Size(1300, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(themed(const PresetPage(), ThemeMode.dark));
      await tester.pumpAndSettle();
      await tester.tap(find.text('＋ 新增'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final panel = find.byKey(const Key('preset-dialog-panel'));
      expect(panel, findsOneWidget);
      final containers =
          find.descendant(of: panel, matching: find.byType(Container));
      final hasRaisedBg = containers.evaluate().any((e) {
        final dec = (e.widget as Container).decoration;
        return dec is BoxDecoration &&
            dec.color == AppColors.dark.surfaceRaised;
      });
      expect(hasRaisedBg, isTrue, reason: '深色弹框表面必须取 surfaceRaised');

      final title = tester.widget<Text>(find.text('新增预置词'));
      expect(title.style?.color, AppColors.dark.textPrimary);
      expect(
          contrastRatio(
              AppColors.dark.textPrimary, AppColors.dark.surfaceRaised),
          greaterThanOrEqualTo(4.5));

      // 不得出现白底弹框
      final hasWhiteBg = containers.evaluate().any((e) {
        final dec = (e.widget as Container).decoration;
        return dec is BoxDecoration && dec.color == const Color(0xFFFFFFFF);
      });
      expect(hasWhiteBg, isFalse, reason: '深色弹框不得残留纯白底');
    });
  });

  group('⑥ 硬编码颜色守卫', () {
    test('lib 除 theme.dart 外无 Color(0x…)/具名固定色', () {
      final offenders = <String>[];
      final hexRe = RegExp(r'Color\(0x');
      final namedRe = RegExp(
          r'Colors\.(white|black|grey|red|green|blue|orange|amber|yellow|teal)\b');
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path.endsWith('lib/ui/theme.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (hexRe.hasMatch(lines[i]) || namedRe.hasMatch(lines[i])) {
            offenders.add('$path:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: '以下位置仍硬编码颜色（应改用 context.colors 令牌）：\n'
              '${offenders.join('\n')}');
    });
  });
}
