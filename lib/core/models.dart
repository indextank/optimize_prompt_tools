/// 核心数据模型（服务配置 / 优化结果 / 历史记录 / 场景模板）
library;

import 'model_specs.dart';

/// 优化模式
enum OptimizeMode {
  quick('快速优化'),
  deep('深度优化'),
  ask('提问式优化');

  const OptimizeMode(this.label);
  final String label;

  static OptimizeMode parse(String v) =>
      OptimizeMode.values.firstWhere((e) => e.name == v, orElse: () => OptimizeMode.deep);
}

/// 优化结果输出详略：简单模式=一段连贯提示词；完整模式=六段式结构化契约
enum OutputStyle {
  simple('简单模式'),
  full('完整模式');

  const OutputStyle(this.label);
  final String label;

  static OutputStyle parse(String v) =>
      v == OutputStyle.full.name ? OutputStyle.full : OutputStyle.simple;
}

/// AI 服务配置（密钥仅存 [keyRef] 引用，明文由 KeyStore 托管）
class ServiceConfig {
  const ServiceConfig({
    required this.id,
    required this.provider,
    required this.apiUrl,
    this.keyRef = '',
    this.model = '',
    this.temperature = 1.0,
    this.maxInputTokens = 128000,
    this.maxOutputTokens = 16384,
    this.thinkingMode = kThinkingModeDefault,
    this.imageInput = false,
    this.isDefault = false,
    this.createdAt = 0,
  });

  final String id;
  final String provider;
  final String apiUrl;
  final String keyRef;
  final String model;
  final double temperature;
  final int maxInputTokens;
  final int maxOutputTokens;

  /// default | on | off
  final String thinkingMode;
  final bool imageInput;
  final bool isDefault;
  final int createdAt;

  ServiceConfig copyWith({
    String? id,
    String? provider,
    String? apiUrl,
    String? keyRef,
    String? model,
    double? temperature,
    int? maxInputTokens,
    int? maxOutputTokens,
    String? thinkingMode,
    bool? imageInput,
    bool? isDefault,
    int? createdAt,
  }) =>
      ServiceConfig(
        id: id ?? this.id,
        provider: provider ?? this.provider,
        apiUrl: apiUrl ?? this.apiUrl,
        keyRef: keyRef ?? this.keyRef,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
        maxInputTokens: maxInputTokens ?? this.maxInputTokens,
        maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
        thinkingMode: thinkingMode ?? this.thinkingMode,
        imageInput: imageInput ?? this.imageInput,
        isDefault: isDefault ?? this.isDefault,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider,
        'api_url': apiUrl,
        'key_ref': keyRef,
        'model': model,
        'temperature': temperature,
        'max_input_tokens': maxInputTokens,
        'max_output_tokens': maxOutputTokens,
        'thinking_mode': thinkingMode,
        'image_input': imageInput,
        'is_default': isDefault,
        'created_at': createdAt,
      };

  /// 导出用（不含任何密钥相关信息）
  Map<String, dynamic> toExportJson() => {
        'provider': provider,
        'api_url': apiUrl,
        'model': model,
        'temperature': temperature,
        'max_input_tokens': maxInputTokens,
        'max_output_tokens': maxOutputTokens,
        'thinking_mode': thinkingMode,
        'image_input': imageInput,
        'is_default': isDefault,
      };

