/// AI 模型规格与能力数据（移植自基准项目 EBook Master Pro `app/ai_model_specs.py`）。
///
/// 为「添加AI服务」弹窗提供模型联动的自动配置数据：
/// - 上下文窗口 / 最大输入 Token / 最大输出 Token（含官方默认值）
/// - Temperature 官方取值范围与默认值
/// - 思考（推理）模式支持情况：none / toggle / forcedOn
/// - 图片（多模态）输入支持情况
///
/// 数据来源均为各服务商官方文档（运行时不需要联网）；豆包、文心一言两家
/// 未内置逐模型官方值，按基准同款机制走服务商级保守回退（[kFallbackSpecs]）。
library;

/// 思考模式支持情况
enum ThinkingSupport {
  /// 不支持推理思考（配置项锁定为「跟随模型默认配置」）
  none,

  /// 支持开启/关闭（三种选项均可选）
  toggle,

  /// 强制开启（仅「跟随模型默认配置/开启」可选）
  forcedOn;

  static ThinkingSupport parse(String v) => switch (v) {
        'toggle' => ThinkingSupport.toggle,
        'forced_on' => ThinkingSupport.forcedOn,
        _ => ThinkingSupport.none,
      };
}

/// 单模型规格
class ModelSpec {
  const ModelSpec({
    required this.contextWindow,
    required this.maxInputTokens,
    required this.maxOutputTokens,
    required this.maxOutputDefault,
    this.maxOutputDocumented = true,
    required this.temperatureMin,
    required this.temperatureMax,
    required this.temperatureDefault,
    this.temperatureSupported = true,
    this.thinking = ThinkingSupport.none,
    this.vision = false,
    this.isFallback = false,
    this.provider = '',
    this.model = '',
  });

  /// 上下文窗口（tokens，官方公布值）
  final int contextWindow;

  /// 「最大输入Token」默认值（官方公布的最大输入长度；未单独公布时 = 上下文窗口）
  final int maxInputTokens;

  /// 「最大输出Token」允许上限（官方公布的最大输出长度）
  final int maxOutputTokens;

  /// 「最大输出Token」默认值（官方默认；未公布时取保守值 8192）
  final int maxOutputDefault;

  /// 官方是否单独公布了最大输出长度
  final bool maxOutputDocumented;

  final double temperatureMin;
  final double temperatureMax;
  final double temperatureDefault;

  /// 模型是否接受 Temperature 参数
  final bool temperatureSupported;
  final ThinkingSupport thinking;
  final bool vision;

  /// 是否来自服务商级回退（未内置适配的模型）
  final bool isFallback;
  final String provider;
  final String model;

  ModelSpec copy() => ModelSpec(
        contextWindow: contextWindow,
        maxInputTokens: maxInputTokens,
        maxOutputTokens: maxOutputTokens,
        maxOutputDefault: maxOutputDefault,
        maxOutputDocumented: maxOutputDocumented,
        temperatureMin: temperatureMin,
        temperatureMax: temperatureMax,
        temperatureDefault: temperatureDefault,
        temperatureSupported: temperatureSupported,
        thinking: thinking,
        vision: vision,
        isFallback: isFallback,
        provider: provider,
        model: model,
      );
}

/// 便捷构造（对照基准 python 字典字段）
ModelSpec _spec(
  int contextWindow,
  int maxInputTokens,
  int maxOutputTokens,
  int maxOutputDefault, {
  bool maxOutputDocumented = true,
  (double, double, double) temperature = const (0.0, 2.0, 1.0),
  bool temperatureSupported = true,
  String thinking = 'none',
  bool vision = false,
}) =>
    ModelSpec(
      contextWindow: contextWindow,
      maxInputTokens: maxInputTokens,
      maxOutputTokens: maxOutputTokens,
      maxOutputDefault: maxOutputDefault,
      maxOutputDocumented: maxOutputDocumented,
      temperatureMin: temperature.$1,
      temperatureMax: temperature.$2,
      temperatureDefault: temperature.$3,
      temperatureSupported: temperatureSupported,
      thinking: ThinkingSupport.parse(thinking),
      vision: vision,
    );

