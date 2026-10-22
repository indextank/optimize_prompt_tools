/// 优化引擎：快速 / 深度 / 提问式三种模式。
///
/// 输出契约（六段式 JSON）：role / goal / requirements / constraints /
/// output_format / acceptance / score_before / score_after / diagnosis。
/// 模型返回非法 JSON 时自动重试一次（追加格式修正指令），仍失败则降级为
/// 纯文本结果（isStructured=false），绝不向调用方抛解析异常。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;

import '../core/errors.dart';
import '../core/model_specs.dart';
import '../core/models.dart';
import 'llm_client.dart';

/// 单次优化调用的进度回调
typedef OptimizeProgress = void Function(String accumulatedText);

/// 引擎运行结果（含元数据）
class EngineRunResult {
  const EngineRunResult({
    required this.result,
    required this.elapsedMs,
    this.totalTokens,
  });

  final OptimizeResult result;
  final int elapsedMs;
  final int? totalTokens;
}

/// 发送给 AI 的优化请求组装结果。
///
/// [system] 含技术背景段（如有）；[userMessages] 严格仅为待优化原始提示词
/// （及重试所需的对话追加），预置词内容绝不混入用户消息。
class OptimizeRequestPlan {
  const OptimizeRequestPlan({
    required this.system,
    required this.userMessages,
  });

  final String system;
  final List<ChatMessage> userMessages;
}

/// 优化引擎
class OptimizeEngine {
  OptimizeEngine({required LlmClient client}) : _client = client;

  final LlmClient _client;

  /// 单条输入长度上限
  static const int maxInputChars = 10000;

  /// 提问式优化问题数约束
  static const int minAskQuestions = 5;
  static const int maxAskQuestions = 8;

  /// 剥离模型可能误输出的代码围栏与首尾空白
  static String _stripFences(String text) {
    var t = text.trim();
    final m = RegExp(r'^```[a-zA-Z]*\s*\n([\s\S]*?)\n?```\s*$').firstMatch(t);
    if (m != null) t = m.group(1)!.trim();
    return t;
  }

  // -------------------------------------------------------------------------
  // 提示词模板
  // -------------------------------------------------------------------------

  static const String _contractDesc = '''
严格按以下 JSON 契约输出（禁止输出 JSON 以外的任何内容，不要用代码围栏）：
{
  "role": "角色定位（为 AI 指定最匹配该任务的专家角色与能力要求）",
  "goal": "任务目标（一句话说清要做什么、做到什么程度）",
  "requirements": ["具体要求 1", "具体要求 2"],
  "constraints": ["约束条件（技术栈/边界/禁止项）"],
  "output_format": "交付物形态与格式说明",
  "acceptance": ["可量化、可验证的验收标准"],
  "score_before": 0-100 的整数（对原始提示词质量的评分：角色/目标/背景/范围/产出/约束/验收/风险/验证/回复格式 十维各 10 分）,
  "score_after": 0-100 的整数（对优化后提示词的评分，同口径）,
  "diagnosis": [
    {"item": "诊断维度名", "status": "fixed 或 need_confirm",
     "before": "原始缺失描述", "action": "修复动作或待用户确认的建议"}
  ]
}''';

  static const String _corePrinciple = '''
你是提示词工程专家。任务：把用户的原始输入重写为可直接交给 AI 执行的高质量提示词。
核心原则：
1. 优化不是把话写长，而是降低 AI 的不确定性；
2. 缺失信息可推断则推断，不可推断则写出最小安全假设，并在 diagnosis 中以 need_confirm 显式列出；
3. 输出语言跟随用户输入语言。''';

