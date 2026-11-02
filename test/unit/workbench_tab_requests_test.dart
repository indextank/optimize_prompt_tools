import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/errors.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/llm_client.dart';
import 'package:prompt_optimizer/services/storage/sqlite_storage.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/state/workbench_tabs.dart';
import 'package:sqlite3/sqlite3.dart';

import '../fakes.dart';

class _RequestWaiter {
  _RequestWaiter(this.count);

  final int count;
  final completer = Completer<void>();
}

class _ControlledRequest {
  _ControlledRequest(this.request, this.cancelToken)
      : controller = StreamController<LlmChunk>(sync: true);

  final ChatRequest request;
  final CancelToken? cancelToken;
  final StreamController<LlmChunk> controller;

  String get body => request.messages.last.content;

  void emit(String delta) {
    if (!controller.isClosed) controller.add(LlmChunk(delta: delta));
  }

  Future<void> complete() async {
    if (controller.isClosed) return;
    controller.add(const LlmChunk(done: true, totalTokens: 42));
    await controller.close();
  }

  Future<void> fail(Object error) async {
    if (controller.isClosed) return;
    controller.addError(error);
    await controller.close();
  }
}

/// 每个请求都由测试显式推进；取消不会替测试关闭流，因此可以稳定重放迟到事件。
class _ControlledLlmClient extends FakeLlmClient {
  final requests = <_ControlledRequest>[];
  final _waiters = <_RequestWaiter>[];

  @override
  Stream<LlmChunk> chatStream(
    ChatRequest request, {
    CancelToken? cancelToken,
  }) {
    capturedRequests.add(request);
    final controlled = _ControlledRequest(request, cancelToken);
    requests.add(controlled);
    for (final waiter in List<_RequestWaiter>.of(_waiters)) {
      if (requests.length >= waiter.count) {
        waiter.completer.complete();
        _waiters.remove(waiter);
      }
    }
    return controlled.controller.stream;
  }

  Future<void> waitForRequests(int count) {
    if (requests.length >= count) return Future<void>.value();
    final waiter = _RequestWaiter(count);
    _waiters.add(waiter);
    return waiter.completer.future.timeout(const Duration(seconds: 2));
  }

  List<_ControlledRequest> forBody(String body) =>
      requests.where((request) => request.body == body).toList();
}

class _GatedSaveStorage extends SqliteStorage {
  _GatedSaveStorage() : super(sqlite3.openInMemory());

  final saveStarted = Completer<void>();
  final _saveGate = Completer<void>();

  @override
  Future<void> saveRecord(OptimizeRecord record) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await _saveGate.future;
    await super.saveRecord(record);
  }

  void releaseSave() {
    if (!_saveGate.isCompleted) _saveGate.complete();
  }
}

OptimizeRecord _historyRecord(String id) => OptimizeRecord(
      id: id,
      scene: kDefaultScene.id,
      mode: OptimizeMode.deep,
      rawText: 'raw-$id',
      versions: [
        OptimizeVersion(
          v: 1,
          result: OptimizeResult.unstructured('result-$id'),
        ),
      ],
      providers: const ['a'],
      createdAt: 1,
    );

