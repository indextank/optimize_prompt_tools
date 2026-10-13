/// OpenAI 兼容协议的统一 LLM 客户端（SSE 流式）。
///
/// 九家服务商全部走 `POST {baseUrl}/chat/completions` + Bearer Key；
/// 差异参数（思考模式等）通过 [ChatRequest.extraBody] 注入。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/errors.dart';

/// 一条聊天消息
class ChatMessage {
  const ChatMessage(this.role, this.content);
  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// 对话请求
class ChatRequest {
  const ChatRequest({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.messages,
    this.temperature,
    this.maxTokens,
    this.extraBody = const {},
    this.timeout = const Duration(seconds: 30),
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final List<ChatMessage> messages;
  final double? temperature;
  final int? maxTokens;
  final Map<String, dynamic> extraBody;
  final Duration timeout;

  Map<String, dynamic> buildBody({required bool stream}) {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': stream,
    };
    if (temperature != null) body['temperature'] = temperature;
    if (maxTokens != null) body['max_tokens'] = maxTokens;
    body.addAll(extraBody);
    if (stream) {
      // 尽量让服务商在末片返回 token 用量（OpenAI 兼容扩展，不支持的服务商会忽略）
      body['stream_options'] = {'include_usage': true};
    }
    return body;
  }
}

/// 流式响应分片
class LlmChunk {
  const LlmChunk({this.delta = '', this.done = false, this.totalTokens});

  final String delta;
  final bool done;

  /// 末片携带的 token 用量（服务商支持时）
  final int? totalTokens;
}

/// 连接测试结果
class ConnectionTestResult {
  const ConnectionTestResult({
    required this.success,
    required this.latencyMs,
    this.message = '',
  });

  final bool success;
  final int latencyMs;
  final String message;
}

/// SSE 行解析器（纯函数，独立可测）
///
/// 输入 SSE 文本流（可能按任意字节边界切分），输出解析后的 JSON data 载荷。
class SseParser {
  SseParser({void Function(String data)? onData}) : _onData = onData;

  final void Function(String data)? _onData;
  final StringBuffer _lineBuf = StringBuffer();
  final StringBuffer _dataBuf = StringBuffer();
  bool _hasData = false;

  /// 喂入一段原始文本
  void feed(String text) {
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '\n') {
        _flushLine();
      } else if (ch != '\r') {
        _lineBuf.write(ch);
      }
    }
  }

  /// 流结束时冲刷残余
  void close() {
    if (_lineBuf.isNotEmpty) _flushLine();
    _dispatchData();
  }

  void _flushLine() {
    final line = _lineBuf.toString();
    _lineBuf.clear();
    if (line.isEmpty) {
      // 空行：事件边界
      _dispatchData();
      return;
    }
    if (line.startsWith(':')) return; // keep-alive 注释
    final idx = line.indexOf(':');
    final field = idx < 0 ? line : line.substring(0, idx);
    var value = idx < 0 ? '' : line.substring(idx + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'data') {
      if (_hasData) _dataBuf.write('\n');
      _dataBuf.write(value);
      _hasData = true;
    }
    // event:/id:/retry: 忽略
  }

  void _dispatchData() {
    if (!_hasData) return;
    final data = _dataBuf.toString();
    _dataBuf.clear();
    _hasData = false;
    _onData?.call(data);
  }
}

/// LLM 客户端抽象（便于测试注入假实现）
abstract class LlmClient {
  /// 流式对话
  Stream<LlmChunk> chatStream(ChatRequest request, {CancelToken? cancelToken});

  /// 在线拉取模型列表
  Future<List<String>> listModels(String baseUrl, String apiKey,
      {String endpoint = '/models', Duration timeout = const Duration(seconds: 15)});

  /// 测试连接（测量延迟）
  Future<ConnectionTestResult> testConnection(ChatRequest request);
}

/// OpenAI 兼容客户端实现
class OpenAiCompatibleClient implements LlmClient {
  OpenAiCompatibleClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Options _options(ChatRequest req, {required bool stream}) => Options(
        headers: {
          'Authorization': 'Bearer ${req.apiKey}',
          'Content-Type': 'application/json',
          if (stream) 'Accept': 'text/event-stream',
        },
        responseType: stream ? ResponseType.stream : ResponseType.json,
        sendTimeout: req.timeout,
        receiveTimeout: req.timeout,
      );