  /// 简单模式系统提示词：一段连贯提示词，无分段/JSON 契约（步骤编号列表为唯一例外）
  static String _buildSimpleSystemPrompt(SceneTemplate scene,
          {CodingPreset? preset}) =>
      '''
$_corePrinciple
场景：${scene.name}。${scene.promptHint}${_techBgBlock(preset)}
场景指引仅用于提示需覆盖的信息维度，须将这些维度自然融入连贯正文，不得据此生成小标题、分段或逐项清单。
当前为简单模式：仅对用户的原始提示词做专业化重述与逻辑完善，精准强化原始需求。
简单模式下核心原则第 2 条调整为：缺失信息可推断则推断，不可推断则将最小安全假设以自然语句融入正文，不得单独输出「待确认」「假设说明」「diagnosis」等任何附加段。
硬性要求：
1. 输出连贯、完整、可直接交给 AI 执行的提示词正文，完全聚焦原始需求本身；
2. 禁止输出任何角色定位相关内容（不得出现「你是/扮演/作为……专家/工程师」等角色设定语句）；
3. 忠实保留原始需求的目标与关键参数（如指定语言、数量、格式、术语），长度与任务复杂度相称，
   禁止注水式扩写；若原文已足够清晰完整，仅做最小必要修正，不得为改而改；
4. 输出正文的语言与用户原始输入语言保持一致；不得把用户提出的语言要求本身翻译成目标语言
   （如「翻译成英文」须原样保留）；
5. 当原始需求包含或经梳理后形成多步骤执行流程时：先梳理所有步骤的逻辑依赖关系，确保执行顺序符合业务流程逻辑；
   再以规范的阿拉伯数字编号列表（1. 2. 3. …）将所有步骤依次单级罗列，不使用嵌套子编号；
   每个编号步骤表述完整、边界清晰、无模糊歧义，编号格式统一；
6. 除上述步骤编号列表外，禁止使用标题、加粗、无序列表符号（-、*）、分隔线、分段符号（如【】）或 JSON；
   正文内容本身需要的符号（如术语引号、代码标识符）可保留；
7. 只输出提示词正文本身，不要输出解释、前缀或代码围栏。''';

  /// 组装系统提示词
  static String buildSystemPrompt(SceneTemplate scene, OptimizeMode mode,
      {CodingPreset? preset}) {
    final sb = StringBuffer(_corePrinciple)
      ..writeln()
      ..writeln('场景：${scene.name}。${scene.promptHint}');
    if (mode == OptimizeMode.quick) {
      sb.writeln('当前为快速优化模式：直接重写为结构化提示词，diagnosis 可只保留关键项。');
    } else {
      sb.writeln('当前为深度优化模式：先做十维诊断（角色/目标/背景/现状/范围/产出/约束/验收/验证风险/回复格式），再重写。');
    }
    final techBg = buildTechBackground(preset);
    if (techBg != null) {
      sb.writeln();
      sb.writeln(techBg);
    }
    sb.writeln(_contractDesc);
    return sb.toString();
  }

  /// 组装「编程预置词」技术背景段（独立可单测）。
  ///
  /// 背景段明确声明：预置词内容仅用于说明待优化提示词所处的技术环境
  ///（平台 / 编程语言 / 技术架构等），**不是**优化对象、禁止拼接进优化结果。
  /// 未选择（null）或内容为空时返回 null（不注入，优化流程保持现状）。
  static String? buildTechBackground(CodingPreset? preset) {
    final content = preset?.content.trim() ?? '';
    if (content.isEmpty) return null;
    return '【技术背景】以下内容仅用于帮助理解待优化提示词所处的技术环境'
        '（如目标平台、编程语言、技术架构等），严禁将其视为需要优化的内容、'
        '严禁拼接进优化结果：\n$content';
  }

  /// system 模板内嵌的技术背景块（空内容返回空串，保持模板原样）
  static String _techBgBlock(CodingPreset? preset) {
    final bg = buildTechBackground(preset);
    return bg == null ? '' : '\n\n$bg';
  }

  /// 发送给 AI 的优化请求组装结果（[OptimizeRequestPlan]）。
  ///
  /// [system] 含技术背景段（如有）；[userMessages] 严格仅为待优化原始提示词，
  /// 预置词内容绝不混入用户消息。
  /// 组装优化请求（独立可单测）：简单/完整模式共用入口。
  ///
  /// [preset] 选定的编程预置词：以独立技术背景段注入 system，
  /// 与待优化原始提示词（user 消息）明确分离；未选择时请求与现状完全一致。
  static OptimizeRequestPlan assembleOptimizeRequest({
    required SceneTemplate scene,
    required OptimizeMode mode,
    required OutputStyle style,
    required String rawText,
    CodingPreset? preset,
  }) {
    final system = style == OutputStyle.simple
        ? _buildSimpleSystemPrompt(scene, preset: preset)
        : buildSystemPrompt(scene, mode, preset: preset);
    return OptimizeRequestPlan(
      system: system,
      userMessages: [ChatMessage('user', rawText)],
    );
  }

