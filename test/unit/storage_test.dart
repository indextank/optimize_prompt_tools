/// SQLite 存储层测试：CRUD / 默认唯一 / 搜索筛选 / 保留清理 / 损坏容错。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/errors.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/storage/sqlite_storage.dart';

import '../fakes.dart';

void main() {
  late SqliteStorage storage;

  setUp(() => storage = SqliteStorage.inMemory());
  tearDown(() => storage.close());

  OptimizeRecord rec(String id, int createdAt,
          {String scene = 'general',
          String raw = '原文',
          List<String> providers = const ['deepseek'],
          String resultText = '结果'}) =>
      OptimizeRecord(
        id: id,
        scene: scene,
        mode: OptimizeMode.deep,
        rawText: raw,
        versions: [
          OptimizeVersion(
              v: 1, result: OptimizeResult(role: resultText), createdAt: createdAt)
        ],
        providers: providers,
        createdAt: createdAt,
      );

  group('服务配置', () {
    test('保存与加载回环', () async {
      final s = testService();
      await storage.saveService(s);
      final list = await storage.loadServices();
      expect(list, hasLength(1));
      expect(list.single.provider, 'deepseek');
      expect(list.single.model, 'deepseek-flash');
    });

    test('按 id 覆盖更新', () async {
      await storage.saveService(testService());
      await storage.saveService(testService().copyWith(model: 'deepseek-v4-pro'));
      final list = await storage.loadServices();
      expect(list, hasLength(1));
      expect(list.single.model, 'deepseek-v4-pro');
    });

    test('默认唯一约束：新默认自动清掉旧默认', () async {
      await storage.saveService(testService(id: 'a', isDefault: true));
      await storage.saveService(testService(id: 'b', isDefault: true));
      final list = await storage.loadServices();
      expect(list.where((s) => s.isDefault), hasLength(1));
      expect(list.singleWhere((s) => s.isDefault).id, 'b');
    });

    test('删除', () async {
      await storage.saveService(testService(id: 'a'));
      await storage.deleteService('a');
      expect(await storage.loadServices(), isEmpty);
    });

    test('损坏 JSON 抛 StorageException', () async {
      await storage.saveService(testService());
      storage.debugExecute(
          "UPDATE services SET json='{bad json' WHERE id=?", [testService().id]);
      await expectLater(
          storage.loadServices(), throwsA(isA<StorageException>()));
    });
  });

  group('历史记录', () {
    test('保存/计数/按时间倒序', () async {
      await storage.saveRecord(rec('r1', 1000));
      await storage.saveRecord(rec('r2', 3000));
      await storage.saveRecord(rec('r3', 2000));
      expect(await storage.recordCount(), 3);
      final list = await storage.loadRecords();
      expect(list.map((e) => e.id), ['r2', 'r3', 'r1']);
    });

    test('分页 limit/offset', () async {
      for (var i = 0; i < 5; i++) {
        await storage.saveRecord(rec('r$i', i));
      }
      final page = await storage.loadRecords(limit: 2, offset: 1);
      expect(page.map((e) => e.id), ['r3', 'r2']);
    });

    test('搜索：关键字命中原文或结果', () async {
      await storage.saveRecord(rec('a', 1, raw: '帮我写爬虫'));
      await storage.saveRecord(rec('b', 2, raw: '写首诗', resultText: '诗歌正文'));
      expect((await storage.searchRecords(keyword: '爬虫')).single.id, 'a');
      expect((await storage.searchRecords(keyword: '诗歌')).single.id, 'b');
      expect(await storage.searchRecords(keyword: '不存在'), isEmpty);
    });

    test('筛选：场景与服务商', () async {
      await storage.saveRecord(rec('a', 1, scene: 'ai_coding'));
      await storage.saveRecord(rec('b', 2, scene: 'writing', providers: ['kimi']));
      expect((await storage.searchRecords(scene: 'ai_coding')).single.id, 'a');
      expect((await storage.searchRecords(provider: 'kimi')).single.id, 'b');
      expect(await storage.searchRecords(scene: 'ai_coding', provider: 'kimi'),
          isEmpty);
    });

    test('保留清理：0 天=永久；超期删除并返回条数', () async {
      final now = 100 * 86400; // 第 100 天
      await storage.saveRecord(rec('old', now - 40 * 86400)); // 40 天前
      await storage.saveRecord(rec('new', now - 10 * 86400)); // 10 天前
      expect(await storage.purgeExpiredRecords(0, nowEpochSec: now), 0);
      expect(await storage.recordCount(), 2);
      expect(await storage.purgeExpiredRecords(30, nowEpochSec: now), 1);
      final left = await storage.loadRecords();
      expect(left.single.id, 'new');
    });
  });

  group('模板与设置', () {
    test('自定义模板 CRUD', () async {
      const t = SceneTemplate(id: 'my', name: '我的场景', promptHint: '提示');
      await storage.saveTemplate(t);
      await storage.saveTemplate(
          const SceneTemplate(id: 'my', name: '改名', promptHint: '提示2'));
      final list = await storage.loadCustomTemplates();
      expect(list, hasLength(1));
      expect(list.single.name, '改名');
      await storage.deleteTemplate('my');
      expect(await storage.loadCustomTemplates(), isEmpty);
    });

    test('设置项读写', () async {
      expect(await storage.getSetting('k'), isNull);
      await storage.setSetting('k', 'v1');
      await storage.setSetting('k', 'v2');
      expect(await storage.getSetting('k'), 'v2');
    });
  });

  group('损坏容错', () {
    test('记录 JSON 损坏时读取抛 StorageException，删除后恢复', () async {
      await storage.saveRecord(rec('ok', 1));
      storage.debugExecute(
          "INSERT INTO records(id, json, scene, created_at) VALUES('bad','not-json','',3)");
      await expectLater(
          storage.loadRecords(), throwsA(isA<StorageException>()));
      await storage.deleteRecord('bad');
      expect((await storage.loadRecords()).single.id, 'ok');
    });
  });
}
