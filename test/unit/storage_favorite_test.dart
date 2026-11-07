/// 收藏字段持久化、组合筛选与重启后保留测试（SQLite 内存库）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/storage/app_storage.dart';
import 'package:prompt_optimizer/services/storage/sqlite_storage.dart';
import 'package:prompt_optimizer/state/app_state.dart';

import '../fakes.dart';

OptimizeRecord rec(String id, {String scene = 'ai_coding', String? presetId}) =>
    OptimizeRecord(
      id: id,
      scene: scene,
      mode: OptimizeMode.deep,
      rawText: '原文-$id',
      versions: [
        OptimizeVersion(v: 1, result: OptimizeResult.unstructured('结果-$id')),
      ],
      providers: const ['svc-1'],
      presetId: presetId,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

void main() {
  late AppStorage storage;

  setUp(() {
    storage = SqliteStorage.inMemory();
  });

  tearDown(() async => storage.close());

  test('收藏持久化：重新读取仍保留，版本链与原文不变', () async {
    await storage.saveRecord(rec('r1'));
    expect((await storage.loadRecords()).single.favorite, isFalse);

    await storage.setRecordFavorite('r1', true);
    final saved = (await storage.loadRecords()).single;
    expect(saved.favorite, isTrue);
    expect(saved.rawText, '原文-r1');
    expect(saved.latest.result.toPlainText(), '结果-r1');

    // 序列化字段存在
    expect(saved.toJson()['favorite'], isTrue);

    // 不存在的 id 安全忽略
    await storage.setRecordFavorite('missing', true);
    expect(await storage.recordCount(), 1);
  });

  test('只看收藏 + 场景 + 预置词叠加过滤', () async {
    await storage.saveRecord(rec('a', scene: 'ai_coding', presetId: 'p1'));
    await storage.saveRecord(rec('b', scene: 'ai_coding'));
    await storage.saveRecord(rec('c', scene: 'bug_fix', presetId: 'p1'));
    await storage.setRecordFavorite('a', true);

    expect((await storage.searchRecords(onlyFavorites: true)).single.id, 'a');
    expect(
        (await storage.searchRecords(scene: 'ai_coding', onlyFavorites: true))
            .single
            .id,
        'a');
    expect(
        await storage.searchRecords(scene: 'ai_coding', presetId: 'p1'), hasLength(1));
    expect(
        await storage.searchRecords(scene: 'bug_fix', onlyFavorites: true), isEmpty);
    expect(await storage.searchRecords(presetId: 'p1'), hasLength(2));
  });

  test('AppState 切换收藏后当前 tab 同步，重启状态仍保留', () async {
    final record = rec('r1', presetId: 'p1');
    await storage.saveRecord(record);
    final state = await makeTestAppState(storage: storage);
    appState = state;

    await state.openRecord(record);
    await state.toggleFavorite(record);
    expect(state.tabs.activeTab.state.currentRecord?.favorite, isTrue);

    final favorites = await state.loadHistory(onlyFavorites: true);
    expect(favorites.single.id, 'r1');

    // 模拟重新进入：新的 AppState 读同一存储
    final reopened = await makeTestAppState(storage: storage);
    final again = await reopened.loadHistory(onlyFavorites: true);
    expect(again.single.favorite, isTrue);
    state.dispose();
    reopened.dispose();
  });

  test('优化落库时保留所选预置词关联', () async {
    final state = await makeTestAppState(storage: SqliteStorage.inMemory());
    appState = state;
    await state.saveService(testService(), apiKey: 'sk');
    await state.savePreset(CodingPreset(
      id: 'p1',
      name: 'Vue',
      content: 'Vue3 + TypeScript',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ));
    final llm = state.llmClient as FakeLlmClient;
    llm.enqueueText('优化结果');
    state.session.rawText = '写一段提示词';
    state.session.presetId = 'p1';

    await state.startOptimize();
    final matched = await state.loadHistory(presetId: 'p1');
    expect(matched.single.presetId, 'p1');
    expect(matched.single.favorite, isFalse);
    state.dispose();
  });
}
