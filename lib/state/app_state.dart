/// 应用状态中枢：服务配置、优化会话、历史记录、设置。
///
/// 无第三方状态管理依赖，使用 ChangeNotifier + 全局单例（在 main() 完成异步初始化）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../core/models.dart';
import '../services/key_store.dart';
import '../services/llm_client.dart';
import '../services/network_probe.dart';
import '../services/optimize_engine.dart';
import '../services/parallel_scheduler.dart';
import '../services/settings_service.dart';
import '../services/storage/app_storage.dart';
import 'workbench_tabs.dart';

/// 一次请求启动时的不可变快照。异步回调只允许写入这里捕获的 tab。
class _OptimizeSnapshot {
  const _OptimizeSnapshot({
    required this.runtime,
    required this.generation,
    required this.raw,
    required this.scene,
    required this.service,
    required this.mode,
    required this.outputStyle,
    required this.preset,
    required this.parallelEnabled,
    required this.parallelServiceId,
  });

  final WorkbenchTabRuntime runtime;
  final int generation;
  final String raw;
  final SceneTemplate scene;
  final ServiceConfig service;
  final OptimizeMode mode;
  final OutputStyle outputStyle;
  final CodingPreset? preset;
  final bool parallelEnabled;
  final String? parallelServiceId;

  OptimizationTabState get tab => runtime.state;
  String get tabId => tab.id;
  bool get isCurrent => runtime.isCurrent(generation);
}

class AppState extends ChangeNotifier {
  AppState({
    required this.storage,
    required this.keyStore,
    required this.settings,
    required this.engine,
    required this.llmClient,
  }) : scheduler = ParallelScheduler(engine: engine) {
    tabs = WorkbenchTabsController(
      stateFactory: (id, title) => OptimizationTabState(
        id: id,
        title: title,
        mode: settings.settings.defaultMode,
        sceneId: settings.settings.defaultScene,
        parallelEnabled: settings.settings.parallelEnabled,
      ),
    );
    tabs.addListener(notifyListeners);
    // 转发设置变更：设置页/模型配置页/工作台均只监听 AppState，
    // SettingsService 的变更必须驱动整体重绘，否则开关类控件表现为「点击无响应」
    settings.addListener(notifyListeners);
  }

  final AppStorage storage;
  final KeyStore keyStore;
  final SettingsService settings;
  final OptimizeEngine engine;
  final LlmClient llmClient;
  final ParallelScheduler scheduler;
  late final WorkbenchTabsController tabs;

  /// 兼容单工作台调用方；新代码应显式传入 tabId。
  OptimizationTabState get session => tabs.activeTab.state;

  WorkbenchTabRuntime? _runtimeFor([String? tabId]) =>
      tabId == null ? tabs.activeTab : tabs.tabById(tabId);

  OptimizationTabState? _tabFor([String? tabId]) => _runtimeFor(tabId)?.state;

  List<ServiceConfig> services = [];
  List<SceneTemplate> customTemplates = [];
  List<CodingPreset> presets = [];

  static const _uuid = Uuid();

  /// 全部场景（内置 + 自定义）
  List<SceneTemplate> get scenes => [...kBuiltinScenes, ...customTemplates];

  SceneTemplate sceneById(String id) =>
      scenes.firstWhere((s) => s.id == id, orElse: () => kDefaultScene);

  // ------------------------------------------------------------------ 初始化
  Future<void> init() async {
    services = await storage.loadServices();
    customTemplates = await storage.loadCustomTemplates();
    presets = await storage.loadPresets();
    // 默认服务一致性：设置里记录的 id 失效时回退到第一个 isDefault
    final defaultId = settings.settings.defaultServiceId;
    if (defaultId.isNotEmpty && services.every((s) => s.id != defaultId)) {
      await settings.update(settings.settings.copyWith(defaultServiceId: ''));
    }
    // 启动时按保留天数清理历史
    await storage.purgeExpiredRecords(settings.settings.retentionDays);
    notifyListeners();
  }

  /// 拖动调整服务顺序（仅排序持久化；不影响默认服务/并行门槛等业务状态）
  Future<void> reorderServices(List<String> orderedIds) async {
    await storage.reorderServices(orderedIds);
    services = await storage.loadServices();
    notifyListeners();
  }

  // -------------------------------------------------------------- 编程预置词
  /// 当前 tab 选中的编程预置词（未选择或已删除时为 null）
  CodingPreset? get selectedPreset => selectedPresetFor();

  CodingPreset? selectedPresetFor([String? tabId]) {
    final id = _tabFor(tabId)?.presetId;
    if (id == null || id.isEmpty) return null;
    return presets.where((p) => p.id == id).firstOrNull;
  }

  /// 重新拉取预置词列表（页面初始化 / 失败重试）
  Future<void> refreshPresets() async {
    presets = await storage.loadPresets();
    notifyListeners();
  }

