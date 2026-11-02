/// 多模型并行调度器：最多 3 个模型并发优化，独立超时/取消/失败隔离。
library;

import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;

import '../core/models.dart';
import 'optimize_engine.dart';

/// 并行调度上限
const int kMaxParallelProviders = 3;

/// 单个模型的运行状态
class ParallelRunState {
  ParallelRunState({required this.service, required this.apiKey});

  final ServiceConfig service;
  final String apiKey;
  final CancelToken cancelToken = CancelToken();

  String streamedText = '';
  EngineRunResult? runResult;
  Object? error;
  bool done = false;
  int elapsedMs = 0;

  bool get success => done && error == null && runResult != null;
}

/// 并行事件
sealed class ParallelEvent {
  const ParallelEvent();
}

/// 某个模型完成（成功或失败均通过此事件通知）
class ParallelItemDone extends ParallelEvent {
  const ParallelItemDone(this.state);
  final ParallelRunState state;
}

/// 全部完成
class ParallelAllDone extends ParallelEvent {
  const ParallelAllDone(this.states);
  final List<ParallelRunState> states;
}

/// 一次并行运行的句柄，用于读取事件与状态并统一取消。
class ParallelRunHandle {
  ParallelRunHandle({
    required this.events,
    required this.states,
    required this.droppedServices,
    required this.done,
    required void Function() onCancel,
  }) : _onCancel = onCancel;

  final Stream<ParallelEvent> events;
  final List<ParallelRunState> states;
  final List<ServiceConfig> droppedServices;
  final Future<void> done;
  final void Function() _onCancel;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final state in states) {
      state.cancelToken.cancel('parallel_cancelled');
    }
    _onCancel();
  }
}

/// 并行调度器
class ParallelScheduler {
  ParallelScheduler({required OptimizeEngine engine}) : _engine = engine;

  final OptimizeEngine _engine;

  /// 并行运行。[services] 与 [apiKeys] 等长；超出上限的服务商将被丢弃并记入返回值。
  ///
  /// 返回包含事件流、实际运行状态和被截断丢弃服务列表的运行句柄。
  ParallelRunHandle run(
    List<ServiceConfig> services,
    List<String> apiKeys,
    String rawText, {
    OptimizeMode mode = OptimizeMode.deep,
    OutputStyle style = OutputStyle.full,
    SceneTemplate scene = kDefaultScene,
    CodingPreset? preset,
    void Function(String serviceId, String accumulated)? onItemProgress,
  }) {
    if (services.length != apiKeys.length) {
      throw ArgumentError('services 与 apiKeys 长度不一致');
    }
    final used = services.take(kMaxParallelProviders).toList();
    final dropped = services.skip(kMaxParallelProviders).toList();
    final usedKeys = apiKeys.take(kMaxParallelProviders).toList();

    final controller = StreamController<ParallelEvent>();
    final states = [
      for (var i = 0; i < used.length; i++)
        ParallelRunState(service: used[i], apiKey: usedKeys[i])
    ];
    var cancelled = false;
    final workerDone = Completer<void>();
    final handle = ParallelRunHandle(
      events: controller.stream,
      states: List.unmodifiable(states),
      droppedServices: List.unmodifiable(dropped),
      done: workerDone.future,
      onCancel: () {
        cancelled = true;
        if (!controller.isClosed) unawaited(controller.close());
      },
    );

    Future(() async {
      try {
        await Future.wait(states.map((st) async {
          final sw = Stopwatch()..start();
          try {
            final res = await _engine.optimize(
              st.service,
              st.apiKey,
              rawText,
              mode: mode,
              style: style,
              scene: scene,
              preset: preset,
              cancelToken: st.cancelToken,
              onProgress: (t) {
                if (cancelled || controller.isClosed) return;
                st.streamedText = t;
                onItemProgress?.call(st.service.id, t);
              },
            );
            if (!cancelled) st.runResult = res;
          } catch (e) {
            if (!cancelled) st.error = e;
          } finally {
            sw.stop();
            if (!cancelled) {
              st.elapsedMs = sw.elapsedMilliseconds;
              st.done = true;
              if (!controller.isClosed) {
                controller.add(ParallelItemDone(st));
              }
            }
          }
        }));
        if (!cancelled && !controller.isClosed) {
          controller.add(ParallelAllDone(List.unmodifiable(states)));
          unawaited(controller.close());
        }
      } finally {
        if (!workerDone.isCompleted) workerDone.complete();
      }
    });

    return handle;
  }
}
