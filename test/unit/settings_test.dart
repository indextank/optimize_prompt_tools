/// 设置服务测试：默认值 / 持久化回环 / 校验 / 变更通知。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/settings_service.dart';
import 'package:prompt_optimizer/services/storage/sqlite_storage.dart';

void main() {
  late SqliteStorage storage;

  setUp(() => storage = SqliteStorage.inMemory());
  tearDown(() => storage.close());

  group('默认值与持久化', () {
    test('首次加载为设计默认值', () async {
      final s = await SettingsService.load(storage);
      expect(s.settings.themeMode, AppThemeMode.system);
      expect(s.settings.defaultMode, OptimizeMode.quick); // 快速优化
      expect(s.settings.defaultScene, 'ai_coding'); // AI 编程
      expect(s.settings.retentionDays, 30);
      expect(s.settings.timeoutSecs, 30);
      expect(s.settings.proxyMode, ProxyMode.system);
      expect(s.settings.autoCopy, isFalse);
      expect(s.settings.parallelEnabled, isFalse);
    });

    test('更新后重新加载保持一致（持久化回环）', () async {
      final s = await SettingsService.load(storage);
      await s.update(s.settings.copyWith(
        retentionDays: 7,
        autoCopy: true,
        timeoutSecs: 60,
        defaultMode: OptimizeMode.quick,
      ));
      final s2 = await SettingsService.load(storage);
      expect(s2.settings.retentionDays, 7);
      expect(s2.settings.autoCopy, isTrue);
      expect(s2.settings.timeoutSecs, 60);
      expect(s2.settings.defaultMode, OptimizeMode.quick);
    });

    test('存储损坏时回退默认值', () async {
      await storage.setSetting('app_settings', '{broken');
      final s = await SettingsService.load(storage);
      expect(s.settings.retentionDays, 30);
    });

    test('更新成功触发 notifyListeners', () async {
      final s = await SettingsService.load(storage);
      var notified = 0;
      s.addListener(() => notified++);
      await s.update(s.settings.copyWith(autoCopy: true));
      expect(notified, 1);
    });
  });

  group('校验', () {
    Future<String?> tryUpdate(SettingsService s, AppSettings Function(AppSettings) fn) =>
        s.update(fn(s.settings));

    test('超时时间越界拒绝且不保存', () async {
      final s = await SettingsService.load(storage);
      expect(await tryUpdate(s, (c) => c.copyWith(timeoutSecs: 2)), isNotNull);
      expect(await tryUpdate(s, (c) => c.copyWith(timeoutSecs: 999)), isNotNull);
      expect(s.settings.timeoutSecs, 30); // 未变
      expect(await storage.getSetting('app_settings'), isNull); // 未落库
    });

    test('保留天数边界：0=永久合法，负数非法', () async {
      final s = await SettingsService.load(storage);
      expect(await tryUpdate(s, (c) => c.copyWith(retentionDays: 0)), isNull);
      expect(s.settings.retentionDays, 0);
      expect(await tryUpdate(s, (c) => c.copyWith(retentionDays: -1)), isNotNull);
    });

    test('自定义代理：空地址允许（先进入模式再填写），非法格式拒绝', () async {
      final s = await SettingsService.load(storage);
      // 空地址：允许切换模式（用户下一步才填地址）
      expect(
          await tryUpdate(
              s, (c) => c.copyWith(proxyMode: ProxyMode.custom, proxyUrl: '')),
          isNull);
      expect(s.settings.proxyMode, ProxyMode.custom);
      // 非法协议：拒绝且不保存
      expect(
          await tryUpdate(
              s, (c) => c.copyWith(proxyUrl: 'ftp://x')),
          isNotNull);
      expect(s.settings.proxyUrl, isEmpty);
      // 合法地址通过
      expect(
          await tryUpdate(s,
              (c) => c.copyWith(proxyUrl: 'http://127.0.0.1:65510')),
          isNull);
      expect(
          await tryUpdate(s,
              (c) => c.copyWith(proxyUrl: 'socks5://127.0.0.1:1080')),
          isNull);
    });

    test('非自定义模式下空代理地址合法', () async {
      final s = await SettingsService.load(storage);
      expect(await tryUpdate(s, (c) => c.copyWith(proxyMode: ProxyMode.direct)),
          isNull);
    });
  });
}
