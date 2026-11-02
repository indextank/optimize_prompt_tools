import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/optimize_engine.dart';
import 'package:prompt_optimizer/services/parallel_scheduler.dart';
import 'package:prompt_optimizer/state/workbench_tabs.dart';

WorkbenchTabsController createTabsController() {
  return WorkbenchTabsController(
    stateFactory: (id, title) => OptimizationTabState(id: id, title: title),
  );
}

ParallelRunHandle createRunHandle(void Function() onCancel) {
  return ParallelRunHandle(
    events: const Stream<ParallelEvent>.empty(),
    states: <ParallelRunState>[],
    droppedServices: <ServiceConfig>[],
    done: Future<void>.value(),
    onCancel: onCancel,
  );
}

void expectControllerDisposed(TextEditingController controller) {
  expect(
    () => controller.text = 'must not be accepted',
    throwsA(isA<FlutterError>()),
  );
}

void main() {
  group('OptimizationTabState', () {
    test('has business defaults and independent mutable collections', () {
      final first = OptimizationTabState(id: 'first', title: 'First');
      final second = OptimizationTabState(id: 'second', title: 'Second');

      expect(first.rawText, '');
      expect(first.mode, OptimizeMode.deep);
      expect(first.sceneId, kDefaultScene.id);
      expect(first.sessionServiceId, '');
      expect(first.outputStyle, OutputStyle.simple);
      expect(first.parallelServiceId, isNull);
      expect(first.presetId, isNull);
      expect(first.parallelEnabled, isFalse);
      expect(first.currentRecord, isNull);
      expect(first.singleResult, isNull);
      expect(first.streaming, isEmpty);
      expect(first.parallelStates, isEmpty);
      expect(first.droppedProviderNames, isEmpty);
      expect(first.askAnswering, isFalse);
      expect(first.questions, isEmpty);
      expect(first.answers, isEmpty);
      expect(first.status, OptimizationRunStatus.empty);
      expect(first.errorMessage, isNull);
      expect(first.isEmpty, isTrue);
      expect(first.optimizing, isFalse);

      first.streaming['service'] = 'partial';
      first.droppedProviderNames.add('Dropped');
      first.answers.add(null);
      expect(second.streaming, isEmpty);
      expect(second.droppedProviderNames, isEmpty);
      expect(second.answers, isEmpty);
    });

    test('exposes empty, loading, streaming, success and error states', () {
      final state = OptimizationTabState(id: 'tab', title: 'Tab');

      state.status = OptimizationRunStatus.empty;
      expect(state.isEmpty, isTrue);
      expect(state.optimizing, isFalse);

      state.status = OptimizationRunStatus.loading;
      expect(state.isEmpty, isFalse);
      expect(state.optimizing, isTrue);

      state.status = OptimizationRunStatus.streaming;
      expect(state.isEmpty, isFalse);
      expect(state.optimizing, isTrue);

      state.status = OptimizationRunStatus.success;
      expect(state.isEmpty, isFalse);
      expect(state.optimizing, isFalse);

      state.status = OptimizationRunStatus.error;
      state.errorMessage = 'failed';
      expect(state.status, OptimizationRunStatus.error);
      expect(state.errorMessage, 'failed');
      expect(state.optimizing, isFalse);
      expect(state.isEmpty, isFalse);
    });

    test('reset preserves input, configuration and record but clears run data', () {
      const record = OptimizeRecord(
        id: 'record',
        scene: 'general',
        mode: OptimizeMode.deep,
        rawText: 'raw',
        versions: <OptimizeVersion>[],
        providers: <String>['service'],
        createdAt: 1,
      );
      const singleResult = EngineRunResult(
        result: OptimizeResult(rawText: 'result'),
        elapsedMs: 1,
      );
      final parallelState = ParallelRunState(
        service: const ServiceConfig(
          id: 'service',
          provider: 'Provider',
          apiUrl: 'https://example.test',
        ),
        apiKey: 'key',
      );
      const question = ClarifyQuestion(
        question: 'Which audience?',
        decides: 'Tone',
      );
      final state = OptimizationTabState(
        id: 'tab',
        title: 'Tab',
        rawText: 'keep this input',
        mode: OptimizeMode.quick,
        sceneId: 'custom-scene',
        sessionServiceId: 'session-service',
        outputStyle: OutputStyle.full,
        parallelServiceId: 'parallel-service',
        presetId: 'preset',
        parallelEnabled: true,
        currentRecord: record,
        singleResult: singleResult,
        streaming: <String, String>{'service': 'partial'},
        parallelStates: <String, ParallelRunState>{'service': parallelState},
        droppedProviderNames: <String>['Dropped'],
        askAnswering: true,
        questions: <ClarifyQuestion>[question],
        answers: <String?>['answer', null],
        status: OptimizationRunStatus.error,
        errorMessage: 'failure',
      );

      state.reset();

      expect(state.id, 'tab');
      expect(state.title, 'Tab');
      expect(state.rawText, 'keep this input');
      expect(state.mode, OptimizeMode.quick);
      expect(state.sceneId, 'custom-scene');
      expect(state.sessionServiceId, 'session-service');
      expect(state.outputStyle, OutputStyle.full);
      expect(state.parallelServiceId, 'parallel-service');
      expect(state.presetId, 'preset');
      expect(state.parallelEnabled, isTrue);
      expect(state.currentRecord, same(record));
      expect(state.streaming, isEmpty);
      expect(state.parallelStates, isEmpty);
      expect(state.singleResult, isNull);
      expect(state.droppedProviderNames, isEmpty);
      expect(state.askAnswering, isFalse);
      expect(state.questions, isEmpty);
      expect(state.answers, isEmpty);
      expect(state.errorMessage, isNull);
      expect(state.status, OptimizationRunStatus.empty);
    });
  });

  group('WorkbenchTabRuntime', () {
    test('controller starts from rawText and writes back through its listener', () {
      final state = OptimizationTabState(
        id: 'tab',
        title: 'Tab',
        rawText: 'initial',
      );
      var changes = 0;
      final runtime = WorkbenchTabRuntime(
        state: state,
        onChanged: () => changes++,
      );

      expect(runtime.controller.text, 'initial');
      runtime.controller.text = 'edited';
      expect(state.rawText, 'edited');
      expect(changes, 1);

      runtime.dispose();
    });

    test('disposed getter reports runtime disposal state', () {
      final runtime = WorkbenchTabRuntime(
        state: OptimizationTabState(id: 'tab', title: 'Tab'),
      );
      expect(runtime.disposed, isFalse);

      runtime.dispose();
      expect(runtime.disposed, isTrue);

      runtime.dispose(); // 幂等
      expect(runtime.disposed, isTrue);
    });

    test('tracks run generations and supports invalidation', () {
      final runtime = WorkbenchTabRuntime(
        state: OptimizationTabState(id: 'tab', title: 'Tab'),
      );

      final firstRun = runtime.beginRun();
      expect(runtime.isCurrent(firstRun), isTrue);
      expect(runtime.isCurrent(firstRun + 1), isFalse);

      final secondRun = runtime.beginRun();
      expect(secondRun, greaterThan(firstRun));
      expect(runtime.isCurrent(firstRun), isFalse);
      expect(runtime.isCurrent(secondRun), isTrue);

      runtime.invalidateRun();
      expect(runtime.isCurrent(secondRun), isFalse);
      runtime.dispose();
    });

    test('dispose cancels resources, disposes controller and is idempotent', () async {
      final state = OptimizationTabState(id: 'tab', title: 'Tab');
      final token = CancelToken();
      var handleCancels = 0;
      final handle = createRunHandle(() => handleCancels++);
      final runtime = WorkbenchTabRuntime(
        state: state,
        onChanged: () {},
      );
      runtime.cancelToken = token;
      runtime.parallelRun = handle;
      final run = runtime.beginRun();

      runtime.dispose();

      expect(runtime.isCurrent(run), isFalse);
      expect(token.isCancelled, isTrue);
      expect(handle.isCancelled, isTrue);
      expect(handleCancels, 1);
      await Future<void>.value();
      expectControllerDisposed(runtime.controller);

      runtime.dispose();
      final runAfterDispose = runtime.beginRun();
      expect(runtime.isCurrent(runAfterDispose), isFalse);
      expect(handleCancels, 1);
    });
  });

  group('WorkbenchTabsController', () {
    test('starts with one fixed workbench tab and an unmodifiable view', () {
      final controller = createTabsController();

      expect(controller.tabs, hasLength(1));
      expect(controller.activeIndex, 0);
      expect(controller.activeTab, same(controller.tabs.single));
      expect(controller.activeTab.state.title, '工作台');
      expect(controller.activeTab.state.id, isNotEmpty);
      expect(() => controller.tabs.clear(), throwsUnsupportedError);
      expect(controller.closeTab(controller.activeTab.state.id), isFalse);
      expect(controller.tabs, hasLength(1));

      controller.dispose();
    });

    test('addTab creates uniquely identified session tabs and activates them', () {
      final controller = createTabsController();
      final fixed = controller.activeTab;
      var notifications = 0;
      controller.addListener(() => notifications++);

      final first = controller.addTab();
      expect(first.state.title, '会话 1');
      expect(controller.activeTab, same(first));
      expect(controller.activeIndex, 1);

      final second = controller.addTab();
      expect(second.state.title, '会话 2');
      expect(controller.activeTab, same(second));
      expect(controller.activeIndex, 2);
      expect(notifications, 2);
      expect(
        <String>{fixed.state.id, first.state.id, second.state.id},
        hasLength(3),
      );

      controller.dispose();
    });

    test('rejects a stateFactory result that replaces the generated id', () {
      var factoryCalls = 0;
      final controller = WorkbenchTabsController(
        stateFactory: (id, title) {
          factoryCalls++;
          return OptimizationTabState(
            id: factoryCalls == 1 ? id : 'conflicting-fixed-id',
            title: title,
          );
        },
      );
      final fixed = controller.activeTab;

      expect(() => controller.addTab(), throwsStateError);
      expect(controller.tabs, <WorkbenchTabRuntime>[fixed]);
      expect(controller.activeTab, same(fixed));

      controller.dispose();
    });

    test('does not reuse a closed tab id when adding a replacement', () {
      final controller = createTabsController();
      final fixedId = controller.activeTab.state.id;
      final removed = controller.addTab();
      final removedId = removed.state.id;

      expect(controller.closeTab(removedId), isTrue);
      final replacement = controller.addTab();

      expect(replacement.state.id, isNot(removedId));
      expect(replacement.state.id, isNot(fixedId));
      expect(
        <String>{fixedId, removedId, replacement.state.id},
        hasLength(3),
      );
      expect(replacement.state.title, '会话 2');

      controller.dispose();
    });

    test('rejects closing fixed or unknown tabs without disposal or notification', () {
      final controller = createTabsController();
      final fixed = controller.activeTab;
      final token = CancelToken();
      var handleCancels = 0;
      fixed.cancelToken = token;
      fixed.parallelRun = createRunHandle(() => handleCancels++);
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.closeTab(fixed.state.id), isFalse);
      expect(controller.closeTab('missing'), isFalse);
      expect(controller.tabs, hasLength(1));
      expect(controller.activeTab, same(fixed));
      expect(token.isCancelled, isFalse);
      expect(handleCancels, 0);
      expect(notifications, 0);
      fixed.controller.text = 'still usable';
      expect(fixed.state.rawText, 'still usable');

      controller.dispose();
    });

    test('ignores invalid switch, update, lookup and touch operations', () {
      final controller = createTabsController();
      final second = controller.addTab();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.switchTab(-1);
      controller.switchTab(controller.tabs.length);
      expect(controller.activeTab, same(second));
      expect(controller.updateTab('missing', (_) {}), isFalse);
      expect(controller.tabById('missing'), isNull);
      controller.touch('missing');
      expect(notifications, 0);

      controller.switchTab(0);
      expect(controller.activeIndex, 0);
      expect(notifications, 1);
      controller.touch(controller.activeTab.state.id);
      expect(notifications, 2);

      controller.dispose();
    });

    test('closing current tab selects its original right-hand neighbor', () {
      final controller = createTabsController();
      final fixed = controller.activeTab;
      final middle = controller.addTab();
      final right = controller.addTab();
      controller.switchTab(1);

      expect(controller.closeTab(middle.state.id), isTrue);
      expect(controller.tabs.map((tab) => tab.state), <OptimizationTabState>[
        fixed.state,
        right.state,
      ]);
      expect(controller.activeIndex, 1);
      expect(controller.activeTab, same(right));

      controller.dispose();
    });

    test('closing current last tab selects its left-hand neighbor', () {
      final controller = createTabsController();
      final fixed = controller.activeTab;
      final middle = controller.addTab();
      final last = controller.addTab();

      expect(controller.closeTab(last.state.id), isTrue);
      expect(controller.tabs.map((tab) => tab.state), <OptimizationTabState>[
        fixed.state,
        middle.state,
      ]);
      expect(controller.activeIndex, 1);
      expect(controller.activeTab, same(middle));

      controller.dispose();
    });

    test('closing a tab before the current one decrements activeIndex', () {
      final controller = createTabsController();
      controller.addTab();
      final before = controller.addTab();
      final current = controller.addTab();
      final after = controller.addTab();
      controller.switchTab(3);
      final previousIndex = controller.activeIndex;

      expect(controller.closeTab(before.state.id), isTrue);
      expect(controller.activeIndex, previousIndex - 1);
      expect(controller.activeTab, same(current));
      expect(controller.tabs.last, same(after));

      controller.dispose();
    });

    test('closing a tab after the current one preserves activeIndex', () {
      final controller = createTabsController();
      final fixed = controller.activeTab;
      final current = controller.addTab();
      final after = controller.addTab();
      controller.switchTab(1);

      expect(controller.closeTab(after.state.id), isTrue);
      expect(controller.activeIndex, 1);
      expect(controller.activeTab, same(current));
      expect(controller.tabs.map((tab) => tab.state), <OptimizationTabState>[
        fixed.state,
        current.state,
      ]);

      controller.dispose();
    });

    test('updateTab changes only the requested state and notifies once', () {
      final controller = createTabsController();
      final first = controller.activeTab;
      final second = controller.addTab();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final updated = controller.updateTab(first.state.id, (state) {
        state.title = 'Updated';
        state.rawText = 'first only';
        state.status = OptimizationRunStatus.loading;
      });

      expect(updated, isTrue);
      expect(first.state.title, 'Updated');
      expect(first.state.rawText, 'first only');
      expect(first.state.status, OptimizationRunStatus.loading);
      expect(second.state.title, '会话 1');
      expect(second.state.rawText, '');
      expect(second.state.status, OptimizationRunStatus.empty);
      expect(notifications, 1);
      expect(controller.tabById(first.state.id), same(first));

      controller.dispose();
    });

    test('updateTab synchronizes rawText to its controller and notifies once', () {
      final controller = createTabsController();
      final tab = controller.activeTab;
      var notifications = 0;
      controller.addListener(() => notifications++);

      final updated = controller.updateTab(tab.state.id, (state) {
        state.rawText = 'programmatic edit';
      });

      expect(updated, isTrue);
      expect(tab.state.rawText, 'programmatic edit');
      expect(tab.controller.text, 'programmatic edit');
      expect(notifications, 1);

      tab.controller.text = 'user edit after synchronization';
      expect(tab.state.rawText, 'user edit after synchronization');
      expect(notifications, 2);

      controller.dispose();
    });

    test('each input controller writes back to its own tab even when inactive', () {
      final controller = createTabsController();
      final first = controller.activeTab;
      final second = controller.addTab();
      var notifications = 0;
      controller.addListener(() => notifications++);

      first.controller.text = 'edited inactive tab';
      expect(first.state.rawText, 'edited inactive tab');
      expect(second.state.rawText, '');
      expect(second.controller.text, '');
      expect(controller.activeTab, same(second));
      expect(notifications, 1);

      second.controller.text = 'edited active tab';
      expect(second.state.rawText, 'edited active tab');
      expect(first.state.rawText, 'edited inactive tab');
      expect(first.controller.text, 'edited inactive tab');
      expect(notifications, 2);

      controller.dispose();
    });

    test('controllers retain independent text and initial rawText', () {
      final controller = WorkbenchTabsController(
        stateFactory: (id, title) => OptimizationTabState(
          id: id,
          title: title,
          rawText: 'initial $title',
        ),
      );
      final first = controller.activeTab;
      final second = controller.addTab();

      expect(first.controller.text, 'initial 工作台');
      expect(second.controller.text, 'initial 会话 1');
      first.controller.text = 'first text';
      expect(second.controller.text, 'initial 会话 1');
      expect(second.state.rawText, 'initial 会话 1');
      second.controller.text = 'second text';
      expect(first.controller.text, 'first text');
      expect(first.state.rawText, 'first text');

      controller.dispose();
    });

    test('closing a tab disposes only that tab resources', () async {
      final controller = createTabsController();
      final first = controller.activeTab;
      final target = controller.addTab();
      final third = controller.addTab();
      final firstToken = CancelToken();
      final targetToken = CancelToken();
      final thirdToken = CancelToken();
      var firstCancels = 0;
      var targetCancels = 0;
      var thirdCancels = 0;
      first.cancelToken = firstToken;
      target.cancelToken = targetToken;
      third.cancelToken = thirdToken;
      first.parallelRun = createRunHandle(() => firstCancels++);
      target.parallelRun = createRunHandle(() => targetCancels++);
      third.parallelRun = createRunHandle(() => thirdCancels++);

      expect(controller.closeTab(target.state.id), isTrue);

      expect(firstToken.isCancelled, isFalse);
      expect(thirdToken.isCancelled, isFalse);
      expect(firstCancels, 0);
      expect(thirdCancels, 0);
      expect(targetToken.isCancelled, isTrue);
      expect(targetCancels, 1);
      await Future<void>.value();
      expectControllerDisposed(target.controller);

      first.controller.text = 'first remains live';
      third.controller.text = 'third remains live';
      expect(first.state.rawText, 'first remains live');
      expect(third.state.rawText, 'third remains live');

      controller.dispose();
      expect(firstToken.isCancelled, isTrue);
      expect(thirdToken.isCancelled, isTrue);
      expect(firstCancels, 1);
      expect(thirdCancels, 1);
      expect(targetCancels, 1);
    });

    test('closing from input notification defers controller disposal safely', () async {
      final controller = createTabsController();
      final second = controller.addTab();
      final secondId = second.state.id;
      addTearDown(() async {
        await Future<void>.value();
        controller.dispose();
        second.dispose();
      });
      controller.addListener(() {
        if (controller.tabById(secondId) != null) {
          expect(controller.closeTab(secondId), isTrue);
        }
      });

      second.controller.text = 'close during input notification';

      expect(controller.tabById(secondId), isNull);
      expect(controller.tabs, hasLength(1));
      await Future<void>.value();
      expectControllerDisposed(second.controller);
    });

    test('closing from a direct controller listener is also safe', () async {
      final controller = createTabsController();
      final tab = controller.addTab();
      final tabId = tab.state.id;
      final token = CancelToken();
      var handleCancels = 0;
      final handle = createRunHandle(() => handleCancels++);
      tab.cancelToken = token;
      tab.parallelRun = handle;
      addTearDown(() async {
        controller.dispose();
        tab.dispose();
        await Future<void>.value();
      });
      tab.controller.addListener(() {
        if (controller.tabById(tabId) != null) {
          expect(controller.closeTab(tabId), isTrue);
        }
      });

      tab.controller.text = 'close from a direct controller listener';

      expect(controller.tabById(tabId), isNull);
      expect(token.isCancelled, isTrue);
      expect(handle.isCancelled, isTrue);
      expect(handleCancels, 1);
      await Future<void>.value();
      expectControllerDisposed(tab.controller);
    });

    test('parallel cancel reentrant close cannot remove a different tab', () async {
      final controller = createTabsController();
      final second = controller.addTab();
      final third = controller.addTab();
      addTearDown(() {
        controller.dispose();
        second.dispose();
        third.dispose();
      });
      var cancelCallbacks = 0;
      var reentrantCloseResult = true;
      second.parallelRun = createRunHandle(() {
        cancelCallbacks++;
        reentrantCloseResult = controller.closeTab(second.state.id);
      });

      expect(controller.closeTab(second.state.id), isTrue);

      expect(reentrantCloseResult, isFalse);
      expect(cancelCallbacks, 1);
      expect(controller.tabById(second.state.id), isNull);
      expect(controller.tabById(third.state.id), same(third));
      expect(controller.tabs, hasLength(2));
      await Future<void>.value();
      expectControllerDisposed(second.controller);
      third.controller.text = 'third remains usable';
      expect(third.state.rawText, 'third remains usable');
    });

    test('selection-only controller changes do not notify tabs', () {
      final controller = createTabsController();
      final tab = controller.activeTab;
      addTearDown(controller.dispose);
      tab.controller.text = 'selection text';
      var notifications = 0;
      controller.addListener(() => notifications++);

      tab.controller.selection = const TextSelection.collapsed(offset: 4);

      expect(tab.state.rawText, 'selection text');
      expect(notifications, 0);
    });

    test('controller dispose releases every remaining runtime', () async {
      final controller = createTabsController();
      final first = controller.activeTab;
      final second = controller.addTab();
      final firstToken = CancelToken();
      final secondToken = CancelToken();
      var firstCancels = 0;
      var secondCancels = 0;
      first.cancelToken = firstToken;
      second.cancelToken = secondToken;
      first.parallelRun = createRunHandle(() => firstCancels++);
      second.parallelRun = createRunHandle(() => secondCancels++);

      controller.dispose();

      expect(firstToken.isCancelled, isTrue);
      expect(secondToken.isCancelled, isTrue);
      expect(firstCancels, 1);
      expect(secondCancels, 1);
      await Future<void>.value();
      expectControllerDisposed(first.controller);
      expectControllerDisposed(second.controller);
      expect(
        () => controller.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );
    });

    test('always retains at least the fixed tab', () {
      final controller = createTabsController();
      final first = controller.addTab();
      final second = controller.addTab();
      final fixedId = controller.tabs.first.state.id;

      expect(controller.closeTab(first.state.id), isTrue);
      expect(controller.closeTab(second.state.id), isTrue);
      expect(controller.tabs, hasLength(1));
      expect(controller.activeIndex, 0);
      expect(controller.closeTab(fixedId), isFalse);
      expect(controller.tabs, hasLength(1));
      expect(controller.activeTab.state.id, fixedId);

      controller.dispose();
    });
  });
}
