import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/widgets.dart';

import '../core/models.dart';
import '../services/optimize_engine.dart';
import '../services/parallel_scheduler.dart';

/// 单个工作台 tab 的优化运行状态。
enum OptimizationRunStatus { empty, loading, streaming, success, error }

/// 可独立保存、切换和恢复的工作台业务数据。
class OptimizationTabState {
  OptimizationTabState({
    required this.id,
    required this.title,
    this.rawText = '',
    this.mode = OptimizeMode.deep,
    String? sceneId,
    this.sessionServiceId = '',
    this.outputStyle = OutputStyle.simple,
    this.parallelServiceId,
    this.presetId,
    this.parallelEnabled = false,
    this.currentRecord,
    this.singleResult,
    Map<String, String> streaming = const <String, String>{},
    Map<String, ParallelRunState> parallelStates =
        const <String, ParallelRunState>{},
    List<String> droppedProviderNames = const <String>[],
    this.askAnswering = false,
    List<ClarifyQuestion> questions = const <ClarifyQuestion>[],
    List<String?> answers = const <String?>[],
    this.status = OptimizationRunStatus.empty,
    this.errorMessage,
  })  : sceneId = sceneId ?? kDefaultScene.id,
        streaming = Map<String, String>.of(streaming),
        parallelStates = Map<String, ParallelRunState>.of(parallelStates),
        droppedProviderNames = List<String>.of(droppedProviderNames),
        questions = List<ClarifyQuestion>.of(questions),
        answers = List<String?>.of(answers);

  final String id;
  String title;
  String rawText;
  OptimizeMode mode;
  String sceneId;
  String sessionServiceId;
  OutputStyle outputStyle;
  String? parallelServiceId;
  String? presetId;
  bool parallelEnabled;

  OptimizeRecord? currentRecord;
  EngineRunResult? singleResult;
  Map<String, String> streaming;
  Map<String, ParallelRunState> parallelStates;
  List<String> droppedProviderNames;

  bool askAnswering;
  List<ClarifyQuestion> questions;
  List<String?> answers;

  OptimizationRunStatus status;
  String? errorMessage;

  bool get optimizing =>
      status == OptimizationRunStatus.loading ||
      status == OptimizationRunStatus.streaming;

  bool get isEmpty => status == OptimizationRunStatus.empty;

  /// 清除一次运行的临时数据，保留输入、配置及当前历史记录。
  void reset() {
    streaming.clear();
    parallelStates.clear();
    singleResult = null;
    droppedProviderNames.clear();
    askAnswering = false;
    questions.clear();
    answers.clear();
    status = OptimizationRunStatus.empty;
    errorMessage = null;
  }
}

/// 仅属于单个 tab 的控制器、取消句柄及运行代际。
class WorkbenchTabRuntime {
  WorkbenchTabRuntime({
    required this.state,
    void Function()? onChanged,
  })  : _onChanged = onChanged,
        controller = TextEditingController(text: state.rawText) {
    controller.addListener(_handleInput);
  }

  final OptimizationTabState state;
  final TextEditingController controller;
  final void Function()? _onChanged;

  CancelToken? cancelToken;
  ParallelRunHandle? parallelRun;

  int _generation = 0;
  bool _disposed = false;
  bool _synchronizing = false;

  /// 该 runtime 是否已释放（异步回调写入前的资源竞态防护）。
  bool get disposed => _disposed;

  void _handleInput() {
    if (_synchronizing || state.rawText == controller.text) return;
    state.rawText = controller.text;
    _onChanged?.call();
  }

  /// 将程序化输入变更同步到控制器，不触发额外的输入通知。
  void syncControllerFromState() {
    if (controller.text == state.rawText) return;
    _synchronizing = true;
    try {
      controller.text = state.rawText;
    } finally {
      _synchronizing = false;
    }
  }

  int beginRun() => ++_generation;

  bool isCurrent(int run) => !_disposed && run == _generation;

  void invalidateRun() {
    _generation++;
  }

  /// 释放该 tab 独占的资源；重复调用不会重复取消或销毁。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    cancelToken?.cancel('workbench_tab_disposed');
    parallelRun?.cancel();
    controller.removeListener(_handleInput);
    scheduleMicrotask(controller.dispose);
  }
}

/// 管理固定工作台与可关闭会话 tab，并同步各 tab 的输入变更。
class WorkbenchTabsController extends ChangeNotifier {
  WorkbenchTabsController({
    required OptimizationTabState Function(String id, String title) stateFactory,
  }) : _stateFactory = stateFactory {
    _tabs.add(_createRuntime('工作台'));
  }

  final OptimizationTabState Function(String id, String title) _stateFactory;
  final List<WorkbenchTabRuntime> _tabs = <WorkbenchTabRuntime>[];

  int _activeIndex = 0;
  int _nextId = 0;
  int _nextSessionNumber = 1;

  UnmodifiableListView<WorkbenchTabRuntime> get tabs =>
      UnmodifiableListView<WorkbenchTabRuntime>(_tabs);

  int get activeIndex => _activeIndex;

  WorkbenchTabRuntime get activeTab => _tabs[_activeIndex];

  WorkbenchTabRuntime _createRuntime(String title) {
    final id = 'workbench-tab-${_nextId++}';
    final state = _stateFactory(id, title);
    if (state.id != id) {
      throw StateError('stateFactory must preserve the generated tab id');
    }
    return WorkbenchTabRuntime(
      state: state,
      onChanged: notifyListeners,
    );
  }

  WorkbenchTabRuntime addTab() {
    final runtime = _createRuntime('会话 $_nextSessionNumber');
    _nextSessionNumber++;
    _tabs.add(runtime);
    _activeIndex = _tabs.length - 1;
    notifyListeners();
    return runtime;
  }

  bool closeTab(String id) {
    final index = _tabs.indexWhere((runtime) => runtime.state.id == id);
    if (index <= 0) return false;

    final closingActive = index == _activeIndex;
    final runtime = _tabs.removeAt(index);

    if (index < _activeIndex) {
      _activeIndex--;
    } else if (closingActive && _activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    }

    runtime.dispose();
    notifyListeners();
    return true;
  }

  void switchTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  bool updateTab(String id, void Function(OptimizationTabState) update) {
    final runtime = tabById(id);
    if (runtime == null) return false;
    update(runtime.state);
    runtime.syncControllerFromState();
    notifyListeners();
    return true;
  }

  WorkbenchTabRuntime? tabById(String id) {
    for (final runtime in _tabs) {
      if (runtime.state.id == id) return runtime;
    }
    return null;
  }

  void touch(String id) {
    if (tabById(id) == null) return;
    notifyListeners();
  }

  @override
  void dispose() {
    final runtimes = List<WorkbenchTabRuntime>.of(_tabs);
    _tabs.clear();
    for (final runtime in runtimes) {
      runtime.dispose();
    }
    super.dispose();
  }
}