/// 模型规格表：{ provider: { modelId: spec } }（数值 1:1 移植基准项目）
final Map<String, Map<String, ModelSpec>> kModelSpecs = {
  'dashscope': {
    'qwen3.8-flash': _spec(1000000, 991808, 131072, 131072, thinking: 'toggle', vision: true),
    'qwen-turbo': _spec(131072, 98304, 16384, 16384, thinking: 'toggle'),
    'qwen-long': _spec(10000000, 10000000, 8192, 8192),
  },
  'deepseek': {
    'deepseek-flash': _spec(1048576, 1048576, 393216, 65536, thinking: 'toggle'),
    'deepseek-v4-pro': _spec(1048576, 1048576, 393216, 65536, thinking: 'toggle'),
  },
  'kimi': {
    'k3': _spec(1048576, 1048576, 1048576, 8192,
        maxOutputDocumented: false, thinking: 'toggle', vision: true),
    'k3-256k': _spec(262144, 262144, 262144, 8192,
        maxOutputDocumented: false, thinking: 'toggle', vision: true),
    'kimi-for-coding': _spec(262144, 262144, 262144, 8192,
        maxOutputDocumented: false, thinking: 'forced_on', vision: true),
    'kimi-for-coding-highspeed': _spec(262144, 262144, 262144, 8192,
        maxOutputDocumented: false, thinking: 'forced_on', vision: true),
  },
  'mimo': {
    'mimo-v2.6-pro': _spec(1048576, 1048576, 131072, 131072, thinking: 'toggle', vision: true),
    'mimo-v2.6-flash': _spec(1048576, 1048576, 131072, 131072, thinking: 'toggle', vision: true),
    'mimo-v2.6-pro-ultraspeed':
        _spec(1048576, 1048576, 131072, 131072, thinking: 'toggle', vision: true),
  },
  'stepfun': {
    'step-5-preview': _spec(1048576, 1048576, 65536, 65536,
        temperature: (0.0, 2.0, 0.5), thinking: 'toggle', vision: true),
    'step-3.7-flash': _spec(262144, 262144, 262144, 8192,
        maxOutputDocumented: false, temperature: (0.0, 2.0, 0.5), thinking: 'toggle', vision: true),
    'step-3.5-flash': _spec(262144, 262144, 262144, 8192,
        maxOutputDocumented: false, temperature: (0.0, 2.0, 0.5), thinking: 'toggle'),
    'step-3.5-flash-2603': _spec(262144, 262144, 262144, 8192,
        maxOutputDocumented: false, temperature: (0.0, 2.0, 0.5), thinking: 'toggle'),
  },
  'minimax': {
    'MiniMax-M3.1-Flash-Preview': _spec(1000000, 1000000, 1000000, 8192,
        maxOutputDocumented: false, thinking: 'forced_on', vision: true),
    'MiniMax-M3': _spec(1000000, 1000000, 1000000, 8192,
        maxOutputDocumented: false, thinking: 'toggle', vision: true),
    'MiniMax-M2.7': _spec(204800, 204800, 204800, 8192,
        maxOutputDocumented: false, thinking: 'forced_on'),
    'MiniMax-M2.7-highspeed': _spec(204800, 204800, 204800, 8192,
        maxOutputDocumented: false, thinking: 'forced_on'),
    'MiniMax-M2.5': _spec(204800, 204800, 204800, 8192,
        maxOutputDocumented: false, thinking: 'forced_on'),
    'MiniMax-M2.5-highspeed': _spec(204800, 204800, 204800, 8192,
        maxOutputDocumented: false, thinking: 'forced_on'),
    'MiniMax-M2.1': _spec(204800, 204800, 204800, 8192,
        maxOutputDocumented: false, thinking: 'forced_on'),
    'MiniMax-M2.1-highspeed': _spec(204800, 204800, 204800, 8192,
        maxOutputDocumented: false, thinking: 'forced_on'),
    'MiniMax-M2':
        _spec(204800, 204800, 204800, 8192, maxOutputDocumented: false, thinking: 'forced_on'),
  },
  'zhipu': {
    'glm-5.3': _spec(1048576, 1048576, 131072, 65536, thinking: 'forced_on'),
    'glm-5.3-flash': _spec(1048576, 1048576, 131072, 65536, thinking: 'forced_on', vision: true),
    'glm-5.3-flashx': _spec(1048576, 1048576, 131072, 65536, thinking: 'forced_on', vision: true),
    'glm-5.2': _spec(1048576, 1048576, 131072, 65536, thinking: 'toggle'),
    'glm-5.1': _spec(204800, 204800, 131072, 65536, thinking: 'toggle'),
    'glm-5': _spec(204800, 204800, 131072, 65536, thinking: 'toggle'),
    'glm-5-turbo': _spec(204800, 204800, 131072, 65536, thinking: 'toggle'),
    'glm-4.7': _spec(204800, 204800, 131072, 65536, thinking: 'forced_on'),
    'glm-4.6': _spec(204800, 204800, 131072, 65536, thinking: 'toggle'),
    'glm-4.5-air': _spec(131072, 131072, 98304, 65536, thinking: 'toggle'),
    'glm-4-long': _spec(1048576, 1048576, 4096, 4096),
    'glm-5v-turbo': _spec(204800, 204800, 131072, 65536, thinking: 'toggle', vision: true),
    'glm-4.6v': _spec(131072, 131072, 32768, 16384, thinking: 'toggle', vision: true),
    'glm-4.6v-flash': _spec(131072, 131072, 32768, 16384, thinking: 'toggle', vision: true),
    'glm-4v-flash': _spec(16384, 16384, 1024, 1024, vision: true),
  },
};

