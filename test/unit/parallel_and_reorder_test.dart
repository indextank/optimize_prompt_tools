/// 任务验收测试：
/// 1) 每次运行软件「并行对比」默认关闭——AppSettings.fromJson 恒 false
///    （即使上次运行存过 true）；运行时状态不受影响。
/// 2) 服务拖动排序持久化（SQLite）：reorderServices 后 loadServices 保持顺序；
///    编辑保存不重置排序；新增排末尾；删除不影响其余顺序。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/settings_service.dart';
import 'package:prompt_optimizer/services/storage/sqlite_storage.dart';

ServiceConfig svc(String id, {bool isDefault = false}) => ServiceConfig(
    id: id,
    provider: 'kimi',
    apiUrl: 'https://api.moonshot.cn/v1',
    model: 'model-$id',
    isDefault: isDefault,
    createdAt: 1700000000);

void main() {
  group('① 每次运行默认「并行对比」关闭', () {
    test('fromJson 恒 false：存过 true 也不沿用', () {
      final s = AppSettings.fromJson({'parallel_enabled': true});
      expect(s.parallelEnabled, isFalse, reason: '重启后不得沿用上次开启状态');
    });

    test('fromJson 缺省同样 false', () {
      expect(AppSettings.fromJson({}).parallelEnabled, isFalse);
    });

    test('运行时开启状态正常工作，仅持久化读取被忽略', () {
      const base = AppSettings();
      expect(base.parallelEnabled, isFalse);
      final on = base.copyWith(parallelEnabled: true);
      expect(on.parallelEnabled, isTrue, reason: '运行时状态不因默认策略被锁死');
      // 存成 json 再读回 → 重启默认关
      final round = AppSettings.fromJson(on.toJson());
      expect(round.parallelEnabled, isFalse);
    });
  });

  group('② 服务拖动排序持久化（SQLite）', () {
    late SqliteStorage storage;
    setUp(() => storage = SqliteStorage.inMemory());
    tearDown(() => storage.close());

    test('reorderServices 后 loadServices 保持新顺序', () async {
      await storage.saveService(svc('a'));
      await storage.saveService(svc('b'));
      await storage.saveService(svc('c'));
      expect((await storage.loadServices()).map((s) => s.id), ['a', 'b', 'c']);

      await storage.reorderServices(['c', 'a', 'b']);
      expect((await storage.loadServices()).map((s) => s.id), ['c', 'a', 'b']);
    });

    test('编辑保存（含默认服务回写）不重置排序', () async {
      await storage.saveService(svc('a'));
      await storage.saveService(svc('b'));
      await storage.saveService(svc('c'));
      await storage.reorderServices(['b', 'c', 'a']);
      // 编辑中间项 + 设默认（触发全量回写）
      await storage.saveService(svc('b', isDefault: true).copyWith(model: 'm2'));
      final ids = (await storage.loadServices()).map((s) => s.id).toList();
      expect(ids, ['b', 'c', 'a'], reason: '保存更新不得打乱已保存的排序');
    });

    test('新增服务排到末尾（不插队）', () async {
      await storage.saveService(svc('a'));
      await storage.saveService(svc('b'));
      await storage.reorderServices(['b', 'a']);
      await storage.saveService(svc('c'));
      expect((await storage.loadServices()).map((s) => s.id), ['b', 'a', 'c']);
    });

    test('删除不影响其余顺序', () async {
      await storage.saveService(svc('a'));
      await storage.saveService(svc('b'));
      await storage.saveService(svc('c'));
      await storage.reorderServices(['c', 'b', 'a']);
      await storage.deleteService('b');
      expect((await storage.loadServices()).map((s) => s.id), ['c', 'a']);
    });
  });
}