  factory ServiceConfig.fromJson(Map<String, dynamic> j) => ServiceConfig(
        id: j['id'] as String? ?? '',
        provider: j['provider'] as String? ?? '',
        apiUrl: j['api_url'] as String? ?? '',
        keyRef: j['key_ref'] as String? ?? '',
        model: j['model'] as String? ?? '',
        temperature: (j['temperature'] as num?)?.toDouble() ?? 1.0,
        maxInputTokens: (j['max_input_tokens'] as num?)?.toInt() ?? 128000,
        maxOutputTokens: (j['max_output_tokens'] as num?)?.toInt() ?? 16384,
        thinkingMode: j['thinking_mode'] as String? ?? kThinkingModeDefault,
        imageInput: j['image_input'] as bool? ?? false,
        isDefault: j['is_default'] as bool? ?? false,
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// 诊断项（十维诊断结果之一）
class DiagnosisItem {
  const DiagnosisItem({
    required this.item,
    required this.status,
    this.before = '',
    this.action = '',
  });

  final String item;

  /// fixed | need_confirm
  final String status;
  final String before;
  final String action;

  bool get isFixed => status == 'fixed';

  Map<String, dynamic> toJson() =>
      {'item': item, 'status': status, 'before': before, 'action': action};

  factory DiagnosisItem.fromJson(Map<String, dynamic> j) => DiagnosisItem(
        item: j['item'] as String? ?? '',
        status: j['status'] as String? ?? 'fixed',
        before: j['before'] as String? ?? '',
        action: j['action'] as String? ?? '',
      );
}

/// 六段式结构化优化结果
class OptimizeResult {
  const OptimizeResult({
    this.role = '',
    this.goal = '',
    this.requirements = const [],
    this.constraints = const [],
    this.outputFormat = '',
    this.acceptance = const [],
    this.scoreBefore,
    this.scoreAfter,
    this.diagnosis = const [],
    this.rawText = '',
    this.isStructured = true,
  });

  final String role;
  final String goal;
  final List<String> requirements;
  final List<String> constraints;
  final String outputFormat;
  final List<String> acceptance;
  final int? scoreBefore;
  final int? scoreAfter;
  final List<DiagnosisItem> diagnosis;

  /// 未结构化降级时的原文
  final String rawText;

  /// 是否按六段式契约解析成功
  final bool isStructured;

  static int? _clampScore(dynamic v) {
    if (v is! num) return null;
    return v.round().clamp(0, 100);
  }

  /// 宽松解析（契约字段缺失时给默认值，不抛异常）
  factory OptimizeResult.fromJson(Map<String, dynamic> j) => OptimizeResult(
        role: j['role'] as String? ?? '',
        goal: j['goal'] as String? ?? '',
        requirements: _strList(j['requirements']),
        constraints: _strList(j['constraints']),
        outputFormat: j['output_format'] as String? ?? '',
        acceptance: _strList(j['acceptance']),
        scoreBefore: _clampScore(j['score_before']),
        scoreAfter: _clampScore(j['score_after']),
        diagnosis: (j['diagnosis'] as List?)
                ?.whereType<Map>()
                .map((e) => DiagnosisItem.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
      );

  /// 非结构化降级构造
  factory OptimizeResult.unstructured(String text, {int? scoreBefore}) => OptimizeResult(
        rawText: text,
        isStructured: false,
        scoreBefore: scoreBefore,
      );

  static List<String> _strList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  Map<String, dynamic> toJson() => {
        'role': role,
        'goal': goal,
        'requirements': requirements,
        'constraints': constraints,
        'output_format': outputFormat,
        'acceptance': acceptance,
        'score_before': scoreBefore,
        'score_after': scoreAfter,
        'diagnosis': diagnosis.map((e) => e.toJson()).toList(),
        'raw_text': rawText,
        'is_structured': isStructured,
      };

  factory OptimizeResult.fromStoredJson(Map<String, dynamic> j) => OptimizeResult.fromJson(j)
      .copyWithRaw(rawText: j['raw_text'] as String? ?? '', isStructured: j['is_structured'] as bool? ?? true);

  OptimizeResult copyWithRaw({String? rawText, bool? isStructured}) => OptimizeResult(
        role: role,
        goal: goal,
        requirements: requirements,
        constraints: constraints,
        outputFormat: outputFormat,
        acceptance: acceptance,
        scoreBefore: scoreBefore,
        scoreAfter: scoreAfter,
        diagnosis: diagnosis,
        rawText: rawText ?? this.rawText,
        isStructured: isStructured ?? this.isStructured,
      );

  OptimizeResult copyWithSections({
    String? role,
    String? goal,
    List<String>? requirements,
    List<String>? constraints,
    String? outputFormat,
    List<String>? acceptance,
  }) =>
      OptimizeResult(
        role: role ?? this.role,
        goal: goal ?? this.goal,
        requirements: requirements ?? this.requirements,
        constraints: constraints ?? this.constraints,
        outputFormat: outputFormat ?? this.outputFormat,
        acceptance: acceptance ?? this.acceptance,
        scoreBefore: scoreBefore,
        scoreAfter: scoreAfter,
        diagnosis: diagnosis,
        rawText: rawText,
        isStructured: isStructured,
      );

  /// 渲染为可复制/导出的纯文本（六段式）
  String toPlainText() {
    if (!isStructured) return rawText;
    final b = StringBuffer();
    void sec(String title, String body) {
      if (body.trim().isEmpty) return;
      b.writeln('【$title】');
      b.writeln(body.trim());
      b.writeln();
    }

    void listSec(String title, List<String> items) {
      if (items.isEmpty) return;
      b.writeln('【$title】');
      for (var i = 0; i < items.length; i++) {
        b.writeln('${i + 1}. ${items[i]}');
      }
      b.writeln();
    }

    sec('角色定位', role);
    sec('任务目标', goal);
    listSec('具体要求', requirements);
    listSec('约束条件', constraints);
    sec('输出格式', outputFormat);
    listSec('验收标准', acceptance);
    return b.toString().trimRight();
  }

  /// 是否有可展示内容
  bool get hasContent =>
      isStructured ? toPlainText().isNotEmpty : rawText.trim().isNotEmpty;
}

/// 优化记录中的一个版本
class OptimizeVersion {
  const OptimizeVersion({
    required this.v,
    required this.result,
    this.edited = false,
    this.createdAt = 0,
  });

  final int v;
  final OptimizeResult result;
  final bool edited;
  final int createdAt;

  Map<String, dynamic> toJson() =>
      {'v': v, 'result': result.toJson(), 'edited': edited, 'created_at': createdAt};

  factory OptimizeVersion.fromJson(Map<String, dynamic> j) => OptimizeVersion(
        v: (j['v'] as num?)?.toInt() ?? 1,
        result: OptimizeResult.fromStoredJson(
            Map<String, dynamic>.from(j['result'] as Map? ?? const {})),
        edited: j['edited'] as bool? ?? false,
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      );
}

/// 历史记录（含版本链）
class OptimizeRecord {
  const OptimizeRecord({
    required this.id,
    required this.scene,
    required this.mode,
    required this.rawText,
    required this.versions,
    required this.providers,
    this.scoreBefore,
    this.scoreAfter,
    this.elapsedMs = 0,
    this.tokens = 0,
    required this.createdAt,
  });

  final String id;
  final String scene;
  final OptimizeMode mode;
  final String rawText;
  final List<OptimizeVersion> versions;
  final List<String> providers;
  final int? scoreBefore;
  final int? scoreAfter;
  final int elapsedMs;
  final int tokens;
  final int createdAt;

  OptimizeVersion get latest => versions.isEmpty
      ? OptimizeVersion(v: 0, result: const OptimizeResult(rawText: '', isStructured: false))
      : versions.reduce((a, b) => a.v >= b.v ? a : b);

  Map<String, dynamic> toJson() => {
        'id': id,
        'scene': scene,
        'mode': mode.name,
        'raw_text': rawText,
        'versions': versions.map((e) => e.toJson()).toList(),
        'providers': providers,
        'score_before': scoreBefore,
        'score_after': scoreAfter,
        'elapsed_ms': elapsedMs,
        'tokens': tokens,
        'created_at': createdAt,
      };

  factory OptimizeRecord.fromJson(Map<String, dynamic> j) => OptimizeRecord(
        id: j['id'] as String? ?? '',
        scene: j['scene'] as String? ?? 'general',
        mode: OptimizeMode.parse(j['mode'] as String? ?? 'deep'),
        rawText: j['raw_text'] as String? ?? '',
        versions: (j['versions'] as List?)
                ?.whereType<Map>()
                .map((e) => OptimizeVersion.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        providers: (j['providers'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        scoreBefore: (j['score_before'] as num?)?.toInt(),
        scoreAfter: (j['score_after'] as num?)?.toInt(),
        elapsedMs: (j['elapsed_ms'] as num?)?.toInt() ?? 0,
        tokens: (j['tokens'] as num?)?.toInt() ?? 0,
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
      );

  OptimizeRecord copyWith({List<OptimizeVersion>? versions}) => OptimizeRecord(
        id: id,
        scene: scene,
        mode: mode,
        rawText: rawText,
        versions: versions ?? this.versions,
        providers: providers,
        scoreBefore: scoreBefore,
        scoreAfter: scoreAfter,
        elapsedMs: elapsedMs,
        tokens: tokens,
        createdAt: createdAt,
      );
}

/// 场景模板
class SceneTemplate {
  const SceneTemplate({
    required this.id,
    required this.name,
    required this.promptHint,
    this.builtin = false,
  });

  final String id;
  final String name;

  /// 注入系统提示词的场景指引
  final String promptHint;
  final bool builtin;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'prompt_hint': promptHint, 'builtin': builtin};

  factory SceneTemplate.fromJson(Map<String, dynamic> j) => SceneTemplate(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        promptHint: j['prompt_hint'] as String? ?? '',
        builtin: j['builtin'] as bool? ?? false,
      );
}

/// 默认场景（通用）——编译期常量，供默认参数使用
const SceneTemplate kDefaultScene = SceneTemplate(
  id: 'general',
  name: '通用',
  promptHint: '通用场景。输出结构完整、可执行即可。',
  builtin: true,
);

/// 内置 8 类场景模板（对齐对标指标）
const List<SceneTemplate> kBuiltinScenes = [
  kDefaultScene,
  SceneTemplate(
    id: 'ai_coding',
    name: 'AI 编程',
    promptHint: '编程任务。明确要求技术栈约束、错误处理（loading/error/empty）、类型安全、可测试性与验收标准。',
    builtin: true,
  ),
  SceneTemplate(
    id: 'bug_fix',
    name: 'Bug 修复',
    promptHint: 'Bug 修复任务。明确要求复现步骤、根因定位、最小修复范围、回归验证方法。',
    builtin: true,
  ),
  SceneTemplate(
    id: 'writing',
    name: '文案写作',
    promptHint: '文案创作。明确目标读者、语气风格、篇幅、禁用表达与交付格式。',
    builtin: true,
  ),
  SceneTemplate(
    id: 'translate',
    name: '翻译润色',
    promptHint: '翻译/润色任务。明确源语言与目标语言、术语一致性要求、风格保留程度。',
    builtin: true,
  ),
  SceneTemplate(
    id: 'draw',
    name: '绘画提示词',
    promptHint: '文生图提示词。明确画面主体、风格、构图、光线、色彩与负面约束。',
    builtin: true,
  ),
  SceneTemplate(
    id: 'data_analysis',
    name: '数据分析',
    promptHint: '数据分析任务。明确数据来源/口径、指标定义、分析方法、可视化与结论输出格式。',
    builtin: true,
  ),
  SceneTemplate(
    id: 'prd',
    name: 'PRD 文档',
    promptHint: '产品需求文档。明确背景与目标、用户故事、功能范围与边界、交互说明、验收标准。',
    builtin: true,
  ),
];

/// 提问式优化：单个澄清问题
class ClarifyQuestion {
  const ClarifyQuestion({required this.question, required this.decides});

  final String question;

  /// 该问题会决定什么（对齐 Trae「每问注明决定什么」）
  final String decides;

  Map<String, dynamic> toJson() => {'question': question, 'decides': decides};

  factory ClarifyQuestion.fromJson(Map<String, dynamic> j) => ClarifyQuestion(
        question: j['question'] as String? ?? '',
        decides: j['decides'] as String? ?? '',
      );
}