  String _buildAskSystemPrompt(SceneTemplate scene, {CodingPreset? preset}) => '''
$_corePrinciple
场景：${scene.name}。${scene.promptHint}${_techBgBlock(preset)}
当前为提问式优化模式的第一轮：不要直接重写，而是提出 $minAskQuestions-$maxAskQuestions 个会改变方案的关键澄清问题。
严格按以下 JSON 契约输出（禁止输出 JSON 以外的内容）：
{
  "questions": [
    {"question": "问题内容", "decides": "该问题的答案将决定什么"}
  ]
}''';

  // -------------------------------------------------------------------------
  // JSON 契约解析
  // -------------------------------------------------------------------------

  /// 从模型输出中提取首个 JSON 对象文本（容忍代码围栏与前后杂讯）
  static String? extractJsonObject(String text) {
    var t = text.trim();
    // 去掉 ```json ... ``` 围栏
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final m = fence.firstMatch(t);
    if (m != null) t = m.group(1)!.trim();
    final start = t.indexOf('{');
    if (start < 0) return null;
    // 平衡括号扫描（字符串感知）
    var depth = 0;
    var inStr = false;
    var escape = false;
    for (var i = start; i < t.length; i++) {
      final ch = t[i];
      if (inStr) {
        if (escape) {
          escape = false;
        } else if (ch == r'\') {
          escape = true;
        } else if (ch == '"') {
          inStr = false;
        }
        continue;
      }
      if (ch == '"') {
        inStr = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return t.substring(start, i + 1);
      }
    }
    return null;
  }

