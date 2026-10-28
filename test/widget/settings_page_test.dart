/// 系统设置页 Widget 测试：渲染 / 持久化 / 校验提示。
library;

import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/export_service.dart';
import 'package:prompt_optimizer/services/settings_service.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/pages/settings_page.dart';

import '../fakes.dart';
import '../widget_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    appState = await makeTestAppState(llm: FakeLlmClient());
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithFluentApp(const SettingsPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('导出配置：JSON 文件内容与当前设置一致、文件名含日期时间', (tester) async {
    final saver = FakeFileSaver();
    SettingsPage.debugFileSaver = saver;
    addTearDown(() => SettingsPage.debugFileSaver = null);
    await appState.settings.update(appState.settings.settings
        .copyWith(timeoutSecs: 45, autoCopy: true));
    await pumpPage(tester);

    await tester.tap(find.text('⬆ 导出配置'));
    await tester.pumpAndSettle();
    expect(saver.lastExt, 'json');
    expect(saver.lastName, matches(r'^提示词优化工具配置_\d{8}_\d{4}$'));
    final j = jsonDecode(utf8.decode(saver.lastBytes!)) as Map;
    expect(j['app'], 'prompt_optimizer');
    expect(j['config_version'], AppState.settingsConfigVersion);
    expect(j['exported_at'], isNotEmpty);
    expect((j['settings'] as Map)['timeout_secs'], 45);
    expect((j['settings'] as Map)['auto_copy'], isTrue);
    // 成功提示
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('配置已导出'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('导入配置：合法 JSON 字段级覆盖并刷新界面', (tester) async {
    final saver = FakeFileSaver()
      ..nextPickFile = PickedFile(
        name: 'my_config.json',
        bytes: utf8.encode(jsonEncode({
          'app': 'prompt_optimizer',
          'config_version': 1,
          'exported_at': '2026-10-08T15:30:00.000',
          'settings': {'default_mode': 'deep', 'timeout_secs': 90},
        })),
      );
    SettingsPage.debugFileSaver = saver;
    addTearDown(() => SettingsPage.debugFileSaver = null);
    await pumpPage(tester);

    await tester.tap(find.text('⬇ 导入配置'));
    await tester.pumpAndSettle();
    // 仅接受 json 扩展名
    expect(saver.lastPickExtensions, ['json']);
    // 配置写入生效
    expect(appState.settings.settings.defaultMode, OptimizeMode.deep);
    expect(appState.settings.settings.timeoutSecs, 90);
    // 界面刷新呈现导入后的值
    expect(
        tester
            .widget<ComboBox<OptimizeMode>>(find.byType(ComboBox<OptimizeMode>))
            .value,
        OptimizeMode.deep);
    // 成功提示
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('配置导入成功'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('导入 .txt 文件：拦截并提示，配置不变', (tester) async {
    final before = appState.settings.settings.toJson();
    final saver = FakeFileSaver()
      ..nextPickFile = PickedFile(name: 'notes.txt', bytes: utf8.encode('hello'));
    SettingsPage.debugFileSaver = saver;
    addTearDown(() => SettingsPage.debugFileSaver = null);
    await pumpPage(tester);

    await tester.tap(find.text('⬇ 导入配置'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('仅支持 .json'), findsOneWidget);
    expect(appState.settings.settings.toJson(), before);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('导入破损/字段缺失 JSON：拦截并提示，配置不变', (tester) async {
    final before = appState.settings.settings.toJson();
    final saver = FakeFileSaver()
      ..nextPickFile = PickedFile(
          name: 'broken.json', bytes: utf8.encode('{broken json'));
    SettingsPage.debugFileSaver = saver;
    addTearDown(() => SettingsPage.debugFileSaver = null);
    await pumpPage(tester);

    // 破损 JSON
    await tester.tap(find.text('⬇ 导入配置'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('导入失败'), findsOneWidget);
    expect(appState.settings.settings.toJson(), before);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 字段类型错误
    saver.nextPickFile = PickedFile(
        name: 'bad_field.json',
        bytes: utf8.encode(jsonEncode({
          'app': 'prompt_optimizer', 'config_version': 1,
          'settings': {'retention_days': '三十'},
        })));
    await tester.tap(find.text('⬇ 导入配置'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('retention_days'), findsOneWidget);
    expect(appState.settings.settings.toJson(), before);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('默认优化模式默认选中「快速优化」，切换可持久化', (tester) async {
    await pumpPage(tester);
    // 默认值为快速优化（需求最新口径）
    final combo = find.byType(ComboBox<OptimizeMode>);
    expect(tester.widget<ComboBox<OptimizeMode>>(combo).value,
        OptimizeMode.quick);
    // 切换为深度优化并验证持久化生效
    await tester.tap(combo);
    await tester.pumpAndSettle();
    await tester.tap(find.text('深度优化').last);
    await tester.pumpAndSettle();
    expect(appState.settings.settings.defaultMode, OptimizeMode.deep);
  });

  testWidgets('四个分组渲染（版本模块已迁移至导航栏）', (tester) async {
    await pumpPage(tester);
    expect(find.text('系统设置'), findsOneWidget);
    expect(find.text('🖥 常规'), findsOneWidget);
    expect(find.text('✨ 优化偏好'), findsOneWidget);
    expect(find.text('🌐 网络与代理'), findsOneWidget);
    expect(find.text('🗄 数据管理'), findsOneWidget);
    // 设置页底部不再展示版本信息模块
    expect(find.text('提示词优化工具 Prompt Optimizer'), findsNothing);
    expect(find.text('检查更新'), findsNothing);
    // 「界面语言」设置项已移除（当前仅支持中文）
    expect(find.text('界面语言'), findsNothing);
    expect(find.text('当前版本提供简体中文'), findsNothing);
  });

  testWidgets('主题切换持久化', (tester) async {
    await pumpPage(tester);
    // 主题模式下拉（第一个 ComboBox）
    await tester.tap(find.byType(ComboBox<AppThemeMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色').last);
    await tester.pumpAndSettle();
    expect(appState.settings.settings.themeMode, AppThemeMode.dark);
    // 重新加载验证落库
    final reloaded = await SettingsService.load(appState.storage);
    expect(reloaded.settings.themeMode, AppThemeMode.dark);
  });

  testWidgets('自动复制开关持久化', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('toggle-autoCopy')));
    await tester.pumpAndSettle();
    expect(appState.settings.settings.autoCopy, isTrue);
    final reloaded = await SettingsService.load(appState.storage);
    expect(reloaded.settings.autoCopy, isTrue);
  });

  testWidgets('自定义代理非法地址给出错误提示且不保存', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byType(ComboBox<ProxyMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义').last);
    await tester.pumpAndSettle();
    // 出现地址输入框
    expect(find.byKey(const Key('proxy-url-field')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('proxy-url-field')), 'ftp://bad');
    await tester.pump();
    // InfoBar 有入场延迟（mediumAnimationDuration），推进后可见
    await tester.pump(const Duration(milliseconds: 500));
    expect(appState.settings.settings.proxyUrl, isNot('ftp://bad'));
    expect(find.textContaining('代理地址需以'), findsOneWidget);
    // 推进到自动关闭，避免遗留 Timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('自定义代理地址可正常键入、粘贴并实时写入配置', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byType(ComboBox<ProxyMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义').last);
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('proxy-url-field'));
    // 逐段输入模拟键入过程（中间态不被拦截）
    await tester.enterText(field, 'http');
    await tester.pump();
    expect(appState.settings.settings.proxyUrl, 'http');
    await tester.enterText(field, 'http://127.0.0.1:7890');
    await tester.pump();
    expect(appState.settings.settings.proxyUrl, 'http://127.0.0.1:7890');
    // 输入框内容与配置一致，未被 rebuild 重置
    expect(tester.widget<TextBox>(field).controller!.text, 'http://127.0.0.1:7890');
    // 持久化回环
    final reloaded = await SettingsService.load(appState.storage);
    expect(reloaded.settings.proxyUrl, 'http://127.0.0.1:7890');
  });

  testWidgets('跟随系统/直连模式下立即检测不报「尚未配置服务商」', (tester) async {
    final probeCalls = <String?>[];
    AppState.debugNetworkProbe = (proxyUrl, timeout) async {
      probeCalls.add(proxyUrl);
      return (true, proxyUrl == null ? '跟随系统' : (proxyUrl.isEmpty ? '直连' : proxyUrl));
    };
    addTearDown(() => AppState.debugNetworkProbe = null);

    await pumpPage(tester);

    // 默认跟随系统
    await tester.tap(find.text('📶 立即检测'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未配置服务商'), findsNothing);
    expect(find.text('✅ 网络连接正常'), findsOneWidget);
    expect(probeCalls.last, isNull);

    // 切换为直连
    await tester.tap(find.byType(ComboBox<ProxyMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('直连').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('📶 立即检测'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未配置服务商'), findsNothing);
    expect(find.text('✅ 网络连接正常'), findsOneWidget);
    expect(probeCalls.last, '');
  });

  testWidgets('自定义模式缺少代理地址时检测报「尚未配置服务商」，配置后走自定义代理', (tester) async {
    final probeCalls = <String?>[];
    AppState.debugNetworkProbe = (proxyUrl, timeout) async {
      probeCalls.add(proxyUrl);
      return (true, proxyUrl ?? '跟随系统');
    };
    addTearDown(() => AppState.debugNetworkProbe = null);

    await pumpPage(tester);
    await tester.tap(find.byType(ComboBox<ProxyMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义').last);
    await tester.pumpAndSettle();

    // 缺少地址：报尚未配置服务商，且不发起探测
    await tester.tap(find.text('📶 立即检测'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未配置服务商'), findsOneWidget);
    expect(probeCalls, isEmpty);

    // 填入合法地址后检测走自定义代理
    await tester.enterText(
        find.byKey(const Key('proxy-url-field')), 'http://127.0.0.1:7890');
    await tester.pump();
    await tester.tap(find.text('📶 立即检测'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未配置服务商'), findsNothing);
    expect(find.text('✅ 网络连接正常'), findsOneWidget);
    expect(probeCalls.last, 'http://127.0.0.1:7890');
  });

  testWidgets('清空历史需二次确认', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('🗑 清空历史'));
    await tester.pumpAndSettle();
    expect(find.text('清空历史记录'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('清空历史记录'), findsNothing);
  });
}
