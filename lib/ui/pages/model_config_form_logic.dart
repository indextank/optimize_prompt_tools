/// 添加/编辑 AI 服务弹窗的联动逻辑（纯逻辑，独立于 Widget 便于单测）。
///
/// 1:1 对齐基准项目 ai_service_dialog.py 的交互规则：
/// - 选服务商 → 地址选项联动（默认选中 defaultUrl）
/// - 选模型 → 五项参数自动填入官方规格值（applyModelSpecs）
/// - 编辑模式：先应用规格默认值，再用已存参数覆盖（顺序不可颠倒）
/// - 思考模式可选项按规格收敛：forcedOn 无「关闭」；none 固定「跟随」并禁用
/// - 非多模态模型固定「不支持」并禁用
library;

import '../../core/constants.dart';
import '../../core/model_specs.dart';
import '../../core/models.dart';

/// 弹窗表单状态（与控件一一对应）
class ServiceFormState {
  ServiceFormState({required this.provider, required this.apiUrl});

  String provider;
  String apiUrl;
  String apiKey = '';
  String model = '';
  double temperature = 1.0;
  int maxInputTokens = 128000;
  int maxOutputTokens = 16384;
  String thinkingMode = kThinkingModeDefault;
  bool imageInput = false;

  /// 当前模型规格
  ModelSpec get spec => getModelSpec(provider, model);

  /// 思考模式下拉可选项（按规格收敛）
  List<String> get thinkingOptions => switch (spec.thinking) {
        ThinkingSupport.none => const [kThinkingModeDefault],
        ThinkingSupport.forcedOn => const [kThinkingModeDefault, kThinkingModeOn],
        ThinkingSupport.toggle =>
          const [kThinkingModeDefault, kThinkingModeOn, kThinkingModeOff],
      };

  /// 思考模式控件是否可用
  bool get thinkingEnabled => spec.thinking != ThinkingSupport.none;

  /// 图片输入控件是否可用
  bool get visionEnabled => spec.vision;

  /// 切换服务商：地址联动到该家默认地址，模型联动到默认模型并应用规格
  void onProviderChanged(String next) {
    provider = next;
    apiUrl = getProviderConfig(next)?.defaultUrl ?? '';
    model = getProviderConfig(next)?.defaultModel ?? '';
    applyModelSpecs();
  }

  /// 切换模型：按官方规格自动填充五项参数
  void onModelChanged(String next) {
    model = next;
    applyModelSpecs();
  }

  /// 规格应用（基准 `_apply_model_specs` 的移植）
  void applyModelSpecs() {
    final s = spec;
    temperature = s.temperatureDefault;
    maxInputTokens = s.maxInputTokens;
    maxOutputTokens = s.maxOutputDefault;
    // 思考模式：none 固定 default；forcedOn 若当前为 off 则拉回 default
    if (s.thinking == ThinkingSupport.none) {
      thinkingMode = kThinkingModeDefault;
    } else if (s.thinking == ThinkingSupport.forcedOn && thinkingMode == kThinkingModeOff) {
      thinkingMode = kThinkingModeDefault;
    }
    // 图片输入：非多模态固定不支持
    if (!s.vision) imageInput = false;
  }

  /// 编辑模式回读（基准 `_restore_saved_params`：必须在 applyModelSpecs 之后调用）
  void restoreFrom(ServiceConfig saved, {String? apiKey}) {
    provider = saved.provider;
    apiUrl = saved.apiUrl;
    model = saved.model;
    applyModelSpecs(); // 先按模型加载默认与收敛规则
    // 再用已存参数覆盖
    temperature = saved.temperature;
    maxInputTokens = saved.maxInputTokens;
    maxOutputTokens = saved.maxOutputTokens;
    thinkingMode = thinkingOptions.contains(saved.thinkingMode)
        ? saved.thinkingMode
        : kThinkingModeDefault;
    imageInput = spec.vision ? saved.imageInput : false;
    if (apiKey != null) this.apiKey = apiKey;
  }

  /// 数值字段校验；返回错误文案（null = 合法）
  String? validate() {
    final cfg = getProviderConfig(provider);
    if (cfg == null) return '未知服务商';
    if (apiUrl.trim().isEmpty) return 'API 接口地址不能为空';
    if (!apiUrl.startsWith('http://') && !apiUrl.startsWith('https://')) {
      return 'API 接口地址需以 http(s):// 开头';
    }
    if (model.trim().isEmpty) return '请选择或输入模型';
    final s = spec;
    if (s.temperatureSupported &&
        (temperature < s.temperatureMin || temperature > s.temperatureMax)) {
      return 'Temperature 需在官方范围 ${s.temperatureMin}-${s.temperatureMax} 内';
    }
    if (maxInputTokens < 1 || maxInputTokens > s.contextWindow) {
      return '最大输入Token 不能超过所选模型上下文窗口 ${s.contextWindow}';
    }
    if (maxOutputTokens < 1 || maxOutputTokens > s.maxOutputTokens) {
      return '最大输出Token 不能超过所选模型生成上限 ${s.maxOutputTokens}';
    }
    return null;
  }

  /// 组装为持久化对象
  ServiceConfig toServiceConfig({String? id, bool isDefault = false, int createdAt = 0}) =>
      ServiceConfig(
        id: id ?? '',
        provider: provider,
        apiUrl: apiUrl.trim(),
        model: model.trim(),
        temperature: temperature,
        maxInputTokens: maxInputTokens,
        maxOutputTokens: maxOutputTokens,
        thinkingMode: thinkingMode,
        imageInput: imageInput,
        isDefault: isDefault,
        createdAt: createdAt,
      );
}