  /// 解析优化结果契约；不合法时抛出 FormatException
  static OptimizeResult parseResultContract(String text) {
    final jsonText = extractJsonObject(text);
    if (jsonText == null) throw const FormatException('未找到 JSON 对象');
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON 顶层不是对象');
    }
    final result = OptimizeResult.fromJson(decoded);
    if (!result.hasContent) throw const FormatException('契约内容为空');
    return result;
  }

  /// 解析提问式问题契约
  static List<ClarifyQuestion> parseQuestionsContract(String text) {
    final jsonText = extractJsonObject(text);
    if (jsonText == null) throw const FormatException('未找到 JSON 对象');
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) throw const FormatException('JSON 顶层不是对象');
    final qs = decoded['questions'];
    if (qs is! List) throw const FormatException('缺少 questions 数组');
    final list = qs
        .whereType<Map>()
        .map((e) => ClarifyQuestion.fromJson(Map<String, dynamic>.from(e)))
        .where((q) => q.question.trim().isNotEmpty)
        .toList();
    if (list.length < minAskQuestions || list.length > maxAskQuestions) {
      throw FormatException('问题数量 ${list.length} 不在 $minAskQuestions-$maxAskQuestions 范围');
    }
    return list;
  }

  // -------------------------------------------------------------------------
  // 调用
  // -------------------------------------------------------------------------

  ChatRequest _buildRequest(
    ServiceConfig service, {
    required String apiKey,
    required String system,
    required List<ChatMessage> messages,
  }) {
    final spec = getModelSpec(service.provider, service.model);
    return ChatRequest(
      baseUrl: service.apiUrl,
      apiKey: apiKey,
      model: service.model,
      messages: [ChatMessage('system', system), ...messages],
      temperature: spec.temperatureSupported ? service.temperature : null,
      maxTokens: service.maxOutputTokens,
      extraBody: buildThinkingPayload(service.provider, service.thinkingMode),
    );
  }

  Future<String> _collect(
    ChatRequest req, {
    CancelToken? cancelToken,
    OptimizeProgress? onProgress,
    void Function(int? totalTokens)? onUsage,
  }) async {
    final buf = StringBuffer();
    await for (final chunk in _client.chatStream(req, cancelToken: cancelToken)) {
      if (chunk.delta.isNotEmpty) {
        buf.write(chunk.delta);
        onProgress?.call(buf.toString());
      }
      if (chunk.totalTokens != null) onUsage?.call(chunk.totalTokens);
    }
    return buf.toString();
  }

  /// 快速 / 深度优化（含一次格式重试与降级）
  /// [style] 简单模式输出一段连贯提示词；完整模式输出六段式结构化契约
  Future<EngineRunResult> optimize(
    ServiceConfig service,
    String apiKey,
    String rawText, {
    OptimizeMode mode = OptimizeMode.deep,
    OutputStyle style = OutputStyle.full,
    SceneTemplate scene = kDefaultScene,
    CodingPreset? preset,
    CancelToken? cancelToken,
    OptimizeProgress? onProgress,
  }) async {
    final raw = rawText.trim();
    if (raw.isEmpty) {
      throw const LlmException(LlmErrorKind.badResponse, '原始提示词不能为空');
    }
    if (raw.length > maxInputChars) {
      throw LlmException(
          LlmErrorKind.badResponse, '输入长度 ${raw.length} 超过上限 $maxInputChars 字');
    }

    final sw = Stopwatch()..start();
    int? totalTokens;
    // 请求组装统一入口：预置词仅注入 system 作技术背景，user 消息仅为原文
    final plan = assembleOptimizeRequest(
        scene: scene, mode: mode, style: style, rawText: raw, preset: preset);
    // 简单模式：单段连贯提示词，无 JSON 契约、无需重试
    if (style == OutputStyle.simple) {
      final text = await _collect(
        _buildRequest(service,
            apiKey: apiKey,
            system: plan.system,
            messages: plan.userMessages),
        cancelToken: cancelToken,
        onProgress: onProgress,
        onUsage: (t) => totalTokens = t,
      );
      sw.stop();
      return EngineRunResult(
        result: OptimizeResult.unstructured(_stripFences(text)),
        elapsedMs: sw.elapsedMilliseconds,
        totalTokens: totalTokens,
      );
    }
    String system = plan.system;
    var messages = [...plan.userMessages];

    for (var attempt = 0; attempt < 2; attempt++) {
      final text = await _collect(
        _buildRequest(service, apiKey: apiKey, system: system, messages: messages),
        cancelToken: cancelToken,
        onProgress: onProgress,
        onUsage: (t) => totalTokens = t,
      );
      try {
        final result = parseResultContract(text);
        sw.stop();
        return EngineRunResult(
            result: result, elapsedMs: sw.elapsedMilliseconds, totalTokens: totalTokens);
      } on FormatException {
        if (attempt == 0) {
          // 追加格式修正指令重试一次
          messages = [
            ChatMessage('user', raw),
            ChatMessage('assistant', text),
            const ChatMessage('user', '你的输出不符合 JSON 契约。请仅重新输出合法 JSON，不要输出任何其他内容。'),
          ];
          continue;
        }
        // 二次失败：降级为纯文本
        sw.stop();
        return EngineRunResult(
          result: OptimizeResult.unstructured(text),
          elapsedMs: sw.elapsedMilliseconds,
          totalTokens: totalTokens,
        );
      }
    }
    // 不可达
    throw StateError('unreachable');
  }

  /// 提问式优化：第一轮，生成澄清问题
  Future<List<ClarifyQuestion>> askQuestions(
    ServiceConfig service,
    String apiKey,
    String rawText, {
    SceneTemplate scene = kDefaultScene,
    CodingPreset? preset,
    CancelToken? cancelToken,
  }) async {
    final raw = rawText.trim();
    if (raw.isEmpty) {
      throw const LlmException(LlmErrorKind.badResponse, '原始提示词不能为空');
    }
    final system = _buildAskSystemPrompt(scene, preset: preset);
    var messages = [ChatMessage('user', raw)];
    for (var attempt = 0; attempt < 2; attempt++) {
      final text =
          await _collect(_buildRequest(service, apiKey: apiKey, system: system, messages: messages), cancelToken: cancelToken);
      try {
        return parseQuestionsContract(text);
      } on FormatException {
        if (attempt == 0) {
          messages = [
            ChatMessage('user', raw),
            ChatMessage('assistant', text),
            const ChatMessage('user', '请仅重新输出符合契约的合法 JSON（questions 数组，5-8 个问题）。'),
          ];
          continue;
        }
        rethrow;
      }
    }
    throw StateError('unreachable');
  }

  /// 提问式优化：终轮，结合问答生成终稿
  ///
  /// [answers] 与 [questions] 等长；值为 null 表示「跳过/不确定」。
  Future<EngineRunResult> finalizeAsk(
    ServiceConfig service,
    String apiKey,
    String rawText,
    List<ClarifyQuestion> questions,
    List<String?> answers, {
    OutputStyle style = OutputStyle.full,
    SceneTemplate scene = kDefaultScene,
    CodingPreset? preset,
    CancelToken? cancelToken,
    OptimizeProgress? onProgress,
  }) async {
    if (answers.length != questions.length) {
      throw ArgumentError('answers 与 questions 长度不一致');
    }
    final qa = StringBuffer('以下是我对澄清问题的回答（标注「跳过」的请使用最小安全假设）：\n');
    for (var i = 0; i < questions.length; i++) {
      final a = answers[i];
      qa.writeln(
          'Q${i + 1}：${questions[i].question}\nA${i + 1}：${(a == null || a.trim().isEmpty) ? '跳过' : a.trim()}');
    }
    final sw = Stopwatch()..start();
    int? totalTokens;
    if (style == OutputStyle.simple) {
      final text = await _collect(
        _buildRequest(service,
            apiKey: apiKey,
            system: _buildSimpleSystemPrompt(scene, preset: preset),
            messages: [ChatMessage('user', '原始输入：$rawText\n\n$qa')]),
        cancelToken: cancelToken,
        onProgress: onProgress,
        onUsage: (t) => totalTokens = t,
      );
      sw.stop();
      return EngineRunResult(
        result: OptimizeResult.unstructured(_stripFences(text)),
        elapsedMs: sw.elapsedMilliseconds,
        totalTokens: totalTokens,
      );
    }
    final system =
        buildSystemPrompt(scene, OptimizeMode.deep, preset: preset);
    final messages = [ChatMessage('user', '原始输入：$rawText\n\n$qa')];
    for (var attempt = 0; attempt < 2; attempt++) {
      final text = await _collect(
        _buildRequest(service, apiKey: apiKey, system: system, messages: messages),
        cancelToken: cancelToken,
        onProgress: onProgress,
        onUsage: (t) => totalTokens = t,
      );
      try {
        final result = parseResultContract(text);
        sw.stop();
        return EngineRunResult(
            result: result, elapsedMs: sw.elapsedMilliseconds, totalTokens: totalTokens);
      } on FormatException {
        if (attempt == 0) {
          messages.addAll([
            ChatMessage('assistant', text),
            const ChatMessage('user', '你的输出不符合 JSON 契约。请仅重新输出合法 JSON。'),
          ]);
          continue;
        }
        sw.stop();
        return EngineRunResult(
          result: OptimizeResult.unstructured(text),
          elapsedMs: sw.elapsedMilliseconds,
          totalTokens: totalTokens,
        );
      }
    }
    throw StateError('unreachable');
  }

  /// 复查编辑页「让 AI 重写此段」：仅重写指定段落，保持其余段落语境
  Future<String> rewriteSection(
    ServiceConfig service,
    String apiKey,
    OptimizeResult current,
    String sectionKey,
    String sectionTitle,
    String currentContent, {
    String instruction = '',
    CancelToken? cancelToken,
  }) async {
    final system = '''
你是提示词工程专家。用户正在编辑一条结构化提示词的「$sectionTitle」段落。
完整提示词当前内容如下：
---
${current.toPlainText()}
---
请仅重写「$sectionTitle」这一段的内容，保持与其他段落风格一致、不重复其他段内容。
${instruction.isEmpty ? '' : '用户修改要求：$instruction\n'}
直接输出重写后的段落正文，不要输出标题、不要解释。''';
    final req = ChatRequest(
      baseUrl: service.apiUrl,
      apiKey: apiKey,
      model: service.model,
      messages: [
        ChatMessage('system', system),
        ChatMessage('user', '当前「$sectionTitle」内容：\n$currentContent'),
      ],
      temperature: 0.7,
      maxTokens: service.maxOutputTokens,
      extraBody: buildThinkingPayload(service.provider, service.thinkingMode),
    );
    final text = await _collect(req, cancelToken: cancelToken);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const LlmException(LlmErrorKind.badResponse, '重写结果为空');
    }
    return trimmed;
  }
}