void main() {
  late _ControlledLlmClient llm;
  late AppState state;

  setUp(() async {
    llm = _ControlledLlmClient();
    state = await makeTestAppState(llm: llm);
    await state.saveService(testService(id: 'a'), apiKey: 'key-a');
    state.session.outputStyle = OutputStyle.simple;
    addTearDown(state.dispose);
  });

  WorkbenchTabRuntime configureTab(
    WorkbenchTabRuntime runtime,
    String raw, {
    bool parallel = false,
    String? parallelServiceId,
  }) {
    runtime.state.rawText = raw;
    runtime.state.outputStyle = OutputStyle.simple;
    runtime.state.parallelEnabled = parallel;
    runtime.state.parallelServiceId = parallelServiceId;
    runtime.syncControllerFromState();
    return runtime;
  }

  test('两个 tab 的输入与控制器互不影响', () {
    final first = state.tabs.activeTab;
    final second = state.tabs.addTab();

    first.controller.text = 'first input';
    second.controller.text = 'second input';

    expect(first.state.rawText, 'first input');
    expect(second.state.rawText, 'second input');
    expect(first.controller.text, 'first input');
    expect(second.controller.text, 'second input');
    expect(state.session, same(second.state));
  });

  test('A/B 单模型并发时乱序 delta 与完成只写各自 tab', () async {
    final tabA = configureTab(state.tabs.activeTab, 'raw-A');
    final tabB = configureTab(state.tabs.addTab(), 'raw-B');

    final futureA = state.startOptimize(tabId: tabA.state.id);
    final futureB = state.startOptimize(tabId: tabB.state.id);
    await llm.waitForRequests(2);
    final requestA = llm.forBody('raw-A').single;
    final requestB = llm.forBody('raw-B').single;

    requestA.emit('A-1');
    requestB.emit('B-1');
    expect(tabA.state.streaming['a'], 'A-1');
    expect(tabB.state.streaming['a'], 'B-1');

    requestB.emit('B-2');
    await requestB.complete();
    final recordB = await futureB;

    expect(recordB, isNotNull);
    expect(tabB.state.status, OptimizationRunStatus.success);
    expect(tabB.state.currentRecord!.latest.result.rawText, 'B-1B-2');
    expect(tabA.state.status, OptimizationRunStatus.streaming);
    expect(tabA.state.currentRecord, isNull);
    expect(tabA.state.streaming['a'], 'A-1');

    requestA.emit('A-2');
    await requestA.complete();
    final recordA = await futureA;

    expect(recordA, isNotNull);
    expect(tabA.state.currentRecord!.latest.result.rawText, 'A-1A-2');
    expect(tabB.state.currentRecord!.latest.result.rawText, 'B-1B-2');
    expect(await state.storage.recordCount(), 2);
  });

  test('切到其他 tab 后 A 后台完成仍只更新 A', () async {
    final tabA = configureTab(state.tabs.activeTab, 'background-A');
    final futureA = state.startOptimize(tabId: tabA.state.id);
    final tabB = configureTab(state.tabs.addTab(), 'active-B');
    await llm.waitForRequests(1);

    expect(state.tabs.activeTab, same(tabB));
    llm.requests.single.emit('A complete');
    await llm.requests.single.complete();
    final recordA = await futureA;

    expect(recordA, isNotNull);
    expect(tabA.state.currentRecord, same(recordA));
    expect(tabA.state.status, OptimizationRunStatus.success);
    expect(tabB.state.currentRecord, isNull);
    expect(tabB.state.streaming, isEmpty);
    expect(state.session, same(tabB.state));
  });

  test('关闭 A 不取消 B，A 迟到 delta 和完成不写状态也不落库', () async {
    final tabA = configureTab(state.tabs.addTab(), 'close-A');
    final tabB = configureTab(state.tabs.addTab(), 'keep-B');
    final stateA = tabA.state;

    final futureA = state.startOptimize(tabId: tabA.state.id);
    final futureB = state.startOptimize(tabId: tabB.state.id);
    await llm.waitForRequests(2);
    final requestA = llm.forBody('close-A').single;
    final requestB = llm.forBody('keep-B').single;

    expect(state.tabs.closeTab(tabA.state.id), isTrue);
    expect(requestA.cancelToken!.isCancelled, isTrue);
    expect(requestB.cancelToken!.isCancelled, isFalse);
    final statusAtClose = stateA.status;

    requestA.emit('late-A');
    await requestA.complete();
    expect(await futureA, isNull);

    expect(stateA.streaming, isEmpty);
    expect(stateA.currentRecord, isNull);
    expect(stateA.status, statusAtClose);
    expect(tabB.state.streaming, isEmpty);
    expect(await state.storage.recordCount(), 0);

    requestB.emit('B survives');
    await requestB.complete();
    expect(await futureB, isNotNull);
    expect(tabB.state.currentRecord!.latest.result.rawText, 'B survives');
    expect(await state.storage.recordCount(), 1);
  });

  test('单模型落库等待期间取消会回滚已保存的新记录', () async {
    final storage = _GatedSaveStorage();
    addTearDown(storage.releaseSave);
    final gatedState = await makeTestAppState(llm: llm, storage: storage);
    addTearDown(gatedState.dispose);
    await gatedState.saveService(testService(id: 'a'), apiKey: 'key-a');
    final tab = configureTab(gatedState.tabs.activeTab, 'gated-single');

    final future = gatedState.startOptimize(tabId: tab.state.id);
    await llm.waitForRequests(1);
    llm.requests.single.emit('single result');
    await llm.requests.single.complete();
    await storage.saveStarted.future.timeout(const Duration(seconds: 2));

    gatedState.cancelOptimize(tabId: tab.state.id);
    storage.releaseSave();

    expect(await future, isNull);
    expect(await storage.recordCount(), 0);
    expect(tab.state.currentRecord, isNull);
  });

  test('并行落库等待期间关闭 tab 会回滚已保存的新记录', () async {
    final storage = _GatedSaveStorage();
    addTearDown(storage.releaseSave);
    final gatedState = await makeTestAppState(llm: llm, storage: storage);
    addTearDown(gatedState.dispose);
    await gatedState.saveService(testService(id: 'a'), apiKey: 'key-a');
    await gatedState.saveService(
      testService(id: 'b', provider: 'kimi', isDefault: false),
      apiKey: 'key-b',
    );
    final tab = configureTab(
      gatedState.tabs.addTab(),
      'gated-parallel',
      parallel: true,
      parallelServiceId: 'b',
    );

    final future = gatedState.startOptimize(tabId: tab.state.id);
    await llm.waitForRequests(2);
    for (final request in llm.requests) {
      request.emit('parallel ${request.request.apiKey}');
    }
    await Future.wait(llm.requests.map((request) => request.complete()));
    await storage.saveStarted.future.timeout(const Duration(seconds: 2));

    expect(gatedState.tabs.closeTab(tab.state.id), isTrue);
    storage.releaseSave();

    expect(await future, isNull);
    expect(await storage.recordCount(), 0);
    expect(tab.state.currentRecord, isNull);
  });

  test('同 tab 取消后立即重跑，旧 run 不得覆盖新 run', () async {
    final tab = configureTab(state.tabs.activeTab, 'rerun');

    final oldFuture = state.startOptimize(tabId: tab.state.id);
    await llm.waitForRequests(1);
    final oldRequest = llm.requests[0];
    oldRequest.emit('old partial');
    state.cancelOptimize(tabId: tab.state.id);

    expect(tab.state.status, OptimizationRunStatus.error);
    expect(tab.state.errorMessage, '请求已取消，已保留接收内容');
    expect(tab.state.streaming['a'], 'old partial');

    final newFuture = state.startOptimize(tabId: tab.state.id);
    await llm.waitForRequests(2);
    final newRequest = llm.requests[1];
    newRequest.emit('new content');
    oldRequest.emit('old late');
    await oldRequest.complete();

    expect(await oldFuture, isNull);
    expect(tab.state.streaming['a'], 'new content');
    expect(tab.state.status, OptimizationRunStatus.streaming);
    expect(tab.state.currentRecord, isNull);
    expect(await state.storage.recordCount(), 0);

    await newRequest.complete();
    final newRecord = await newFuture;
    expect(newRecord, isNotNull);
    expect(tab.state.currentRecord, same(newRecord));
    expect(tab.state.currentRecord!.latest.result.rawText, 'new content');
    expect(await state.storage.recordCount(), 1);
  });

  test('活动请求无 delta 取消时为 error，即使有旧记录也不回退 success', () async {
    final tab = configureTab(state.tabs.activeTab, 'cancel-without-delta');
    tab.state.currentRecord = _historyRecord('previous');

    final future = state.startOptimize(tabId: tab.state.id);
    await llm.waitForRequests(1);
    expect(tab.state.streaming, isEmpty);
    expect(tab.state.optimizing, isTrue);

    state.cancelOptimize(tabId: tab.state.id);

    expect(tab.state.status, OptimizationRunStatus.error);
    expect(tab.state.errorMessage, '请求已取消');
    expect(tab.state.currentRecord?.id, 'previous');
    await llm.requests.single.complete();
    expect(await future, isNull);
    expect(await state.storage.recordCount(), 0);
  });

  Future<void> verifyParallelIsolation({
    required bool parallelA,
    required bool parallelB,
  }) async {
    await state.saveService(
      testService(id: 'b', provider: 'kimi', isDefault: false),
      apiKey: 'key-b',
    );
    final tabA = configureTab(
      state.tabs.activeTab,
      'mixed-A',
      parallel: parallelA,
      parallelServiceId: parallelA ? 'b' : null,
    );
    final tabB = configureTab(
      state.tabs.addTab(),
      'mixed-B',
      parallel: parallelB,
      parallelServiceId: parallelB ? 'b' : null,
    );

    final futureA = state.startOptimize(tabId: tabA.state.id);
    final futureB = state.startOptimize(tabId: tabB.state.id);
    final expectedCount = (parallelA ? 2 : 1) + (parallelB ? 2 : 1);
    await llm.waitForRequests(expectedCount);
    final requestsA = llm.forBody('mixed-A');
    final requestsB = llm.forBody('mixed-B');
    expect(requestsA, hasLength(parallelA ? 2 : 1));
    expect(requestsB, hasLength(parallelB ? 2 : 1));

    for (final request in requestsA) {
      request.emit('A ${request.request.apiKey}');
    }
    for (final request in requestsB) {
      request.emit('B ${request.request.apiKey}');
    }
    await Future.wait(requestsB.map((request) => request.complete()));
    final recordB = await futureB;

    expect(recordB, isNotNull);
    expect(tabB.state.status, OptimizationRunStatus.success);
    expect(tabB.state.currentRecord!.providers, hasLength(parallelB ? 2 : 1));
    expect(tabA.state.status, OptimizationRunStatus.streaming);
    expect(tabA.state.currentRecord, isNull);
    expect(tabA.state.streaming.keys.toSet(),
        requestsA.map((r) => r.serviceId).toSet());

    await Future.wait(requestsA.map((request) => request.complete()));
    final recordA = await futureA;
    expect(recordA, isNotNull);
    expect(tabA.state.currentRecord!.providers, hasLength(parallelA ? 2 : 1));
    expect(await state.storage.recordCount(), 2);
  }

  test('单模型 + 并行模型在不同 tab 独立执行', () async {
    await verifyParallelIsolation(parallelA: false, parallelB: true);
  });

  test('并行 + 并行在不同 tab 独立执行', () async {
    await verifyParallelIsolation(parallelA: true, parallelB: true);
  });

  test('异常保留当前 tab 已接收的部分文本', () async {
    final tab = configureTab(state.tabs.activeTab, 'error raw');
    final future = state.startOptimize(tabId: tab.state.id);
    await llm.waitForRequests(1);

    llm.requests.single.emit('partial before error');
    await llm.requests.single.fail(
      const LlmException(LlmErrorKind.unauthorized, '401', statusCode: 401),
    );

    expect(await future, isNull);
    expect(tab.state.status, OptimizationRunStatus.error);
    expect(tab.state.streaming['a'], 'partial before error');
    expect(tab.state.errorMessage, contains('API KEY'));
    expect(await state.storage.recordCount(), 0);
  });

  test('deleteRecord 清理所有 tab 引用并将成功态重置为 empty', () async {
    final first = state.tabs.activeTab;
    final second = state.tabs.addTab();
    final third = state.tabs.addTab();
    final shared = _historyRecord('shared');
    final other = _historyRecord('other');
    for (final tab in [first, second]) {
      tab.state.currentRecord = shared;
      tab.state.status = OptimizationRunStatus.success;
    }
    third.state.currentRecord = other;
    third.state.status = OptimizationRunStatus.success;

    await state.deleteRecord(shared.id);

    for (final tab in [first, second]) {
      expect(tab.state.currentRecord, isNull);
      expect(tab.state.status, OptimizationRunStatus.empty);
    }
    expect(third.state.currentRecord!.id, 'other',
        reason: '引用其他记录的 tab 不受影响');
    expect(third.state.status, OptimizationRunStatus.success);
  });

  test('openRecord 新建并激活 tab，回填字段且不覆盖原 tab 的进行中请求', () async {
    final tabA = configureTab(state.tabs.activeTab, 'origin-A');
    final futureA = state.startOptimize(tabId: tabA.state.id);
    await llm.waitForRequests(1);
    final request = llm.requests.single;
    request.emit('A-1');
    expect(tabA.state.streaming['a'], 'A-1');

    // 历史页调用 openRecord：新建并激活独立 tab，回填 record/raw/scene/mode/status/controller
    final opened = _historyRecord('opened');
    await state.openRecord(opened);
    final newTab = state.tabs.activeTab;
    expect(newTab.state.id, isNot(tabA.state.id));
    expect(state.tabs.tabs, hasLength(2));
    expect(newTab.state.currentRecord!.id, 'opened');
    expect(newTab.state.rawText, 'raw-opened');
    expect(newTab.state.sceneId, opened.scene);
    expect(newTab.state.mode, opened.mode);
    expect(newTab.state.status, OptimizationRunStatus.success);
    expect(newTab.controller.text, 'raw-opened');

    // 原 tab 的输入不被覆盖；后台请求继续写回原 tab，不写新 tab
    expect(tabA.state.rawText, 'origin-A');
    expect(tabA.controller.text, 'origin-A');
    request.emit('A-2');
    expect(tabA.state.streaming['a'], 'A-1A-2');
    expect(newTab.state.streaming, isEmpty);
    await request.complete();
    final recordA = await futureA;

    expect(recordA, isNotNull);
    expect(tabA.state.status, OptimizationRunStatus.success);
    expect(tabA.state.currentRecord, same(recordA));
    expect(tabA.state.rawText, 'origin-A');
    expect(newTab.state.currentRecord!.id, 'opened',
        reason: '新 tab 的回填记录不被后台 run 覆盖');
    expect(newTab.state.status, OptimizationRunStatus.success);
  });

  test('切 tab 后后台 SSE 请求的流式 delta 继续写回原 tab', () async {
    final tabA = configureTab(state.tabs.activeTab, 'sse-A');
    final futureA = state.startOptimize(tabId: tabA.state.id);
    await llm.waitForRequests(1);
    llm.requests.single.emit('s1');
    expect(tabA.state.streaming['a'], 's1');

    // 切走：新增并激活 tab B（真实切换，不是直接写字段）
    final tabB = configureTab(state.tabs.addTab(), 'active-B');
    expect(state.tabs.activeTab, same(tabB));

    llm.requests.single.emit('s2');
    expect(tabA.state.streaming['a'], 's1s2',
        reason: '切 tab 后 SSE 继续写回原 tab');
    expect(tabA.state.status, OptimizationRunStatus.streaming);
    expect(tabB.state.streaming, isEmpty);
    expect(tabB.state.rawText, 'active-B');

    await llm.requests.single.complete();
    final recordA = await futureA;

    expect(recordA, isNotNull);
    expect(tabA.state.currentRecord, same(recordA));
    expect(tabA.state.status, OptimizationRunStatus.success);
    expect(tabB.state.currentRecord, isNull);
    expect(tabB.state.status, OptimizationRunStatus.empty);
    expect(state.session, same(tabB.state));
  });

  test('deleteService 清理所有 tab 的服务与并行引用', () async {
    await state.saveService(
      testService(id: 'b', provider: 'kimi', isDefault: false),
      apiKey: 'key-b',
    );
    final first = state.tabs.activeTab;
    final second = state.tabs.addTab();
    for (final tab in [first, second]) {
      tab.state.sessionServiceId = 'b';
      tab.state.parallelServiceId = 'b';
    }

    await state.deleteService(
      state.services.firstWhere((service) => service.id == 'b'),
    );

    for (final tab in [first, second]) {
      expect(tab.state.sessionServiceId, isEmpty);
      expect(tab.state.parallelServiceId, isNull);
    }
  });

  test('deletePreset 清理所有 tab 引用，且不同 tab 的其他配置不互相污染', () async {
    await state.savePreset(
        const CodingPreset(id: 'p1', name: 'P1', content: 'c1', createdAt: 1));
    await state.savePreset(
        const CodingPreset(id: 'p2', name: 'P2', content: 'c2', createdAt: 2));
    final first = state.tabs.activeTab;
    final second = state.tabs.addTab();
    final third = state.tabs.addTab();
    for (final tab in [first, second]) {
      tab.state.presetId = 'p1';
    }
    third.state.presetId = 'p2';
    third.state.sceneId = 'ai_coding';

    await state.deletePreset('p1');

    for (final tab in [first, second]) {
      expect(tab.state.presetId, isNull);
      expect(state.selectedPresetFor(tab.state.id), isNull);
    }
    expect(third.state.presetId, 'p2', reason: '其他 tab 的预置词引用不受影响');
    expect(state.selectedPresetFor(third.state.id)!.id, 'p2');
    expect(third.state.sceneId, 'ai_coding', reason: '其他 tab 的场景选择不被污染');
  });

  test('deleteTemplate 重置所有 tab 的场景引用，不影响其他场景选择', () async {
    await state.saveTemplate(const SceneTemplate(
        id: 'my', name: '我的场景', promptHint: '自定义指引'));
    final first = state.tabs.activeTab;
    final second = state.tabs.addTab();
    final third = state.tabs.addTab();
    for (final tab in [first, second]) {
      tab.state.sceneId = 'my';
    }
    third.state.sceneId = 'ai_coding';

    await state.deleteTemplate('my');

    for (final tab in [first, second]) {
      expect(tab.state.sceneId, kDefaultScene.id,
          reason: '引用被删模板的 tab 回退默认场景');
    }
    expect(third.state.sceneId, 'ai_coding', reason: '其他 tab 的场景选择不受影响');
    expect(state.customTemplates, isEmpty);
  });

  test('setDefaultService 清理所有 tab 的同 id 并行引用，不影响其他配置', () async {
    await state.saveService(
      testService(id: 'b', provider: 'kimi', isDefault: false),
      apiKey: 'key-b',
    );
    await state.saveService(
      testService(id: 'c', provider: 'kimi', isDefault: false),
      apiKey: 'key-c',
    );
    final first = state.tabs.activeTab;
    final second = state.tabs.addTab();
    final third = state.tabs.addTab();
    for (final tab in [first, second]) {
      tab.state.parallelServiceId = 'b';
    }
    third.state.parallelServiceId = 'c';
    third.state.sessionServiceId = 'c';
    third.state.presetId = 'keep';

    await state.setDefaultService('b');

    for (final tab in [first, second]) {
      expect(tab.state.parallelServiceId, isNull,
          reason: '默认服务与并行对比服务不得相同');
    }
    expect(third.state.parallelServiceId, 'c', reason: '其他并行引用不受影响');
    expect(third.state.sessionServiceId, 'c', reason: '会话生效服务不被污染');
    expect(third.state.presetId, 'keep', reason: '预置词引用不被污染');
    expect(state.defaultService!.id, 'b');
  });

  test('finalizeAsk 防重入并快照问题与答案', () async {
    final tab = configureTab(state.tabs.activeTab, 'ask raw');
    tab.state.mode = OptimizeMode.ask;
    final asking = state.startOptimize(tabId: tab.state.id);
    await llm.waitForRequests(1);
    llm.requests.single.emit(kValidQuestionsJson);
    await llm.requests.single.complete();
    expect(await asking, isNull);
    expect(tab.state.askAnswering, isTrue);
    expect(tab.state.status, OptimizationRunStatus.empty);

    tab.state.answers[0] = 'original answer';
    final first = state.finalizeAsk(tabId: tab.state.id);
    final duplicate = state.finalizeAsk(tabId: tab.state.id);
    tab.state.answers[0] = 'mutated after submit';

    expect(await duplicate, isNull);
    await llm.waitForRequests(2);
    expect(llm.requests, hasLength(2));
    final finalRequest = llm.requests[1];
    expect(finalRequest.body, contains('A1：original answer'));
    expect(finalRequest.body, isNot(contains('mutated after submit')));

    finalRequest.emit('ask final');
    await finalRequest.complete();
    final record = await first;
    expect(record, isNotNull);
    expect(tab.state.askAnswering, isFalse);
    expect(tab.state.status, OptimizationRunStatus.success);
    expect(llm.requests, hasLength(2));
  });
}

extension on _ControlledRequest {
  String get serviceId => request.apiKey == 'key-a' ? 'a' : 'b';
}
