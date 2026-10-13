/// 服务商配置数据源（移植自基准项目 EBook Master Pro `app/constants.py`，
/// 并扩展豆包/火山方舟与文心一言/百度千帆两家）。
///
/// 每家配置字段与基准保持一致：
/// - `name` / `nameEn`：显示名
/// - `defaultUrl`：默认 API 地址
/// - `apiUrlOptions`：地址下拉选项（标准地址 + Coding Plan 专属地址）
/// - `codingPlanName`：Coding Plan 名称（无则 null）
/// - `models`：内置模型清单（不支持在线拉取时的兜底）
/// - `defaultModel`：默认模型
/// - `supportsModelListApi`：是否支持 GET /models 在线拉取
library;

/// API 地址选项
class ApiUrlOption {
  const ApiUrlOption({required this.label, required this.url});
  final String label;
  final String url;
}

/// 服务商配置
class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.defaultUrl,
    required this.apiUrlOptions,
    required this.models,
    required this.defaultModel,
    this.codingPlanName,
    this.supportsModelListApi = true,
    this.modelListEndpoint = '/models',
  });

  final String id;
  final String name;
  final String nameEn;
  final String defaultUrl;
  final List<ApiUrlOption> apiUrlOptions;
  final String? codingPlanName;
  final List<String> models;
  final String defaultModel;
  final bool supportsModelListApi;
  final String modelListEndpoint;
}

/// 服务商下拉顺序（对齐需求条目顺序：豆包、通义千问、文心/智谱、kimi、
/// deepseek、阶跃 stepfun、小米 MIMO、MiniMax）
const List<String> kProviderList = [
  'doubao',
  'dashscope',
  'qianfan',
  'zhipu',
  'kimi',
  'deepseek',
  'stepfun',
  'mimo',
  'minimax',
];