  /// 保存（新增/编辑）；名称必填/唯一、内容 ≤1000 字校验失败抛 [FormatException]
  Future<void> savePreset(CodingPreset preset) async {
    await storage.savePreset(preset);
    await refreshPresets();
  }

  Future<void> deletePreset(String id) async {
    await storage.deletePreset(id);
    await refreshPresets();
    // 被删除的预置词若正被任一 tab 引用，清空选择。
    for (final runtime in tabs.tabs) {
      if (runtime.state.presetId == id) runtime.state.presetId = null;
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- 服务配置
  /// 全局计数器：已完成配置的有效 AI 服务数量（并行优化门槛判定依据）
  int get configuredServiceCount => services.length;

  /// 并行优化是否可开启：必须已配置 ≥2 个服务
  bool get canEnableParallel => configuredServiceCount >= 2;

  /// 当前 tab 有效的并行候选数（生效服务 ∪ 选中的对比服务）。
  int get parallelCandidateCount => parallelCandidateCountFor();

  int parallelCandidateCountFor([String? tabId]) {
    final tab = _tabFor(tabId);
    if (tab == null) return 0;
    final effective = effectiveServiceFor(tab.id);
    return {
      if (effective != null) effective.id,
      if (tab.parallelServiceId != null) tab.parallelServiceId!,
    }.where((id) => services.any((s) => s.id == id)).length;
  }

  ServiceConfig? get defaultService {
    final id = settings.settings.defaultServiceId;
    for (final s in services) {
      if (s.id == id) return s;
    }
    for (final s in services) {
      if (s.isDefault) return s;
    }
    return null;
  }

  /// tab 生效服务：tab 级选择 > 全局默认
  ServiceConfig? get effectiveService => effectiveServiceFor();

  ServiceConfig? effectiveServiceFor([String? tabId]) {
    final tab = _tabFor(tabId);
    if (tab == null) return null;
    final sid = tab.sessionServiceId;
    if (sid.isNotEmpty) {
      for (final s in services) {
        if (s.id == sid) return s;
      }
    }
    return defaultService;
  }

  Future<String?> readApiKey(ServiceConfig s) => keyStore.read(s.keyRef);

  /// 保存服务（同时写入密钥）
  Future<void> saveService(ServiceConfig service, {String? apiKey}) async {
    var toSave = service;
    if (toSave.keyRef.isEmpty) toSave = toSave.copyWith(keyRef: toSave.id);
    if (apiKey != null) {
      await keyStore.write(toSave.keyRef, apiKey);
    }
    if (services.isEmpty && !toSave.isDefault) {
      // 首个服务自动设为默认
      toSave = toSave.copyWith(isDefault: true);
    }
    await storage.saveService(toSave);
    if (toSave.isDefault) {
      for (final runtime in tabs.tabs) {
        if (runtime.state.parallelServiceId == toSave.id) {
          runtime.state.parallelServiceId = null;
        }
      }
      await settings
          .update(settings.settings.copyWith(defaultServiceId: toSave.id));
    }
    services = await storage.loadServices();
    notifyListeners();
  }

  Future<void> deleteService(ServiceConfig service) async {
    final wasDefault =
        service.isDefault || settings.settings.defaultServiceId == service.id;
    await storage.deleteService(service.id);
    if (service.keyRef.isNotEmpty) await keyStore.delete(service.keyRef);
    if (settings.settings.defaultServiceId == service.id) {
      await settings.update(settings.settings.copyWith(defaultServiceId: ''));
    }
    // 任一 tab 的服务选择指向被删服务时清空。
    for (final runtime in tabs.tabs) {
      if (runtime.state.parallelServiceId == service.id) {
        runtime.state.parallelServiceId = null;
      }
      if (runtime.state.sessionServiceId == service.id) {
        runtime.state.sessionServiceId = '';
      }
    }
    services = await storage.loadServices();
    // 删除的是默认服务且仍有其他服务：自动递补第一个为默认，避免无效默认态
    if (wasDefault && services.isNotEmpty) {
      await setDefaultService(services.first.id);
      return; // setDefaultService 内部已刷新 services 与通知
    }
    notifyListeners();
  }

  Future<void> setDefaultService(String id) async {
    for (final runtime in tabs.tabs) {
      if (runtime.state.parallelServiceId == id) {
        runtime.state.parallelServiceId = null; // 默认服务与对比服务不可相同
      }
    }
    for (final s in services) {
      await storage.saveService(s.copyWith(isDefault: s.id == id));
    }
    await settings.update(settings.settings.copyWith(defaultServiceId: id));
    services = await storage.loadServices();
    notifyListeners();
  }

  void setSessionService(String id, {String? tabId}) {
    final runtime = _runtimeFor(tabId);
    if (runtime == null) return;
    final tab = runtime.state;
    if (tab.parallelServiceId == id) {
      tab.parallelServiceId = null; // 生效服务与对比服务不可相同
    }
    tab.sessionServiceId = id;
    tabs.touch(tab.id);
  }

  /// 测试连接
  Future<ConnectionTestResult> testConnection(
      ServiceConfig service, String apiKey) {
    return llmClient.testConnection(ChatRequest(
      baseUrl: service.apiUrl,
      apiKey: apiKey,
      model: service.model.isEmpty
          ? (getProviderConfig(service.provider)?.defaultModel ?? '')
          : service.model,
      messages: const [ChatMessage('user', 'ping')],
      timeout: Duration(seconds: settings.settings.timeoutSecs),
    ));
  }

  /// 网络探测（测试可注入）：返回是否连通，并回传实际使用的代理描述。
  @visibleForTesting
  static Future<(bool ok, String proxyLabel)> Function(
      String? proxyUrl, Duration timeout)? debugNetworkProbe;

  /// 按当前代理模式执行连通性检测，返回展示文案。
  ///
  /// - 跟随系统 / 直连：直接探测网络，不校验服务商配置
  /// - 自定义：先校验代理地址，探测时走该代理
  /// - 成功/失败文案固定为「✅ 网络连接正常」/「❌ 网络连接失败」
  Future<String> runConnectivityCheck() async {
    final s = settings.settings;
    final timeout = Duration(seconds: s.timeoutSecs);
    String? proxyUrl;
    switch (s.proxyMode) {
      case ProxyMode.system:
        proxyUrl = null; // 跟随系统代理
        break;
      case ProxyMode.direct:
        proxyUrl = ''; // 强制直连
        break;
      case ProxyMode.custom:
        final url = s.proxyUrl.trim();
        if (url.isEmpty) {
          // 仅自定义模式且缺失必要配置时报此错
          return '尚未配置服务商';
        }
        proxyUrl = url;
        break;
    }

    final (netOk, _) = await _probeNetwork(proxyUrl, timeout);
    return netOk ? '✅ 网络连接正常' : '❌ 网络连接失败';
  }

  Future<(bool ok, String proxyLabel)> _probeNetwork(
      String? proxyUrl, Duration timeout) async {
    if (debugNetworkProbe != null) {
      return debugNetworkProbe!(proxyUrl, timeout);
    }
    final label = switch ((settings.settings.proxyMode, proxyUrl)) {
      (ProxyMode.system, _) => '跟随系统',
      (ProxyMode.direct, _) => '直连',
      (ProxyMode.custom, final u?) => u,
      _ => '跟随系统',
    };
    // 解析代理规则：null=跟随系统，DIRECT=直连，PROXY/SOCKS5=自定义
    String? proxyRule;
    if (proxyUrl != null && proxyUrl.isNotEmpty) {
      final uri = Uri.tryParse(proxyUrl);
      if (uri == null || uri.host.isEmpty) return (false, label);
      final scheme = uri.scheme.toLowerCase();
      final port = uri.hasPort
          ? uri.port
          : (scheme == 'socks5' ? 1080 : (scheme == 'https' ? 443 : 80));
      final hostPort = '${uri.host}:$port';
      proxyRule = scheme == 'socks5' ? 'SOCKS5 $hostPort' : 'PROXY $hostPort';
    } else if (proxyUrl != null && proxyUrl.isEmpty) {
      proxyRule = 'DIRECT';
    }
    // 任意可公网访问的轻量端点；仅验证经当前代理路径的连通性
    final ok = await probeThroughProxy(
      proxyRule: proxyRule,
      url: Uri.parse('http://www.baidu.com/'),
      timeout: timeout,
    );
    return (ok, label);
  }

  /// 在线拉取模型列表
  Future<List<String>> fetchModels(
      String provider, String apiUrl, String apiKey) {
    final cfg = getProviderConfig(provider);
    if (cfg == null) return Future.value(const []);
    if (!cfg.supportsModelListApi) return Future.value(cfg.models);
    return llmClient.listModels(apiUrl, apiKey,
        endpoint: cfg.modelListEndpoint,
        timeout: Duration(seconds: settings.settings.timeoutSecs));
  }

  // ------------------------------------------------------------------ 优化
  bool get canOptimize => canOptimizeFor();

  bool canOptimizeFor([String? tabId]) {
    final tab = _tabFor(tabId);
    if (tab == null) return false;
    final raw = tab.rawText.trim();
    return !tab.optimizing &&
        !tab.askAnswering && // 提问式答题中禁止重复触发优化
        raw.isNotEmpty &&
        raw.length <= OptimizeEngine.maxInputChars &&
        effectiveServiceFor(tab.id) != null;
  }

  /// 开始优化（主入口，自动分派模式与并行）。缺省只操作当前 tab。
  Future<OptimizeRecord?> startOptimize({String? tabId}) async {
    final runtime = _runtimeFor(tabId);
    if (runtime == null || !canOptimizeFor(runtime.state.id)) return null;
    final tab = runtime.state;
    final id = tab.id;
    final snapshot = _OptimizeSnapshot(
      runtime: runtime,
      generation: runtime.beginRun(),
      raw: tab.rawText.trim(),
      scene: sceneById(tab.sceneId),
      service: effectiveServiceFor(id)!,
      mode: tab.mode,
      outputStyle: tab.outputStyle,
      preset: selectedPresetFor(id),
      parallelEnabled: tab.parallelEnabled,
      parallelServiceId: tab.parallelServiceId,
    );
    final useParallel =
        snapshot.parallelEnabled && parallelCandidateCountFor(id) >= 2;

    tab.reset();
    tab.status = OptimizationRunStatus.loading;
    runtime.cancelToken = null;
    runtime.parallelRun = null;
    tabs.touch(id);

    final stopwatch = Stopwatch()..start();
    try {
      if (useParallel) return await _runParallel(snapshot, stopwatch);
      return await _runSingle(snapshot);
    } finally {
      _finishRun(snapshot);
    }
  }

  void _setRunError(_OptimizeSnapshot snapshot, Object error) {
    if (!snapshot.isCurrent) return;
    final tab = snapshot.tab;
    tab.status = OptimizationRunStatus.error;
    if (error is LlmException) {
      if (error.kind != LlmErrorKind.cancelled) {
        tab.errorMessage = error.userMessage;
      }
    } else {
      tab.errorMessage = '优化失败：$error';
    }
  }

  /// 只收尾仍属于当前 generation 的运行，旧回调不得触碰新 run。
  void _finishRun(_OptimizeSnapshot snapshot) {
    if (!snapshot.isCurrent) return;
    final tab = snapshot.tab;
    if (tab.optimizing) {
      tab.status = OptimizationRunStatus.error;
      tab.errorMessage ??= '优化已中断';
    }
    snapshot.runtime.cancelToken = null;
    snapshot.runtime.parallelRun = null;
    tabs.touch(snapshot.tabId);
  }

  /// 保存本次 run 的新 UUID 记录；若等待落库期间失效，只回滚这条记录。
  /// generation 后检与成功状态提交之间不再穿插 await。
  Future<bool> _saveRecordIfCurrent(_OptimizeSnapshot snapshot,
      OptimizeRecord record, void Function() commit) async {
    if (!snapshot.isCurrent) return false;
    await storage.saveRecord(record);
    if (!snapshot.isCurrent) {
      await storage.deleteRecord(record.id);
      return false;
    }
    commit();
    return true;
  }

  Future<OptimizeRecord?> _runSingle(_OptimizeSnapshot snapshot) async {
    final runtime = snapshot.runtime;
    final tab = snapshot.tab;
    final svc = snapshot.service;
    try {
      final key = await readApiKey(svc) ?? '';
      if (!snapshot.isCurrent) return null;
      final token = runtime.cancelToken = CancelToken();
      if (snapshot.mode == OptimizeMode.ask) {
        final qs = await engine.askQuestions(
          svc,
          key,
          snapshot.raw,
          scene: snapshot.scene,
          preset: snapshot.preset,
          cancelToken: token,
        );
        if (!snapshot.isCurrent) return null;
        tab.questions = qs;
        tab.answers = List.filled(qs.length, null);
        tab.askAnswering = true;
        tab.status = OptimizationRunStatus.empty;
        return null; // 等待用户回答后由 finalizeAsk 落库
      }
      final res = await engine.optimize(
        style: snapshot.outputStyle,
        svc,
        key,
        snapshot.raw,
        mode: snapshot.mode,
        scene: snapshot.scene,
        preset: snapshot.preset,
        cancelToken: token,
        onProgress: (t) {
          if (!snapshot.isCurrent) return;
          tab.streaming[svc.id] = t;
          tab.status = OptimizationRunStatus.streaming;
          tabs.touch(snapshot.tabId);
        },
      );
      if (!snapshot.isCurrent) return null;
      final record = OptimizeRecord(
        id: _uuid.v4(),
        scene: snapshot.scene.id,
        mode: snapshot.mode,
        rawText: snapshot.raw,
        versions: [
          OptimizeVersion(v: 1, result: res.result, createdAt: _nowSec()),
        ],
        providers: [svc.id],
        scoreBefore: res.result.scoreBefore,
        scoreAfter: res.result.scoreAfter,
        elapsedMs: res.elapsedMs,
        tokens: res.totalTokens ?? 0,
        createdAt: _nowSec(),
      );
      final saved = await _saveRecordIfCurrent(snapshot, record, () {
        tab.currentRecord = record;
        tab.singleResult = res;
        tab.status = OptimizationRunStatus.success;
        tab.errorMessage = null;
      });
      if (!saved) return null;
      return record;
    } on LlmException catch (e) {
      _setRunError(snapshot, e);
      return null;
    } catch (e) {
      _setRunError(snapshot, e);
      return null;
    }
  }

  Future<OptimizeRecord?> _runParallel(
      _OptimizeSnapshot snapshot, Stopwatch sw) async {
    final runtime = snapshot.runtime;
    final tab = snapshot.tab;
    final primary = snapshot.service;
    // 并行集合在首个 await 前从快照确定，之后绝不回读激活 tab。
    final ids = <String>{
      primary.id,
      if (snapshot.parallelServiceId != null) snapshot.parallelServiceId!,
    }.toList();
    final svcs = [for (final id in ids) ...services.where((s) => s.id == id)];
    try {
      final keys = <String>[];
      for (final svc in svcs) {
        keys.add(await readApiKey(svc) ?? '');
        if (!snapshot.isCurrent) return null;
      }

      final handle = scheduler.run(
        svcs,
        keys,
        snapshot.raw,
        mode: snapshot.mode,
        style: snapshot.outputStyle,
        scene: snapshot.scene,
        preset: snapshot.preset,
        onItemProgress: (id, text) {
          if (!snapshot.isCurrent) return;
          tab.streaming[id] = text;
          tab.status = OptimizationRunStatus.streaming;
          tabs.touch(snapshot.tabId);
        },
      );
      runtime.parallelRun = handle;
      tab.droppedProviderNames = [
        for (final s in handle.droppedServices)
          getProviderConfig(s.provider)?.name ?? s.provider
      ];
      // 必须保存调度器的真实 state，UI 与完成事件共享同一份进度和结果。
      tab.parallelStates = {
        for (final state in handle.states) state.service.id: state,
      };
      tabs.touch(snapshot.tabId);

      await for (final ev in handle.events) {
        if (!snapshot.isCurrent) return null;
        if (ev is ParallelItemDone) {
          tab.parallelStates[ev.state.service.id] = ev.state;
          tabs.touch(snapshot.tabId);
        } else if (ev is ParallelAllDone) {
          // 以首个成功结果落库（用户可在复查页切换来源）。
          ParallelRunState? best;
          for (final state in ev.states) {
            if (state.success) {
              best = state;
              break;
            }
          }
          if (best != null) {
            final result = best.runResult!;
            final record = OptimizeRecord(
              id: _uuid.v4(),
              scene: snapshot.scene.id,
              mode: snapshot.mode,
              rawText: snapshot.raw,
              versions: [
                OptimizeVersion(
                    v: 1, result: result.result, createdAt: _nowSec()),
              ],
              providers: svcs.map((s) => s.id).toList(),
              scoreBefore: result.result.scoreBefore,
              scoreAfter: result.result.scoreAfter,
              elapsedMs: sw.elapsedMilliseconds,
              tokens: ev.states.fold<int>(
                  0, (sum, state) => sum + (state.runResult?.totalTokens ?? 0)),
              createdAt: _nowSec(),
            );
            final saved = await _saveRecordIfCurrent(snapshot, record, () {
              tab.currentRecord = record;
              tab.status = OptimizationRunStatus.success;
              tab.errorMessage = null;
            });
            if (!saved) return null;
            return record;
          }
          final firstErr = ev.states.isEmpty ? null : ev.states.first.error;
          tab.status = OptimizationRunStatus.error;
          tab.errorMessage =
              firstErr is LlmException ? firstErr.userMessage : '全部模型调用失败';
          return null;
        }
      }
      return null;
    } on LlmException catch (e) {
      _setRunError(snapshot, e);
      return null;
    } catch (e) {
      _setRunError(snapshot, e);
      return null;
    }
  }

  /// 提问式优化：提交答案生成终稿。loading 在首个 await 前设置以防重入。
  Future<OptimizeRecord?> finalizeAsk({String? tabId}) async {
    final runtime = _runtimeFor(tabId);
    if (runtime == null) return null;
    final tab = runtime.state;
    final id = tab.id;
    final svc = effectiveServiceFor(id);
    if (svc == null || !tab.askAnswering || tab.optimizing) return null;
    final questions = List<ClarifyQuestion>.of(tab.questions);
    final answers = List<String?>.of(tab.answers);
    final snapshot = _OptimizeSnapshot(
      runtime: runtime,
      generation: runtime.beginRun(),
      raw: tab.rawText.trim(),
      scene: sceneById(tab.sceneId),
      service: svc,
      mode: OptimizeMode.ask,
      outputStyle: tab.outputStyle,
      preset: selectedPresetFor(id),
      parallelEnabled: tab.parallelEnabled,
      parallelServiceId: tab.parallelServiceId,
    );

    tab.streaming.clear();
    tab.parallelStates.clear();
    tab.singleResult = null;
    tab.droppedProviderNames.clear();
    tab.errorMessage = null;
    tab.status = OptimizationRunStatus.loading;
    runtime.cancelToken = null;
    runtime.parallelRun = null;
    tabs.touch(id);

    try {
      final key = await readApiKey(svc) ?? '';
      if (!snapshot.isCurrent) return null;
      final token = runtime.cancelToken = CancelToken();
      final res = await engine.finalizeAsk(
        style: snapshot.outputStyle,
        svc,
        key,
        snapshot.raw,
        questions,
        answers,
        scene: snapshot.scene,
        preset: snapshot.preset,
        cancelToken: token,
        onProgress: (text) {
          if (!snapshot.isCurrent) return;
          tab.streaming[svc.id] = text;
          tab.status = OptimizationRunStatus.streaming;
          tabs.touch(id);
        },
      );
      if (!snapshot.isCurrent) return null;
      final record = OptimizeRecord(
        id: _uuid.v4(),
        scene: snapshot.scene.id,
        mode: OptimizeMode.ask,
        rawText: snapshot.raw,
        versions: [
          OptimizeVersion(v: 1, result: res.result, createdAt: _nowSec()),
        ],
        providers: [svc.id],
        scoreBefore: res.result.scoreBefore,
        scoreAfter: res.result.scoreAfter,
        elapsedMs: res.elapsedMs,
        tokens: res.totalTokens ?? 0,
        createdAt: _nowSec(),
      );
      final saved = await _saveRecordIfCurrent(snapshot, record, () {
        tab.currentRecord = record;
        tab.singleResult = res;
        tab.askAnswering = false;
        tab.status = OptimizationRunStatus.success;
        tab.errorMessage = null;
      });
      if (!saved) return null;
      return record;
    } on LlmException catch (e) {
      _setRunError(snapshot, e);
      return null;
    } catch (e) {
      _setRunError(snapshot, e);
      return null;
    } finally {
      _finishRun(snapshot);
    }
  }

  void cancelOptimize({String? tabId}) {
    final runtime = _runtimeFor(tabId);
    if (runtime == null) return;
    final tab = runtime.state;
    if (!tab.optimizing && !tab.askAnswering) return;
    runtime.invalidateRun();
    runtime.cancelToken?.cancel('user');
    runtime.parallelRun?.cancel();
    runtime.cancelToken = null;
    runtime.parallelRun = null;
    tab.askAnswering = false;

    final hasPartial = tab.streaming.values.any((text) => text.isNotEmpty) ||
        tab.parallelStates.values.any((state) => state.streamedText.isNotEmpty);
    tab.status = OptimizationRunStatus.error;
    tab.errorMessage = hasPartial ? '请求已取消，已保留接收内容' : '请求已取消';
    tabs.touch(tab.id);
  }

  /// 清空指定 tab 前必须先使旧请求失效并取消，避免迟到回调重新填回数据。
  void clearWorkbenchTab({String? tabId}) {
    final runtime = _runtimeFor(tabId);
    if (runtime == null) return;
    cancelOptimize(tabId: runtime.state.id);
    runtime.state.rawText = '';
    runtime.state.currentRecord = null;
    runtime.state.reset();
    runtime.syncControllerFromState();
    tabs.touch(runtime.state.id);
  }

  // -------------------------------------------------------------- 复查编辑
  /// 追加一个新版本（编辑后保存）
  Future<OptimizeRecord?> saveEditedResult(OptimizeResult edited,
      {String? tabId}) async {
    final runtime = _runtimeFor(tabId);
    if (runtime == null) return null;
    final tab = runtime.state;
    final record = tab.currentRecord;
    if (record == null) return null;
    final nextV = record.latest.v + 1;
    final updated = record.copyWith(versions: [
      ...record.versions,
      OptimizeVersion(
          v: nextV, result: edited, edited: true, createdAt: _nowSec()),
    ]);
    await storage.saveRecord(updated);
    tab.currentRecord = updated;
    tabs.touch(tab.id);
    return updated;
  }

  /// 回滚到指定版本：将该版本内容复制为新版本（版本链保持单向追加）
  Future<OptimizeRecord?> rollbackToVersion(int v, {String? tabId}) async {
    final runtime = _runtimeFor(tabId);
    if (runtime == null) return null;
    final tab = runtime.state;
    final record = tab.currentRecord;
    if (record == null) return null;
    final target = record.versions.where((e) => e.v == v).firstOrNull;
    if (target == null) return null;
    return saveEditedResult(target.result, tabId: tab.id);
  }

  /// AI 重写某段，返回更新后的结果（不落库，由调用方决定）
  Future<String> rewriteSection(
      String sectionKey, String sectionTitle, String content,
      {String instruction = '', String? tabId}) async {
    final runtime = _runtimeFor(tabId);
    final tab = runtime?.state;
    final svc = effectiveServiceFor(tab?.id);
    final record = tab?.currentRecord;
    if (svc == null || record == null) {
      throw const LlmException(LlmErrorKind.badResponse, '无可用服务或记录');
    }
    final key = await readApiKey(svc) ?? '';
    return engine.rewriteSection(
        svc, key, record.latest.result, sectionKey, sectionTitle, content,
        instruction: instruction);
  }

  // ------------------------------------------------------------------ 历史
  Future<List<OptimizeRecord>> loadHistory(
          {String keyword = '', String scene = '', String provider = ''}) =>
      storage.searchRecords(keyword: keyword, scene: scene, provider: provider);

  Future<void> openRecord(OptimizeRecord record) async {
    final runtime = tabs.addTab();
    final tab = runtime.state;
    tab.currentRecord = record;
    tab.rawText = record.rawText;
    tab.sceneId = record.scene;
    tab.mode = record.mode;
    tab.status = OptimizationRunStatus.success;
    runtime.syncControllerFromState();
    tabs.touch(tab.id);
  }

  Future<void> deleteRecord(String id) async {
    await storage.deleteRecord(id);
    for (final runtime in tabs.tabs) {
      if (runtime.state.currentRecord?.id == id) {
        runtime.state.currentRecord = null;
        if (runtime.state.status == OptimizationRunStatus.success) {
          runtime.state.status = OptimizationRunStatus.empty;
        }
      }
    }
    notifyListeners();
  }

  Future<void> clearHistory() async {
    final all = await storage.loadRecords(limit: 1000000);
    for (final r in all) {
      await storage.deleteRecord(r.id);
    }
    for (final runtime in tabs.tabs) {
      runtime.state.currentRecord = null;
      if (runtime.state.status == OptimizationRunStatus.success) {
        runtime.state.status = OptimizationRunStatus.empty;
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ 模板
  Future<void> saveTemplate(SceneTemplate t) async {
    await storage.saveTemplate(t);
    customTemplates = await storage.loadCustomTemplates();
    notifyListeners();
  }

  Future<void> deleteTemplate(String id) async {
    await storage.deleteTemplate(id);
    customTemplates = await storage.loadCustomTemplates();
    for (final runtime in tabs.tabs) {
      if (runtime.state.sceneId == id) {
        runtime.state.sceneId = kDefaultScene.id;
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ 配置导入导出
  /// 导出配置（不含密钥）
  /// 系统设置配置导出格式版本（导入时做兼容判断）
  static const int settingsConfigVersion = 1;
  static const String settingsConfigAppTag = 'prompt_optimizer';

  /// 导出：将当前全部系统设置项序列化为 JSON（与界面字段一一对应，
  /// 含版本号与导出时间，便于导入校验）
  String buildSettingsExportJson({DateTime? now}) {
    final t = now ?? DateTime.now();
    return const JsonEncoder.withIndent('  ').convert({
      'app': settingsConfigAppTag,
      'config_version': settingsConfigVersion,
      'exported_at': t.toIso8601String(),
      'settings': settings.settings.toJson(),
      // 编程预置词随配置一并导出（不含任何密钥），导入时逐条还原
      'presets': [for (final p in presets) p.toJson()],
    });
  }

  /// 导入：解析 + 校验 + 字段级覆盖合并（纯函数，不写任何存储）。
  /// - 顶层必须为 JSON 对象；app 标记与 config_version 必须可识别；
  /// - settings 必须为对象；出现的字段类型/枚举值必须正确；
  /// - 任一校验失败抛 [FormatException]，调用方不得写入任何数据；
  /// - 未出现的字段保持当前值。
  AppSettings parseImportedSettings(String json) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw const FormatException('文件内容不是合法的 JSON');
    }
    if (decoded is! Map) {
      throw const FormatException('结构非法：顶层必须是 JSON 对象');
    }
    if (decoded['app'] != settingsConfigAppTag) {
      throw const FormatException('不是提示词优化工具的配置文件');
    }
    final ver = decoded['config_version'];
    if (ver is! int || ver < 1) {
      throw const FormatException('版本号缺失或不可识别');
    }
    if (ver > settingsConfigVersion) {
      throw FormatException('配置文件版本（v$ver）高于当前支持版本（v$settingsConfigVersion）');
    }
    final raw = decoded['settings'];
    if (raw is! Map) {
      throw const FormatException('缺少 settings 配置对象');
    }
    return _mergeSettings(Map<String, dynamic>.from(raw));
  }

  /// 解析导入配置中的编程预置词（可选字段：旧版本导出无此段 → 空列表）。
  /// 严格校验：结构非法或单条非法（空名称/超 1000 字等）整体抛 [FormatException]，
  /// 调用方在解析全部通过前不得写入任何数据。
  List<CodingPreset> parseImportedPresets(String json) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      throw const FormatException('文件内容不是合法的 JSON');
    }
    if (decoded is! Map) {
      throw const FormatException('结构非法：顶层必须是 JSON 对象');
    }
    if (decoded['app'] != settingsConfigAppTag) {
      throw const FormatException('不是提示词优化工具的配置文件');
    }
    final raw = decoded['presets'];
    if (raw == null) return const []; // 兼容旧版导出文件（无预置词段）
    if (raw is! List) {
      throw const FormatException('presets 段必须是数组');
    }
    final out = <CodingPreset>[];
    for (final e in raw) {
      if (e is! Map) {
        throw const FormatException('预置词条目结构非法：必须是对象');
      }
      final p = CodingPreset.fromJson(Map<String, dynamic>.from(e));
      // 名称唯一性由写入阶段去重处理，此处仅校验必填与长度上限
      validatePreset(p, const [], selfId: p.id);
      out.add(p);
    }
    return out;
  }

  /// 还原导入的编程预置词：同 id 覆盖更新；不同 id 名称冲突时自动去重命名
  ///（追加「 (2)」递增），保证导入不中断。返回写入条数。
  Future<int> importPresets(List<CodingPreset> incoming) async {
    var count = 0;
    for (final p in incoming) {
      var name = p.name;
      var suffix = 2;
      while (presets.any((e) => e.id != p.id && e.name == name)) {
        name = '${p.name} (${suffix++})';
      }
      await storage.savePreset(CodingPreset(
        id: p.id,
        name: name,
        content: p.content,
        createdAt: p.createdAt,
      ));
      count++;
    }
    await refreshPresets();
    return count;
  }

  /// 字段级覆盖：仅校验并合并 settings 对象中出现的字段
  AppSettings _mergeSettings(Map<String, dynamic> j) {
    final cur = settings.settings;

    T? pickEnum<T extends Enum>(String key, List<T> values) {
      if (!j.containsKey(key)) return null;
      final v = j[key];
      if (v is! String || !values.any((e) => e.name == v)) {
        throw FormatException('字段 "$key" 的值无效，导入已取消');
      }
      return values.firstWhere((e) => e.name == v);
    }

    String? pickStr(String key) {
      if (!j.containsKey(key)) return null;
      final v = j[key];
      if (v is! String) throw FormatException('字段 "$key" 类型不正确（应为字符串），导入已取消');
      return v;
    }

    bool? pickBool(String key) {
      if (!j.containsKey(key)) return null;
      final v = j[key];
      if (v is! bool) throw FormatException('字段 "$key" 类型不正确（应为布尔值），导入已取消');
      return v;
    }

    int? pickInt(String key) {
      if (!j.containsKey(key)) return null;
      final v = j[key];
      if (v is! int) throw FormatException('字段 "$key" 类型不正确（应为整数），导入已取消');
      return v;
    }

    final themeMode = pickEnum('theme_mode', AppThemeMode.values);
    final language = pickStr('language');
    final autoStart = pickBool('auto_start');
    final hotkey = pickStr('hotkey');
    final optimizeHotkey = pickStr('optimize_hotkey');
    final defaultMode = pickEnum('default_mode', OptimizeMode.values);
    final defaultScene = pickStr('default_scene');
    final resultLanguage = pickStr('result_language');
    final autoCopy = pickBool('auto_copy');
    final retentionDays = pickInt('retention_days');
    final proxyMode = pickEnum('proxy_mode', ProxyMode.values);
    final proxyUrl = pickStr('proxy_url');
    final timeoutSecs = pickInt('timeout_secs');
    final parallelEnabled = pickBool('parallel_enabled');
    final defaultServiceId = pickStr('default_service_id');

    return cur.copyWith(
      themeMode: themeMode,
      language: language,
      autoStart: autoStart,
      hotkey: hotkey,
      optimizeHotkey: optimizeHotkey,
      defaultMode: defaultMode,
      defaultScene: defaultScene,
      resultLanguage: resultLanguage,
      autoCopy: autoCopy,
      retentionDays: retentionDays,
      proxyMode: proxyMode,
      proxyUrl: proxyUrl,
      timeoutSecs: timeoutSecs,
      parallelEnabled: parallelEnabled,
      defaultServiceId: defaultServiceId,
    );
  }

  String exportConfigJson() {
    return const JsonEncoder().convert({
      'version': 1,
      'services': services.map((s) => s.toExportJson()).toList(),
      'settings': settings.settings.toJson(),
    });
  }

  /// 导入配置（服务密钥需重新录入）
  Future<int> importConfigJson(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['services'] is! List) {
      throw const FormatException('配置文件格式不正确');
    }
    var count = 0;
    for (final e in (decoded['services'] as List)) {
      final j = Map<String, dynamic>.from(e as Map);
      final provider = j['provider'] as String? ?? '';
      if (getProviderConfig(provider) == null) continue;
      final svc = ServiceConfig.fromJson({
        ...j,
        'id': _uuid.v4(),
        'key_ref': '',
        'is_default': false,
        'created_at': _nowSec(),
      });
      await storage.saveService(svc);
      count++;
    }
    services = await storage.loadServices();
    notifyListeners();
    return count;
  }

  static int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  void dispose() {
    settings.removeListener(notifyListeners);
    tabs.removeListener(notifyListeners);
    tabs.dispose();
    super.dispose();
  }
}

/// 全局单例（main() 初始化后赋值）
late AppState appState;
