/// 并行调度器测试：上限截断 / 失败隔离 / 事件序列 / 进度回调。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/errors.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/optimize_engine.dart';
import 'package:prompt_optimizer/services/parallel_scheduler.dart';

import '../fakes.dart';

void main() {
  late FakeLlmClient llm;
  late ParallelScheduler scheduler;

  setUp(() {
    llm = FakeLlmClient();
    scheduler = ParallelScheduler(engine: OptimizeEngine(client: llm));
  });

  ServiceConfig svc(String id) => testService(id: id, provider: 'deepseek');

  test('services 与 apiKeys 长度不一致抛 ArgumentError', () {
    expect(
        () => scheduler.run([svc('a')], [], '原文'),
        throwsArgumentError);
  });

  test('最多 3 并发，超出丢弃并返回丢弃列表', () async {
    for (var i = 0; i < 3; i++) {
      llm.enqueueText(kValidContractJson);
    }
    final (events, dropped) = scheduler.run(
      [svc('a'), svc('b'), svc('c'), svc('d')],
      ['k1', 'k2', 'k3', 'k4'],
      '原文',
    );
    expect(dropped, hasLength(1));
    expect(dropped.single.id, 'd');
    final list = await events.toList();
    final allDone = list.whereType<ParallelAllDone>().single;
    expect(allDone.states, hasLength(3));
    expect(allDone.states.every((s) => s.success), isTrue);
    expect(llm.capturedRequests, hasLength(3));
  });

  test('单家失败不影响其他（失败隔离）', () async {
    llm.enqueueText(kValidContractJson);
    llm.enqueueError(
        const LlmException(LlmErrorKind.unauthorized, '401', statusCode: 401));
    llm.enqueueText(kValidContractJson);
    final (events, _) = scheduler.run(
      [svc('a'), svc('b'), svc('c')],
      ['k1', 'k2', 'k3'],
      '原文',
    );
    final list = await events.toList();
    final allDone = list.whereType<ParallelAllDone>().single;
    final failed = allDone.states.where((s) => s.error != null);
    final ok = allDone.states.where((s) => s.success);
    expect(failed, hasLength(1));
    expect((failed.single.error as LlmException).kind,
        LlmErrorKind.unauthorized);
    expect(ok, hasLength(2));
    // 每个完成都有事件 + 最终 AllDone
    expect(list.whereType<ParallelItemDone>(), hasLength(3));
    expect(list.last, isA<ParallelAllDone>());
  });

  test('逐项进度回调与耗时记录', () async {
    llm.enqueueText(kValidContractJson);
    final progress = <String>[];
    final (events, _) = scheduler.run(
      [svc('a')],
      ['k'],
      '原文',
      onItemProgress: (id, t) => progress.add('$id:${t.length}'),
    );
    await events.toList();
    expect(progress, isNotEmpty);
    expect(progress.first, startsWith('a:'));
  });

  test('全部失败时 states 均带 error', () async {
    llm.enqueueError(const LlmException(LlmErrorKind.timeout, 't'));
    final (events, _) = scheduler.run([svc('a')], ['k'], '原文');
    final all = (await events.toList()).whereType<ParallelAllDone>().single;
    expect(all.states.single.success, isFalse);
    expect(all.states.single.error, isA<LlmException>());
  });
}
