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
import '../services/optimize_engine.dart';
import '../services/parallel_scheduler.dart';
import '../services/settings_service.dart';
import '../services/storage/app_storage.dart';

/// 工作台会话状态
class WorkbenchSession {
  String rawText = '';
  OptimizeMode mode = OptimizeMode.deep;
  String sceneId = kDefaultScene.id;

  /// 会话级临时选用的服务 id（空 = 跟随全局默认）
  String sessionServiceId = '';

  bool optimizing = false;
  bool askAnswering = false;

  /// 输出详略（简单/完整模式），跟随会话、重启后恢复默认
  OutputStyle outputStyle = OutputStyle.simple;

  /// 并行对比选中的对比服务（单选，跟随会话；须不同于当前生效服务）
  String? parallelServiceId;

  /// 流式中间文本（按服务 id 分组）
  final Map<String, String> streaming = {};

  /// 并行结果（服务 id → 状态）
  final Map<String, ParallelRunState> parallelStates = {};

  /// 单模型结果
  EngineRunResult? singleResult;

  /// 并行模式下被丢弃的服务商名（超上限）
  List<String> droppedProviderNames = [];

  /// 提问式：当前问题与答案
  List<ClarifyQuestion> questions = [];
  List<String?> answers = [];

  /// 当前正在编辑/展示的记录（优化完成或从历史打开）
  OptimizeRecord? currentRecord;

  String? errorMessage;

  CancelToken? cancelToken;

  void reset() {
    optimizing = false;
    askAnswering = false;
    streaming.clear();
    parallelStates.clear();
    singleResult = null;
    droppedProviderNames = [];
    questions = [];
    answers = [];
    errorMessage = null;
    cancelToken = null;
  }
}

class AppState extends ChangeNotifier {
  AppState({
    required this.storage,
    required this.keyStore,
    required this.settings,
    required this.engine,
    required this.llmClient,
  }) : scheduler = ParallelScheduler(engine: engine) {
    // 转发设置变更：设置页/模型配置页/工作台均只监听 AppState，
    // SettingsService 的变更必须驱动整体重绘，否则开关类控件表现为「点击无响应」
    settings.addListener(notifyListeners);
    // 会话初始值跟随设置（默认优化模式 / 默认场景模板）
    session.mode = settings.settings.defaultMode;
    session.sceneId = settings.settings.defaultScene;
  }

  final AppStorage storage;
  final KeyStore keyStore;
  final SettingsService settings;
  final OptimizeEngine engine;
  final LlmClient llmClient;
  final ParallelScheduler scheduler;

  final WorkbenchSession session = WorkbenchSession();

  List<ServiceConfig> services = [];
  List<SceneTemplate> customTemplates = [];

  static const _uuid = Uuid();

  /// 全部场景（内置 + 自定义）
  List<SceneTemplate> get scenes => [...kBuiltinScenes, ...customTemplates];

  SceneTemplate sceneById(String id) =>
      scenes.firstWhere((s) => s.id == id, orElse: () => kDefaultScene);

  // ------------------------------------------------------------------ 初始化
  Future<void> init() async {
    services = await storage.loadServices();
    customTemplates = await storage.loadCustomTemplates();
    // 默认服务一致性：设置里记录的 id 失效时回退到第一个 isDefault
    final defaultId = settings.settings.defaultServiceId;
    if (defaultId.isNotEmpty && services.every((s) => s.id != defaultId)) {
      await settings.update(settings.settings.copyWith(defaultServiceId: ''));
    }
    // 启动时按保留天数清理历史
    await storage.purgeExpiredRecords(settings.settings.retentionDays);
    notifyListeners();
  }

  // -------------------------------------------------------------- 服务配置
  /// 全局计数器：已完成配置的有效 AI 服务数量（并行优化门槛判定依据）
  int get configuredServiceCount => services.length;

  /// 并行优化是否可开启：必须已配置 ≥2 个服务
  bool get canEnableParallel => configuredServiceCount >= 2;

