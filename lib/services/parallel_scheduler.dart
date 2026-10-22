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

/// 并行调度器
class ParallelScheduler {
  ParallelScheduler({required OptimizeEngine engine}) : _engine = engine;

  final OptimizeEngine _engine;

  /// 并行运行。[services] 与 [apiKeys] 等长；超出上限的服务商将被丢弃并记入返回值。
  ///
  /// 返回 (事件流, 被截断丢弃的服务列表)。
  (Stream<ParallelEvent>, List<ServiceConfig>) run(
    List<ServiceConfig> services,
    List<String> apiKeys,
    String rawText, {
    OptimizeMode mode = OptimizeMode.deep,
    OutputStyle style = OutputStyle.full,
    SceneTemplate scene = kDefaultScene,
    CodingPreset? preset,
    void Function(String provider, String accumulated)? onItemProgress,
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

    Future(() async {
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
              st.streamedText = t;
              onItemProgress?.call(st.service.id, t);
            },
          );
          st.runResult = res;
        } catch (e) {
          st.error = e;
        } finally {
          sw.stop();
          st.elapsedMs = sw.elapsedMilliseconds;
          st.done = true;
          if (!controller.isClosed) controller.add(ParallelItemDone(st));
        }
      }));
      if (!controller.isClosed) {
        controller.add(ParallelAllDone(List.unmodifiable(states)));
        await controller.close();
      }
    });

    return (controller.stream, dropped);
  }
}
