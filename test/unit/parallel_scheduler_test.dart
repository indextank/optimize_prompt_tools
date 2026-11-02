/// 并行调度器测试：上限截断 / 失败隔离 / 事件序列 / 进度回调。
library;

import 'dart:async';

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
    expect(() => scheduler.run([svc('a')], [], '原文'), throwsArgumentError);
  });

  test('最多 3 并发，超出丢弃并返回丢弃列表', () async {
    for (var i = 0; i < 3; i++) {
      llm.enqueueText(kValidContractJson);
    }
    final handle = scheduler.run(
      [svc('a'), svc('b'), svc('c'), svc('d')],
      ['k1', 'k2', 'k3', 'k4'],
      '原文',
    );
    expect(handle.droppedServices, hasLength(1));
    expect(handle.droppedServices.single.id, 'd');
    final list = await handle.events.toList();
    await handle.done.timeout(const Duration(seconds: 2));
    final allDone = list.whereType<ParallelAllDone>().single;
    expect(allDone.states, hasLength(3));
    expect(allDone.states.every((s) => s.success), isTrue);
    expect(llm.capturedRequests, hasLength(3));
    for (var i = 0; i < handle.states.length; i++) {
      expect(identical(allDone.states[i], handle.states[i]), isTrue);
    }
    for (final event in list.whereType<ParallelItemDone>()) {
      expect(
        handle.states.any((state) => identical(state, event.state)),
        isTrue,
      );
    }
    expect(() => handle.states.clear(), throwsUnsupportedError);
    expect(() => handle.droppedServices.clear(), throwsUnsupportedError);
  });

  test('正常完成时不监听事件流也能等待 done', () async {
    llm.enqueueText(kValidContractJson);
    final handle = scheduler.run([svc('a')], ['k'], '原文');

    await handle.done.timeout(const Duration(seconds: 1));

    expect(handle.states.single.success, isTrue);
  });

  test('单家失败不影响其他（失败隔离）', () async {
    llm.enqueueText(kValidContractJson);
    llm.enqueueError(
        const LlmException(LlmErrorKind.unauthorized, '401', statusCode: 401));
    llm.enqueueText(kValidContractJson);
    final handle = scheduler.run(
      [svc('a'), svc('b'), svc('c')],
      ['k1', 'k2', 'k3'],
      '原文',
    );
    final list = await handle.events.toList();
    final allDone = list.whereType<ParallelAllDone>().single;
    final failed = allDone.states.where((s) => s.error != null);
    final ok = allDone.states.where((s) => s.success);
    expect(failed, hasLength(1));
    expect(
        (failed.single.error as LlmException).kind, LlmErrorKind.unauthorized);
    expect(ok, hasLength(2));
    // 每个完成都有事件 + 最终 AllDone
    expect(list.whereType<ParallelItemDone>(), hasLength(3));
    expect(list.last, isA<ParallelAllDone>());
  });

  test('逐项进度回调与耗时记录', () async {
    llm.enqueueText(kValidContractJson);
    final progress = <String>[];
    final handle = scheduler.run(
      [svc('a')],
      ['k'],
      '原文',
      onItemProgress: (id, t) => progress.add('$id:${t.length}'),
    );
    await handle.events.toList();
    expect(progress, isNotEmpty);
    expect(progress.first, startsWith('a:'));
  });

  test('全部失败时 states 均带 error', () async {
    llm.enqueueError(const LlmException(LlmErrorKind.timeout, 't'));
    final handle = scheduler.run([svc('a')], ['k'], '原文');
    final all =
        (await handle.events.toList()).whereType<ParallelAllDone>().single;
    expect(all.states.single.success, isFalse);
    expect(all.states.single.error, isA<LlmException>());
  });

  test('cancel 取消所有真实 token，关闭事件流且不发送 AllDone', () async {
    llm.chunkDelay = const Duration(milliseconds: 50);
    llm.enqueueText(kValidContractJson);
    llm.enqueueText(kValidContractJson);
    var progressCount = 0;
    final handle = scheduler.run(
      [svc('a'), svc('b')],
      ['k1', 'k2'],
      '原文',
      onItemProgress: (_, __) => progressCount++,
    );
    final emitted = <ParallelEvent>[];
    final streamDone = Completer<List<ParallelEvent>>();
    var doneCount = 0;
    handle.events.listen(
      emitted.add,
      onDone: () {
        doneCount++;
        streamDone.complete(emitted);
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(llm.capturedRequests, hasLength(2));
    handle.cancel();
    handle.cancel();
    final progressAtCancel = progressCount;
    final streamedAtCancel = [
      for (final state in handle.states) state.streamedText
    ];

    expect(handle.isCancelled, isTrue);
    expect(handle.states, hasLength(2));
    expect(
      handle.states.every((state) => state.cancelToken.isCancelled),
      isTrue,
    );
    final events = await streamDone.future.timeout(const Duration(seconds: 2));
    await handle.done.timeout(const Duration(seconds: 2));
    expect(progressCount, progressAtCancel);
    for (var i = 0; i < handle.states.length; i++) {
      expect(handle.states[i].streamedText, streamedAtCancel[i]);
      expect(handle.states[i].runResult, isNull);
      expect(handle.states[i].error, isNull);
      expect(handle.states[i].done, isFalse);
      expect(handle.states[i].elapsedMs, 0);
    }
    expect(doneCount, 1);
    expect(events.whereType<ParallelAllDone>(), isEmpty);
  });
}