  /// 当前有效的并行候选数（当前生效服务 ∪ 会话选中的对比服务，
  /// 剔除已删除服务与重复选择）。≥2 时并行优化才真正生效，否则回落单模型。
  int get parallelCandidateCount => {
        if (effectiveService != null) effectiveService!.id,
        if (session.parallelServiceId != null) session.parallelServiceId!,
      }.where((id) => services.any((s) => s.id == id)).length;

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

  /// 会话生效服务：会话级选择 > 全局默认
  ServiceConfig? get effectiveService {
    final sid = session.sessionServiceId;
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
      await settings.update(settings.settings.copyWith(defaultServiceId: toSave.id));
    }
    services = await storage.loadServices();
    notifyListeners();
  }

  Future<void> deleteService(ServiceConfig service) async {
    final wasDefault = service.isDefault ||
        settings.settings.defaultServiceId == service.id;
    await storage.deleteService(service.id);
    if (service.keyRef.isNotEmpty) await keyStore.delete(service.keyRef);
    if (settings.settings.defaultServiceId == service.id) {
      await settings.update(settings.settings.copyWith(defaultServiceId: ''));
    }
    // 会话并行选择指向被删服务时清空
    if (session.parallelServiceId == service.id) session.parallelServiceId = null;
    if (session.sessionServiceId == service.id) session.sessionServiceId = '';
    services = await storage.loadServices();
    // 删除的是默认服务且仍有其他服务：自动递补第一个为默认，避免无效默认态
    if (wasDefault && services.isNotEmpty) {
      await setDefaultService(services.first.id);
      return; // setDefaultService 内部已刷新 services 与通知
    }
    notifyListeners();
  }

  Future<void> setDefaultService(String id) async {
    if (session.parallelServiceId == id) {
      session.parallelServiceId = null; // 默认服务变更后与对比选择冲突时清空
    }
    for (final s in services) {
      await storage.saveService(s.copyWith(isDefault: s.id == id));
    }
    await settings.update(settings.settings.copyWith(defaultServiceId: id));
    services = await storage.loadServices();
    notifyListeners();
  }

  void setSessionService(String id) {
    if (session.parallelServiceId == id) {
      session.parallelServiceId = null; // 生效服务与对比服务不可相同
    }
    session.sessionServiceId = id;
    notifyListeners();
  }

  /// 测试连接
  Future<ConnectionTestResult> testConnection(ServiceConfig service, String apiKey) {
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

  /// 在线拉取模型列表
  Future<List<String>> fetchModels(String provider, String apiUrl, String apiKey) {
    final cfg = getProviderConfig(provider);
    if (cfg == null) return Future.value(const []);
    if (!cfg.supportsModelListApi) return Future.value(cfg.models);
    return llmClient.listModels(apiUrl, apiKey,
        endpoint: cfg.modelListEndpoint,
        timeout: Duration(seconds: settings.settings.timeoutSecs));
  }

  // ------------------------------------------------------------------ 优化
  bool get canOptimize =>
      !session.optimizing &&
      !session.askAnswering && // 提问式答题中禁止重复触发优化
      session.rawText.trim().isNotEmpty &&
      session.rawText.trim().length <= OptimizeEngine.maxInputChars &&
      effectiveService != null;

  /// 开始优化（主入口，自动分派模式与并行）
  Future<OptimizeRecord?> startOptimize() async {
    if (!canOptimize) return null;
    final raw = session.rawText.trim();
    final scene = sceneById(session.sceneId);
    final svc = effectiveService!;

    session.reset();
    session.optimizing = true;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    try {
      // 并行守卫：设置开启 + 当前并行候选 ≥2 才走并行，否则单模型
      if (settings.settings.parallelEnabled && parallelCandidateCount >= 2) {
        return await _runParallel(raw, scene, svc, stopwatch);
      }
      return await _runSingle(raw, scene, svc, stopwatch);
    } finally {
      session.optimizing = false;
      notifyListeners();
    }
  }

  Future<OptimizeRecord?> _runSingle(
      String raw, SceneTemplate scene, ServiceConfig svc, Stopwatch sw) async {
    final key = await readApiKey(svc) ?? '';
    final token = session.cancelToken = CancelToken();
    try {
      if (session.mode == OptimizeMode.ask) {
        final qs = await engine.askQuestions(svc, key, raw,
            scene: scene, cancelToken: token);
        session.questions = qs;
        session.answers = List.filled(qs.length, null);
        session.askAnswering = true;
        return null; // 等待用户回答后由 finalizeAsk 落库
      }
      final res = await engine.optimize(
        style: session.outputStyle,
        svc,
        key,
        raw,
        mode: session.mode,
        scene: scene,
        cancelToken: token,
        onProgress: (t) {
          session.streaming[svc.id] = t;
          notifyListeners();
        },
      );
      final record = OptimizeRecord(
        id: _uuid.v4(),
        scene: scene.id,
        mode: session.mode,
        rawText: raw,
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
      await storage.saveRecord(record);
      session.currentRecord = record;
      session.singleResult = res;
      return record;
    } on LlmException catch (e) {
      if (e.kind != LlmErrorKind.cancelled) session.errorMessage = e.userMessage;
      return null;
    } catch (e) {
      session.errorMessage = '优化失败：$e';
      return null;
    }
  }

  Future<OptimizeRecord?> _runParallel(
      String raw, SceneTemplate scene, ServiceConfig primary, Stopwatch sw) async {
    // 并行集合：当前生效服务 + 工作台选中的对比服务（单选）
    final ids = <String>{
      primary.id,
      if (session.parallelServiceId != null) session.parallelServiceId!,
    }.toList();
    final svcs = [for (final id in ids) ...services.where((s) => s.id == id)];
    final keys = [for (final s in svcs) await readApiKey(s) ?? ''];

    final (events, dropped) = scheduler.run(svcs, keys, raw,
        mode: session.mode, style: session.outputStyle, scene: scene,
        onItemProgress: (id, t) {
      session.streaming[id] = t;
      notifyListeners();
    });
    session.droppedProviderNames = [
      for (final s in dropped) getProviderConfig(s.provider)?.name ?? s.provider
    ];
    for (final s in svcs) {
      session.parallelStates[s.id] = ParallelRunState(service: s, apiKey: '');
    }
    notifyListeners();

    await for (final ev in events) {
      if (ev is ParallelItemDone) {
        session.parallelStates[ev.state.service.id] = ev.state;
        notifyListeners();
      } else if (ev is ParallelAllDone) {
        // 以首个成功结果落库（用户可在复查页切换来源）
        ParallelRunState? best;
        for (final st in ev.states) {
          if (st.success) {
            best = st;
            break;
          }
        }
        if (best != null) {
          final r = best.runResult!;
          final record = OptimizeRecord(
            id: _uuid.v4(),
            scene: scene.id,
            mode: session.mode,
            rawText: raw,
            versions: [OptimizeVersion(v: 1, result: r.result, createdAt: _nowSec())],
            providers: svcs.map((s) => s.id).toList(),
            scoreBefore: r.result.scoreBefore,
            scoreAfter: r.result.scoreAfter,
            elapsedMs: sw.elapsedMilliseconds,
            tokens: ev.states.fold(0, (a, b) => a + (b.runResult?.totalTokens ?? 0)),
            createdAt: _nowSec(),
          );
          await storage.saveRecord(record);
          session.currentRecord = record;
          return record;
        } else {
          final firstErr = ev.states.first.error;
          session.errorMessage =
              firstErr is LlmException ? firstErr.userMessage : '全部模型调用失败';
          return null;
        }
      }
    }
    return null;
  }

  /// 提问式优化：提交答案生成终稿
  Future<OptimizeRecord?> finalizeAsk() async {
    final svc = effectiveService;
    if (svc == null || !session.askAnswering) return null;
    final raw = session.rawText.trim();
    final scene = sceneById(session.sceneId);
    final key = await readApiKey(svc) ?? '';
    session.optimizing = true;
    notifyListeners();
    try {
      final res = await engine.finalizeAsk(
        style: session.outputStyle,
        svc,
        key,
        raw,
        session.questions,
        session.answers,
        scene: scene,
        cancelToken: session.cancelToken = CancelToken(),
        onProgress: (t) {
          session.streaming[svc.id] = t;
          notifyListeners();
        },
      );
      final record = OptimizeRecord(
        id: _uuid.v4(),
        scene: scene.id,
        mode: OptimizeMode.ask,
        rawText: raw,
        versions: [OptimizeVersion(v: 1, result: res.result, createdAt: _nowSec())],
        providers: [svc.id],
        scoreBefore: res.result.scoreBefore,
        scoreAfter: res.result.scoreAfter,
        elapsedMs: res.elapsedMs,
        tokens: res.totalTokens ?? 0,
        createdAt: _nowSec(),
      );
      await storage.saveRecord(record);
      session.currentRecord = record;
      session.singleResult = res;
      session.askAnswering = false;
      return record;
    } on LlmException catch (e) {
      if (e.kind != LlmErrorKind.cancelled) session.errorMessage = e.userMessage;
      return null;
    } catch (e) {
      session.errorMessage = '优化失败：$e';
      return null;
    } finally {
      session.optimizing = false;
      notifyListeners();
    }
  }

  void cancelOptimize() {
    session.cancelToken?.cancel('user');
    session.optimizing = false;
    session.askAnswering = false;
    notifyListeners();
  }

  // -------------------------------------------------------------- 复查编辑
  /// 追加一个新版本（编辑后保存）
  Future<OptimizeRecord?> saveEditedResult(OptimizeResult edited) async {
    final record = session.currentRecord;
    if (record == null) return null;
    final nextV = record.latest.v + 1;
    final updated = record.copyWith(versions: [
      ...record.versions,
      OptimizeVersion(v: nextV, result: edited, edited: true, createdAt: _nowSec()),
    ]);
    await storage.saveRecord(updated);
    session.currentRecord = updated;
    notifyListeners();
    return updated;
  }

  /// 回滚到指定版本：将该版本内容复制为新版本（版本链保持单向追加）
  Future<OptimizeRecord?> rollbackToVersion(int v) async {
    final record = session.currentRecord;
    if (record == null) return null;
    final target = record.versions.where((e) => e.v == v).firstOrNull;
    if (target == null) return null;
    return saveEditedResult(target.result);
  }

  /// AI 重写某段，返回更新后的结果（不落库，由调用方决定）
  Future<String> rewriteSection(String sectionKey, String sectionTitle, String content,
      {String instruction = ''}) async {
    final svc = effectiveService;
    final record = session.currentRecord;
    if (svc == null || record == null) {
      throw const LlmException(LlmErrorKind.badResponse, '无可用服务或记录');
    }
    final key = await readApiKey(svc) ?? '';
    return engine.rewriteSection(svc, key, record.latest.result, sectionKey, sectionTitle,
        content, instruction: instruction);
  }

  // ------------------------------------------------------------------ 历史
  Future<List<OptimizeRecord>> loadHistory({String keyword = '', String scene = '', String provider = ''}) =>
      storage.searchRecords(keyword: keyword, scene: scene, provider: provider);

  Future<void> openRecord(OptimizeRecord record) async {
    session.currentRecord = record;
    session.rawText = record.rawText;
    session.sceneId = record.scene;
    session.mode = record.mode;
    notifyListeners();
  }

  Future<void> deleteRecord(String id) async {
    await storage.deleteRecord(id);
    if (session.currentRecord?.id == id) session.currentRecord = null;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    final all = await storage.loadRecords(limit: 1000000);
    for (final r in all) {
      await storage.deleteRecord(r.id);
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
    if (session.sceneId == id) session.sceneId = kDefaultScene.id;
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
    final floatingBall = pickBool('floating_ball');
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
      floatingBall: floatingBall,
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
    super.dispose();
  }
}

/// 全局单例（main() 初始化后赋值）
late AppState appState;
