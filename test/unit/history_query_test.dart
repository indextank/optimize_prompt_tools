/// 历史查询组合与收藏/预置词过滤单测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/history_query.dart';

import '../fakes.dart';

OptimizeRecord rec({
  String scene = 'ai_coding',
  String presetId = '',
  bool favorite = false,
  String raw = 'raw',
  String result = 'result',
  List<String> providers = const ['svc-1'],
}) {
  return OptimizeRecord(
    id: 'id-$scene-$presetId-$favorite',
    scene: scene,
    mode: OptimizeMode.deep,
    rawText: raw,
    versions: [
      OptimizeVersion(v: 1, result: OptimizeResult.unstructured(result)),
    ],
    providers: providers,
    favorite: favorite,
    presetId: presetId.isEmpty ? null : presetId,
    createdAt: 1700000000,
  );
}

void main() {
  group('预置词筛选显隐', () {
    test('全部 / AI 编程 / Bug 修复显示，其它场景隐藏并清空条件', () {
      expect(presetFilterVisible(''), isTrue);
      expect(presetFilterVisible('ai_coding'), isTrue);
      expect(presetFilterVisible('bug_fix'), isTrue);
      expect(presetFilterVisible('writing'), isFalse);

      final q = const HistoryQuery(scene: 'ai_coding', presetId: 'p1');
      expect(q.normalized().presetId, 'p1');
      final hidden = q.copyWith(scene: 'writing');
      expect(hidden.normalized().presetId, isEmpty);
    });
  });

  group('组合匹配', () {
    test('场景 + 预置词 + 收藏同时满足才命中', () {
      final target = rec(scene: 'ai_coding', presetId: 'p1', favorite: true);
      final noPreset = rec(scene: 'ai_coding');
      final otherScene = rec(scene: 'bug_fix', presetId: 'p1', favorite: true);
      final notFavorite = rec(scene: 'ai_coding', presetId: 'p1');

      const q = HistoryQuery(
          scene: 'ai_coding', presetId: 'p1', onlyFavorites: true);
      expect(q.matches(target), isTrue);
      expect(q.matches(noPreset), isFalse);
      expect(q.matches(otherScene), isFalse);
      expect(q.matches(notFavorite), isFalse);
    });

    test('模型筛选按 provider 映射服务 id，并与预置词叠加', () {
      final record = rec(providers: ['svc-deepseek'], presetId: 'p1');
      const q = HistoryQuery(provider: 'deepseek', presetId: 'p1');
      expect(q.matches(record, providerIds: {'svc-deepseek'}), isTrue);
      expect(q.matches(record, providerIds: {'svc-kimi'}), isFalse);
      expect(q.matches(rec(providers: ['svc-deepseek']), providerIds: {'svc-deepseek'}),
          isFalse);
    });

    test('关键词同时匹配原文与结果', () {
      final record = rec(raw: '写爬虫', result: '结构化输出');
      expect(const HistoryQuery(keyword: '爬虫').matches(record), isTrue);
      expect(const HistoryQuery(keyword: '结构化').matches(record), isTrue);
      expect(const HistoryQuery(keyword: '不存在').matches(record), isFalse);
    });

    test('只看收藏过滤未收藏记录', () {
      expect(const HistoryQuery(onlyFavorites: true).matches(rec(favorite: true)),
          isTrue);
      expect(const HistoryQuery(onlyFavorites: true).matches(rec()), isFalse);
    });
  });

  group('已使用模型提取', () {
    test('只保留历史记录中实际用过的服务商类型', () {
      final services = [
        testService(id: 'svc-1', provider: 'deepseek'),
        testService(id: 'svc-2', provider: 'kimi', model: 'k3'),
        testService(id: 'svc-3', provider: 'doubao', isDefault: false),
      ];
      final records = [
        rec(providers: ['svc-1']),
        rec(providers: ['svc-2']),
        rec(providers: ['deleted-service']),
      ];
      expect(usedProviderTypes(records, services), {'deepseek', 'kimi'});
      expect(usedProviderTypes(const [], services), isEmpty);
    });
  });
}
