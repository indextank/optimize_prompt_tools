/// 编程预置词存储层测试：CRUD / 名称必填与唯一性 / 内容 300 字上限 /
/// 编辑排除自身 / 删除。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/storage/sqlite_storage.dart';

CodingPreset preset(
  String id, {
  String name = '预置词',
  String content = 'Electron + Vue3，Windows 桌面端',
  int createdAt = 1700000000,
}) =>
    CodingPreset(id: id, name: name, content: content, createdAt: createdAt);

void main() {
  late SqliteStorage storage;

  setUp(() => storage = SqliteStorage.inMemory());
  tearDown(() => storage.close());

  group('CRUD', () {
    test('新增后可读回（字段完整）', () async {
      await storage.savePreset(preset('p1'));
      final list = await storage.loadPresets();
      expect(list, hasLength(1));
      expect(list.first.id, 'p1');
      expect(list.first.name, '预置词');
      expect(list.first.content, 'Electron + Vue3，Windows 桌面端');
      expect(list.first.createdAt, 1700000000);
    });

    test('编辑（同 id 覆盖）不新增条目', () async {
      await storage.savePreset(preset('p1', name: '旧名'));
      await storage.savePreset(preset('p1', name: '新名', content: '新内容'));
      final list = await storage.loadPresets();
      expect(list, hasLength(1));
      expect(list.first.name, '新名');
      expect(list.first.content, '新内容');
    });

    test('删除后列表刷新', () async {
      await storage.savePreset(preset('p1'));
      await storage.savePreset(preset('p2', name: '另一个'));
      await storage.deletePreset('p1');
      final list = await storage.loadPresets();
      expect(list, hasLength(1));
      expect(list.first.id, 'p2');
    });
  });

  group('校验（后端拦截）', () {
    test('名称为空 → FormatException', () async {
      await expectLater(
        storage.savePreset(preset('p1', name: '   ')),
        throwsA(isA<FormatException>()),
      );
    });

    test('名称重复（大小写不敏感）→ FormatException', () async {
      await storage.savePreset(preset('p1', name: 'Flutter 桌面'));
      await expectLater(
        storage.savePreset(preset('p2', name: 'flutter 桌面')),
        throwsA(predicate((e) =>
            e is FormatException && e.message.contains('已存在'))),
      );
    });

    test('编辑时同名放行（排除自身）', () async {
      await storage.savePreset(preset('p1', name: 'Flutter 桌面'));
      await storage.savePreset(
          preset('p1', name: 'Flutter 桌面', content: '更新内容'));
      final list = await storage.loadPresets();
      expect(list, hasLength(1));
      expect(list.first.content, '更新内容');
    });

    test('内容恰好 300 字 → 通过；301 字 → FormatException', () async {
      await storage.savePreset(preset('p1', content: '字' * 300));
      await expectLater(
        storage.savePreset(preset('p2', name: '另一个', content: '字' * 301)),
        throwsA(predicate((e) =>
            e is FormatException && e.message.contains('300'))),
      );
    });

    test('校验失败不落库（列表无变化）', () async {
      await storage.savePreset(preset('p1'));
      await expectLater(
        storage.savePreset(preset('p2', name: '')),
        throwsA(isA<FormatException>()),
      );
      final list = await storage.loadPresets();
      expect(list, hasLength(1), reason: '失败的保存不得产生半条数据');
    });
  });

  group('validatePreset 纯函数', () {
    test('内容可为空（不强制必填），空内容仅注入侧忽略', () {
      expect(() => validatePreset(preset('p1', content: ''), []),
          returnsNormally);
    });

    test('selfId 排除自身（唯一性判定）', () {
      final existing = [preset('p1', name: 'A')];
      expect(
          () => validatePreset(preset('p1', name: 'A'), existing, selfId: 'p1'),
          returnsNormally);
      expect(() => validatePreset(preset('p2', name: 'A'), existing),
          throwsA(isA<FormatException>()));
    });
  });
}