/// 九家国内主流大模型服务商配置表
const Map<String, ProviderConfig> kProviderConfigs = {
  'doubao': ProviderConfig(
    id: 'doubao',
    name: '豆包（火山方舟）',
    nameEn: 'Doubao (Volcano Ark)',
    defaultUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    apiUrlOptions: [
      ApiUrlOption(label: '标准API地址', url: 'https://ark.cn-beijing.volces.com/api/v3'),
    ],
    models: ['doubao-seed-1-6-250615', 'doubao-seed-1-6-flash-250715', 'doubao-1-5-pro-32k-250115'],
    defaultModel: 'doubao-seed-1-6-250615',
    supportsModelListApi: true,
  ),
  'dashscope': ProviderConfig(
    id: 'dashscope',
    name: '通义千问（阿里云百炼）',
    nameEn: 'DashScope',
    defaultUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    apiUrlOptions: [
      ApiUrlOption(label: '标准API地址', url: 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
      ApiUrlOption(label: 'Coding Plan API 地址', url: 'https://coding.dashscope.aliyuncs.com/v1'),
    ],
    codingPlanName: 'Coding Plan',
    models: ['qwen3.8-flash', 'qwen-turbo', 'qwen-long'],
    defaultModel: 'qwen3.8-flash',
    supportsModelListApi: true,
  ),
  'qianfan': ProviderConfig(
    id: 'qianfan',
    name: '文心一言（百度千帆）',
    nameEn: 'ERNIE (Baidu Qianfan)',
    defaultUrl: 'https://qianfan.baidubce.com/v2',
    apiUrlOptions: [
      ApiUrlOption(label: '标准API地址', url: 'https://qianfan.baidubce.com/v2'),
    ],
    models: ['ernie-4.5-turbo-128k', 'ernie-x1-turbo-32k', 'ernie-4.5-turbo-vl-32k'],
    defaultModel: 'ernie-4.5-turbo-128k',
    supportsModelListApi: true,
  ),
  'zhipu': ProviderConfig(
    id: 'zhipu',
    name: '智谱开放平台',
    nameEn: 'Zhipu AI',
    defaultUrl: 'https://open.bigmodel.cn/api/paas/v4',
    apiUrlOptions: [
      ApiUrlOption(label: '标准API地址', url: 'https://open.bigmodel.cn/api/paas/v4'),
      ApiUrlOption(label: 'Coding Plan API 地址（GLM Coding Plan）', url: 'https://open.bigmodel.cn/api/coding/paas/v4'),
    ],
    codingPlanName: 'GLM Coding Plan',
    models: [
      'glm-5.3', 'glm-5.3-flash', 'glm-5.3-flashx', 'glm-5.2', 'glm-5.1', 'glm-5',
      'glm-5-turbo', 'glm-4.7', 'glm-4.6', 'glm-4.5-air', 'glm-4-long',
      'glm-5v-turbo', 'glm-4.6v', 'glm-4.6v-flash', 'glm-4v-flash',
    ],
    defaultModel: 'glm-5.3',
    supportsModelListApi: false,
  ),
  'kimi': ProviderConfig(
    id: 'kimi',
    name: 'Kimi CN',
    nameEn: 'Kimi (China)',
    defaultUrl: 'https://api.kimi.com/coding/v1',
    apiUrlOptions: [
      ApiUrlOption(label: 'Coding Plan API 地址（Kimi Code）', url: 'https://api.kimi.com/coding/v1'),
      ApiUrlOption(label: '标准API地址（Kimi 开放平台）', url: 'https://api.moonshot.cn/v1'),
    ],
    codingPlanName: 'Kimi Code',
    models: ['k3', 'k3-256k', 'kimi-for-coding', 'kimi-for-coding-highspeed'],
    defaultModel: 'k3',
    supportsModelListApi: false,
  ),
  'deepseek': ProviderConfig(
    id: 'deepseek',
    name: 'DeepSeek',
    nameEn: 'DeepSeek',
    defaultUrl: 'https://api.deepseek.com',
    apiUrlOptions: [
      ApiUrlOption(label: '标准API地址', url: 'https://api.deepseek.com'),
    ],
    models: ['deepseek-flash', 'deepseek-v4-pro'],
    defaultModel: 'deepseek-flash',
    supportsModelListApi: true,
  ),
  'stepfun': ProviderConfig(
    id: 'stepfun',
    name: '阶跃 StepFun',
    nameEn: 'StepFun',
    defaultUrl: 'https://api.stepfun.com/v1',
    apiUrlOptions: [
      ApiUrlOption(label: '标准API地址', url: 'https://api.stepfun.com/v1'),
      ApiUrlOption(label: 'Coding Plan API 地址（Step Plan）', url: 'https://api.stepfun.com/step_plan/v1'),
    ],
    codingPlanName: 'Step Plan',
    models: ['step-5-preview', 'step-3.7-flash', 'step-3.5-flash', 'step-3.5-flash-2603'],
    defaultModel: 'step-3.7-flash',
    supportsModelListApi: true,
  ),
  'mimo': ProviderConfig(
    id: 'mimo',
    name: 'Xiaomi MiMo',
    nameEn: 'Xiaomi MiMo',
    defaultUrl: 'https://api.xiaomimimo.com/v1',
    apiUrlOptions: [
      ApiUrlOption(label: '标准API地址', url: 'https://api.xiaomimimo.com/v1'),
      ApiUrlOption(label: 'Coding Plan API 地址（Token Plan）', url: 'https://token-plan-cn.xiaomimimo.com/v1'),
    ],
    codingPlanName: 'Token Plan',
    models: ['mimo-v2.6-pro', 'mimo-v2.6-flash', 'mimo-v2.6-pro-ultraspeed'],
    defaultModel: 'mimo-v2.6-pro',
    supportsModelListApi: true,
  ),
  'minimax': ProviderConfig(
    id: 'minimax',
    name: 'MiniMax CN',
    nameEn: 'MiniMax (China)',
    // MiniMax 的 Token Plan（订阅 Key）与按量计费共用同一 Base URL，仅密钥类型不同
    defaultUrl: 'https://api.minimax.cn/v1',
    apiUrlOptions: [
      ApiUrlOption(label: '标准API地址', url: 'https://api.minimax.cn/v1'),
    ],
    models: [
      'MiniMax-M3.1-Flash-Preview', 'MiniMax-M3', 'MiniMax-M2.7', 'MiniMax-M2.7-highspeed',
      'MiniMax-M2.5', 'MiniMax-M2.5-highspeed', 'MiniMax-M2.1', 'MiniMax-M2.1-highspeed',
      'MiniMax-M2',
    ],
    defaultModel: 'MiniMax-M3',
    supportsModelListApi: true,
  ),
};

/// 按提供商标识获取配置；未知标识返回 null
ProviderConfig? getProviderConfig(String provider) => kProviderConfigs[provider];

/// 获取服务商地址选项列表（地址联动数据源）
List<ApiUrlOption> getProviderUrlOptions(String provider) =>
    kProviderConfigs[provider]?.apiUrlOptions ?? const [];

/// 服务商是否支持 Coding Plan
bool providerSupportsCodingPlan(String provider) =>
    kProviderConfigs[provider]?.codingPlanName != null;