  Never _mapDioError(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      throw const LlmException(LlmErrorKind.cancelled, 'cancelled');
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      throw LlmException(LlmErrorKind.timeout, e.message ?? 'timeout');
    }
    final code = e.response?.statusCode;
    if (code == 401) throw LlmException(LlmErrorKind.unauthorized, 'unauthorized', statusCode: code);
    if (code == 403) throw LlmException(LlmErrorKind.forbidden, 'forbidden', statusCode: code);
    if (code == 404) throw LlmException(LlmErrorKind.notFound, 'not found', statusCode: code);
    if (code == 429) throw LlmException(LlmErrorKind.rateLimited, 'rate limited', statusCode: code);
    if (code != null && code >= 500) {
      throw LlmException(LlmErrorKind.serverError, 'server error', statusCode: code);
    }
    throw LlmException(LlmErrorKind.network, e.message ?? 'network error', statusCode: code);
  }

  @override
  Stream<LlmChunk> chatStream(ChatRequest request, {CancelToken? cancelToken}) async* {
    final Response<ResponseBody> resp;
    try {
      resp = await _dio.post<ResponseBody>(
        '${request.baseUrl}/chat/completions',
        data: request.buildBody(stream: true),
        options: _options(request, stream: true),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      _mapDioError(e);
    }

    final controller = StreamController<LlmChunk>();
    var emittedDone = false;

    void handleData(String data) {
      if (data.trim() == '[DONE]') {
        if (!emittedDone) {
          emittedDone = true;
          controller.add(const LlmChunk(done: true));
        }
        return;
      }
      Map<String, dynamic> j;
      try {
        j = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return; // 跳过无法解析的分片
      }
      // token 用量（末片）
      final usage = j['usage'];
      int? totalTokens;
      if (usage is Map && usage['total_tokens'] is num) {
        totalTokens = (usage['total_tokens'] as num).toInt();
      }
      final choices = j['choices'];
      String delta = '';
      var finish = false;
      if (choices is List && choices.isNotEmpty) {
        final c = choices.first;
        if (c is Map) {
          final d = c['delta'];
          if (d is Map && d['content'] is String) delta = d['content'] as String;
          finish = c['finish_reason'] != null;
        }
      }
      if (delta.isNotEmpty || totalTokens != null || finish) {
        controller.add(LlmChunk(delta: delta, totalTokens: totalTokens));
      }
      if (finish && !emittedDone) {
        emittedDone = true;
        controller.add(LlmChunk(done: true, totalTokens: totalTokens));
      }
    }

    final p = SseParser(onData: handleData);
    final stream = resp.data?.stream;
    if (stream == null) {
      unawaited(Future(() async {
        controller.add(const LlmChunk(done: true));
        await controller.close();
      }));
      yield* controller.stream;
      return;
    }

    unawaited(Future(() async {
      try {
        await for (final bytes in stream) {
          p.feed(utf8.decode(bytes, allowMalformed: true));
        }
        p.close();
        if (!emittedDone) controller.add(const LlmChunk(done: true));
      } on DioException catch (e) {
        try {
          _mapDioError(e);
        } on LlmException catch (le) {
          controller.addError(le);
        }
      } catch (e) {
        controller.addError(LlmException(LlmErrorKind.badResponse, '$e'));
      } finally {
        await controller.close();
      }
    }));
    yield* controller.stream;
  }

  @override
  Future<List<String>> listModels(String baseUrl, String apiKey,
      {String endpoint = '/models', Duration timeout = const Duration(seconds: 15)}) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '$baseUrl$endpoint',
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          sendTimeout: timeout,
          receiveTimeout: timeout,
        ),
      );
      final data = resp.data?['data'];
      if (data is! List) {
        throw const LlmException(LlmErrorKind.badResponse, '缺少 data 字段');
      }
      final ids = data
          .whereType<Map>()
          .map((e) => e['id'])
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
      return ids;
    } on DioException catch (e) {
      _mapDioError(e);
    }
  }

  @override
  Future<ConnectionTestResult> testConnection(ChatRequest request) async {
    final sw = Stopwatch()..start();
    try {
      // 用最小 max_tokens 的非流式请求探测连通性与鉴权
      final probe = ChatRequest(
        baseUrl: request.baseUrl,
        apiKey: request.apiKey,
        model: request.model,
        messages: const [ChatMessage('user', 'ping')],
        maxTokens: 1,
        timeout: request.timeout,
      );
      await _dio.post<Map<String, dynamic>>(
        '${request.baseUrl}/chat/completions',
        data: probe.buildBody(stream: false),
        options: _options(probe, stream: false),
      );
      sw.stop();
      return ConnectionTestResult(success: true, latencyMs: sw.elapsedMilliseconds);
    } on DioException catch (e) {
      sw.stop();
      try {
        _mapDioError(e);
      } on LlmException catch (le) {
        return ConnectionTestResult(
            success: false, latencyMs: sw.elapsedMilliseconds, message: le.userMessage);
      }
    }
  }
}
