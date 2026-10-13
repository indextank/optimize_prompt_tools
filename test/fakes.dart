/// 测试共享基建：假 LLM 客户端 / 假文件保存器 / 应用状态装配。
library;

import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:prompt_optimizer/core/errors.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/export_service.dart';
import 'package:prompt_optimizer/services/key_store.dart';
import 'package:prompt_optimizer/services/llm_client.dart';
import 'package:prompt_optimizer/services/optimize_engine.dart';
import 'package:prompt_optimizer/services/settings_service.dart';
import 'package:prompt_optimizer/services/storage/app_storage.dart';
import 'package:prompt_optimizer/services/storage/sqlite_storage.dart';
import 'package:prompt_optimizer/state/app_state.dart';

/// 脚本化的假 LLM 客户端：按队列依次响应；可记录请求体供断言。
class FakeLlmClient implements LlmClient {
  /// 每个元素：String（正常输出，按 chunkSize 切片流式发出）或 Exception（抛出）
  final List<Object> responses = [];

  /// 记录所有 chatStream 请求
  final List<ChatRequest> capturedRequests = [];

  /// listModels 的返回（null 时走 [listModelsResult] 默认）
  List<String>? listModelsResult;
  Object? listModelsError;

  /// testConnection 结果
  ConnectionTestResult connectionResult =
      const ConnectionTestResult(success: true, latencyMs: 123);

  /// testConnection 人为延迟（用于观测检测进行中的按钮置灰态）
  Duration connectionLatency = Duration.zero;

  int chunkSize = 7;

  /// 每个流式分片之间的人为延迟（取消/竞态类用例使用，默认零延迟）
  Duration chunkDelay = Duration.zero;

  void enqueueText(String text) => responses.add(text);
  void enqueueError(Object error) => responses.add(error);

  @override
  Stream<LlmChunk> chatStream(ChatRequest request, {CancelToken? cancelToken}) {
    capturedRequests.add(request);
    final resp = responses.isEmpty ? '' : responses.removeAt(0);
    if (resp is Exception) {
      return Stream.error(resp);
    }
    final text = resp as String;
    final chunks = <LlmChunk>[];
    for (var i = 0; i < text.length; i += chunkSize) {
      chunks.add(LlmChunk(
          delta: text.substring(i,
              i + chunkSize > text.length ? text.length : i + chunkSize)));
    }
    chunks.add(const LlmChunk(done: true, totalTokens: 42));
    // 响应取消令牌
    if (cancelToken != null) {
      final controller = StreamController<LlmChunk>();
      var cancelled = false;
      unawaited(cancelToken.whenCancel.then((_) {
        cancelled = true;
        if (!controller.isClosed) {
          controller.addError(
              const LlmException(LlmErrorKind.cancelled, 'cancelled'));
          controller.close();
        }
      }));
      unawaited(Future(() async {
        for (final c in chunks) {
          if (cancelled || controller.isClosed) break;
          controller.add(c);
          await Future<void>.delayed(chunkDelay);
        }
        if (!controller.isClosed) await controller.close();
      }));
      return controller.stream;
    }
    return Stream.fromIterable(chunks);
  }

  @override
  Future<List<String>> listModels(String baseUrl, String apiKey,
      {String endpoint = '/models',
      Duration timeout = const Duration(seconds: 15)}) async {
    if (listModelsError != null) throw listModelsError!;
    return listModelsResult ?? ['model-a', 'model-b'];
  }

  @override
  Future<ConnectionTestResult> testConnection(ChatRequest request) async {
    if (connectionLatency > Duration.zero) {
      await Future<void>.delayed(connectionLatency);
    }
    return connectionResult;
  }
}

/// 假文件保存器
class FakeFileSaver implements FileSaver {
  String? lastName;
  String? lastExt;
  List<int>? lastBytes;
  String? nextPath = '/tmp/out';

  /// pickFile 注入：下一次「打开文件」返回的内容（null=用户取消）
  PickedFile? nextPickFile;
  List<String>? lastPickExtensions;

  @override
  Future<PickedFile?> pickFile({required List<String> extensions}) async {
    lastPickExtensions = extensions;
    return nextPickFile;
  }

  @override
  Future<String?> save(
      {required String suggestedName,
      required String ext,
      required List<int> bytes}) async {
    lastName = suggestedName;
    lastExt = ext;
    lastBytes = bytes;
    return nextPath == null ? null : '$nextPath.$suggestedName.$ext';
  }
}

/// 内存应用状态装配（全部测试共用）
Future<AppState> makeTestAppState({
  FakeLlmClient? llm,
  AppStorage? storage,
  KeyStore? keyStore,
  AppSettings? initialSettings,
}) async {
  final st = storage ?? SqliteStorage.inMemory();
  final settings = await SettingsService.load(st);
  if (initialSettings != null) {
    await settings.update(initialSettings);
  }
  final client = llm ?? FakeLlmClient();
  final state = AppState(
    storage: st,
    keyStore: keyStore ?? MemoryKeyStore(),
    settings: settings,
    engine: OptimizeEngine(client: client),
    llmClient: client,
  );
  await state.init();
  return state;
}

/// 便捷构造服务配置
ServiceConfig testService({
  String id = 'svc-1',
  String provider = 'deepseek',
  String model = 'deepseek-flash',
  bool isDefault = true,
}) =>
    ServiceConfig(
      id: id,
      provider: provider,
      apiUrl: 'https://api.deepseek.com',
      keyRef: id,
      model: model,
      isDefault: isDefault,
      createdAt: 1759700000,
    );

/// 合法六段式契约 JSON 文本
const String kValidContractJson = '''
{
  "role": "资深 Python 工程师",
  "goal": "抓取豆瓣 Top250 并存入 Excel",
  "requirements": ["自动分页", "字段完整"],
  "constraints": ["requests + BeautifulSoup"],
  "output_format": "top250.xlsx",
  "acceptance": ["250 条无缺失"],
  "score_before": 62,
  "score_after": 92,
  "diagnosis": [
    {"item": "角色定位", "status": "fixed", "before": "未指定角色", "action": "已补充角色"}
  ]
}''';

/// 提问式契约
const String kValidQuestionsJson = '''
{
  "questions": [
    {"question": "目标站点有反爬吗？", "decides": "反爬策略"},
    {"question": "数据量级？", "decides": "存储方案"},
    {"question": "运行环境？", "decides": "依赖选型"},
    {"question": "更新频率？", "decides": "调度设计"},
    {"question": "字段明细？", "decides": "表结构"}
  ]
}''';
