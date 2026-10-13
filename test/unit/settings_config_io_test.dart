/// 系统设置配置「导出/导入」序列化与校验单测：
/// - 导出：全字段 + 版本号 + 导出时间，与界面字段一一对应
/// - 导入：字段级覆盖（出现覆盖/未出现保持）、七类异常全部拦截且不写任何数据
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/services/settings_service.dart';
import 'package:prompt_optimizer/state/app_state.dart';

import '../fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;

  setUp(() async {
    state = await makeTestAppState(llm: FakeLlmClient());
  });

  group('导出', () {
    test('全字段序列化：app 标记 + 版本号 + 导出时间 + 全部设置项', () {
      final now = DateTime(2026, 10, 8, 15, 30);
      final j = jsonDecode(state.buildSettingsExportJson(now: now)) as Map;
      expect(j['app'], 'prompt_optimizer');
      expect(j['config_version'], AppState.settingsConfigVersion);
      expect(j['exported_at'], now.toIso8601String());
      final settings = j['settings'] as Map;
      // 与界面字段一一对应：15 个可配置项全量覆盖
      expect(
          settings.keys.toSet(),
          {
            'theme_mode', 'language', 'auto_start', 'hotkey', 'floating_ball',
            'default_mode', 'default_scene', 'result_language', 'auto_copy',
            'retention_days', 'proxy_mode', 'proxy_url', 'timeout_secs',
            'parallel_enabled', 'default_service_id',
          });
      // 与当前设置值一致
      expect(settings['timeout_secs'], state.settings.settings.timeoutSecs);
      expect(settings['default_mode'], state.settings.settings.defaultMode.name);
    });
  });

  group('导入：合法与字段级覆盖', () {
    String wrap(Map<String, Object?> settings) => jsonEncode({
          'app': 'prompt_optimizer',
          'config_version': 1,
          'exported_at': '2026-10-08T15:30:00.000',
          'settings': settings,
        });

    test('全字段导入：全部生效', () async {
      final merged = state.parseImportedSettings(wrap({
        'theme_mode': 'dark',
        'language': 'en_US',
        'auto_start': true,
        'hotkey': 'Alt+Shift+P',
        'floating_ball': true,
        'default_mode': 'deep',
        'default_scene': 'writing',
        'result_language': 'zh',
        'auto_copy': true,
        'retention_days': 7,
        'proxy_mode': 'custom',
        'proxy_url': 'http://127.0.0.1:8080',
        'timeout_secs': 60,
        'parallel_enabled': true,
        'default_service_id': 'svc-x',
      }));
      await state.settings.update(merged);
      final s = state.settings.settings;
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.language, 'en_US');
      expect(s.autoStart, isTrue);
      expect(s.hotkey, 'Alt+Shift+P');
      expect(s.floatingBall, isTrue);
      expect(s.defaultMode.name, 'deep');
      expect(s.defaultScene, 'writing');
      expect(s.resultLanguage, 'zh');
      expect(s.autoCopy, isTrue);
      expect(s.retentionDays, 7);
      expect(s.proxyMode, ProxyMode.custom);
      expect(s.proxyUrl, 'http://127.0.0.1:8080');
      expect(s.timeoutSecs, 60);
      expect(s.parallelEnabled, isTrue);
      expect(s.defaultServiceId, 'svc-x');
    });

    test('字段级覆盖：仅出现字段生效，未出现保持当前值', () async {
      final before = state.settings.settings;
      final merged = state.parseImportedSettings(wrap({
        'timeout_secs': 90,
        'default_mode': 'quick',
      }));
      await state.settings.update(merged);
      final s = state.settings.settings;
      expect(s.timeoutSecs, 90, reason: '出现的字段应覆盖');
      expect(s.defaultMode.name, 'quick');
      // 未出现的字段保持
      expect(s.retentionDays, before.retentionDays);
      expect(s.autoCopy, before.autoCopy);
      expect(s.proxyUrl, before.proxyUrl);
      expect(s.themeMode, before.themeMode);
    });

    test('导出→导入往返：内容与导出时一致', () async {
      await state.settings.update(state.settings.settings.copyWith(
          timeoutSecs: 45, autoCopy: true, retentionDays: 15));
      final json = state.buildSettingsExportJson();
      // 改掉几项后导入回原件
      await state.settings.update(state.settings.settings.copyWith(
          timeoutSecs: 10, autoCopy: false, retentionDays: 1));
      final merged = state.parseImportedSettings(json);
      await state.settings.update(merged);
      final s = state.settings.settings;
      expect(s.timeoutSecs, 45);
      expect(s.autoCopy, isTrue);
      expect(s.retentionDays, 15);
    });
  });

  group('导入异常：全部拦截且不写任何数据', () {
    late AppSettings before;
    setUp(() {
      before = state.settings.settings;
    });

    Future<void> expectRejected(String content, String reasonFragment) async {
      expect(() => state.parseImportedSettings(content),
          throwsA(isA<FormatException>()),
          reason: '应被拦截：$reasonFragment');
      // 原配置完全不变（校验发生在写入之前）
      expect(state.settings.settings.toJson(), before.toJson(),
          reason: '失败导入不得写入任何部分数据');
    }

    test('破损 JSON', () async {
      await expectRejected('{broken json', '解析异常');
    });

    test('顶层非对象', () async {
      await expectRejected('[1,2,3]', '结构非法');
      await expectRejected('"just a string"', '结构非法');
    });

    test('app 标记不符', () async {
      await expectRejected(
          jsonEncode({'app': 'other_tool', 'config_version': 1, 'settings': {}}),
          '非本工具配置');
    });

    test('版本号缺失或不可识别', () async {
      await expectRejected(
          jsonEncode({'app': 'prompt_optimizer', 'settings': {}}), '版本缺失');
      await expectRejected(
          jsonEncode({'app': 'prompt_optimizer', 'config_version': 99, 'settings': {}}),
          '版本过新');
      await expectRejected(
          jsonEncode({'app': 'prompt_optimizer', 'config_version': 'v1', 'settings': {}}),
          '版本类型错');
    });

    test('settings 缺失', () async {
      await expectRejected(
          jsonEncode({'app': 'prompt_optimizer', 'config_version': 1}),
          '缺 settings');
    });

    test('字段类型错误', () async {
      await expectRejected(
          jsonEncode({
            'app': 'prompt_optimizer', 'config_version': 1,
            'settings': {'retention_days': '7'},
          }),
          'retention_days 应为整数');
      await expectRejected(
          jsonEncode({
            'app': 'prompt_optimizer', 'config_version': 1,
            'settings': {'auto_copy': 1},
          }),
          'auto_copy 应为布尔');
      await expectRejected(
          jsonEncode({
            'app': 'prompt_optimizer', 'config_version': 1,
            'settings': {'proxy_url': 123},
          }),
          'proxy_url 应为字符串');
    });

    test('枚举值无效', () async {
      await expectRejected(
          jsonEncode({
            'app': 'prompt_optimizer', 'config_version': 1,
            'settings': {'default_mode': 'bogus'},
          }),
          'default_mode 枚举无效');
      await expectRejected(
          jsonEncode({
            'app': 'prompt_optimizer', 'config_version': 1,
            'settings': {'theme_mode': 'neon'},
          }),
          'theme_mode 枚举无效');
    });

    test('错误信息可读且带字段名', () async {
      try {
        state.parseImportedSettings(jsonEncode({
          'app': 'prompt_optimizer', 'config_version': 1,
          'settings': {'timeout_secs': '60'},
        }));
        fail('应当抛出');
      } on FormatException catch (e) {
        expect(e.message, contains('timeout_secs'));
        expect(e.message, contains('导入已取消'));
      }
    });
  });
}