/// 服务商级别的保守回退规格（用于在线拉取到、但未内置适配的模型）。
/// 豆包 / 文心一言暂无逐模型官方值收录，整家走回退。
final Map<String, ModelSpec> kFallbackSpecs = {
  'doubao': _spec(262144, 262144, 32768, 16384, thinking: 'toggle', vision: true),
  'dashscope': _spec(131072, 131072, 16384, 16384, thinking: 'toggle'),
  'qianfan': _spec(131072, 131072, 16384, 8192,
      maxOutputDocumented: false, temperature: (0.0, 2.0, 0.95)),
  'deepseek': _spec(1048576, 1048576, 393216, 65536, thinking: 'toggle'),
  'kimi': _spec(262144, 262144, 262144, 8192, maxOutputDocumented: false, thinking: 'toggle'),
  'mimo': _spec(1048576, 1048576, 131072, 131072, thinking: 'toggle', vision: true),
  'stepfun': _spec(262144, 262144, 262144, 8192,
      maxOutputDocumented: false, temperature: (0.0, 2.0, 0.5), thinking: 'toggle'),
  'minimax': _spec(204800, 204800, 204800, 8192,
      maxOutputDocumented: false, thinking: 'toggle'),
  'zhipu': _spec(204800, 204800, 131072, 65536, thinking: 'toggle'),
};

/// 通用回退
final ModelSpec kDefaultFallbackSpec = _spec(128000, 128000, 16384, 16384);

/// 获取模型规格；未内置的模型回退到服务商保守规格，并标注 isFallback=true
ModelSpec getModelSpec(String provider, String model) {
  final providerSpecs = kModelSpecs[provider];
  final hit = providerSpecs?[model];
  final base = hit ?? kFallbackSpecs[provider] ?? kDefaultFallbackSpec;
  final spec = base.copy();
  return ModelSpec(
    contextWindow: spec.contextWindow,
    maxInputTokens: spec.maxInputTokens,
    maxOutputTokens: spec.maxOutputTokens,
    maxOutputDefault: spec.maxOutputDefault,
    maxOutputDocumented: spec.maxOutputDocumented,
    temperatureMin: spec.temperatureMin,
    temperatureMax: spec.temperatureMax,
    temperatureDefault: spec.temperatureDefault,
    temperatureSupported: spec.temperatureSupported,
    thinking: spec.thinking,
    vision: spec.vision,
    isFallback: hit == null,
    provider: provider,
    model: model,
  );
}

// ---------------------------------------------------------------------------
// 思考模式（存储稳定码 + UI 文案）
// ---------------------------------------------------------------------------
const String kThinkingModeDefault = 'default';
const String kThinkingModeOn = 'on';
const String kThinkingModeOff = 'off';

const String kThinkingLabelDefault = '跟随模型默认配置';
const String kThinkingLabelOn = '开启';
const String kThinkingLabelOff = '关闭';

const Map<String, String> kThinkingModeLabels = {
  kThinkingModeDefault: kThinkingLabelDefault,
  kThinkingModeOn: kThinkingLabelOn,
  kThinkingModeOff: kThinkingLabelOff,
};

/// 思考模式 -> 请求体附加参数（仅收录官方文档明确的提供方；
/// 官方未提供控制参数的提供方，保存配置后不附加参数）
const Map<String, Map<String, dynamic>> _thinkingOnPayload = {
  'deepseek': {'thinking': {'type': 'enabled'}},
  'zhipu': {'thinking': {'type': 'enabled'}},
  'mimo': {'thinking': {'type': 'enabled'}},
  'minimax': {'thinking': {'type': 'adaptive'}},
  // Kimi: reasoning_effort 官方默认 high；StepFun: 推理强度三档
  'kimi': {'reasoning_effort': 'high'},
  'stepfun': {'reasoning_effort': 'high'},
};

const Map<String, Map<String, dynamic>> _thinkingOffPayload = {
  'deepseek': {'thinking': {'type': 'disabled'}},
  'zhipu': {'thinking': {'type': 'disabled'}},
  'mimo': {'thinking': {'type': 'disabled'}},
  'minimax': {'thinking': {'type': 'disabled'}},
  // Kimi：关闭思考会由服务端路由到上一代模型，无独立参数；StepFun 文档未提供关闭方式
  'kimi': <String, dynamic>{},
  'stepfun': <String, dynamic>{},
};

/// 将「思考模式」取值转为请求体附加参数（无对应官方参数时返回空字典）。
/// [thinkingMode] 使用稳定码 default / on / off。
Map<String, dynamic> buildThinkingPayload(String provider, String thinkingMode) {
  if (thinkingMode == kThinkingModeOn) {
    return Map.of(_thinkingOnPayload[provider] ?? const {});
  }
  if (thinkingMode == kThinkingModeOff) {
    return Map.of(_thinkingOffPayload[provider] ?? const {});
  }
  return {};
}
