# 跨平台提示词优化工具 · 项目实施文档

> 版本：v1.0 ｜ 日期：2026-10-06 ｜ 状态：待评审
> 对标产品：Trae IDE 提示词优化功能 ｜ 设计基准：EBook Master Pro「设置 - AI服务」模块

## 文档索引

| 章节 | 文件 | 内容 |
|---|---|---|
| 01 | [项目概述与对标分析](./01-项目概述与对标分析.md) | 项目定位、基准项目 AI 服务模块能力拆解、Trae 对标指标 |
| 02 | [跨平台兼容性方案](./02-跨平台兼容性方案.md) | Windows / Linux / Android 技术选型、打包、权限、兼容性测试标准 |
| 03 | [核心功能模块设计](./03-核心功能模块设计.md) | 全流程逻辑、优化引擎、九家大模型接入、并行切换机制、界面设计 |
| 04 | [项目实施 Roadmap](./04-项目实施Roadmap.md) | 五阶段时间节点、交付物、里程碑、风险应对 |
| 05 | [质量保障与测试方案](./05-质量保障与测试方案.md) | 功能 / 兼容性 / 性能 / 安全测试用例与验收标准 |
| - | [测试报告](./测试报告.md) | **169 项测试 100% 通过 + 静态分析零告警**（含逐文件明细与多维验证覆盖） |

## 界面设计稿（高保真截图）

| 界面 | 文件 | 尺寸 |
|---|---|---|
| 主操作界面（提示词输入 / 优化结果展示） | [ui-main-workbench.png](./images/ui-main-workbench.png) | 1280×800 |
| 多AI模型配置界面（含添加服务弹窗） | [ui-model-config.png](./images/ui-model-config.png) | 1440×1060 |
| 二次复查编辑界面 | [ui-review-edit.png](./images/ui-review-edit.png) | 1440×900 |
| 系统设置界面 | [ui-settings.png](./images/ui-settings.png) | 1280×800 |
| Android 端主界面（移动适配） | [ui-main-android.png](./images/ui-main-android.png) | 560×960 |

## 设计基准参考截图（EBook Master Pro 真实界面）

| 界面 | 文件 |
|---|---|
| AI 服务设置页（服务卡片列表） | [ref-ai-service-page.png](./images/reference/ref-ai-service-page.png) |
| 添加AI服务弹窗（字段联动） | [ref-ai-service-dialog.png](./images/reference/ref-ai-service-dialog.png) |
| 弹窗参数区（模型规格联动） | [ref-ai-dialog-params.png](./images/reference/ref-ai-dialog-params.png) |

## 快速摘要

- **产品形态**：Windows / Linux / Android 三端独立的提示词优化工具，输入原始想法 → AI 一键优化为结构化提示词 → 复查编辑 → 一键复制/导出。
- **技术选型**：Flutter 单代码库（fluent_ui 桌面 Fluent 风格 + Material Android 自适应），详见 [02](./02-跨平台兼容性方案.md)。
- **模型接入**：统一 OpenAI 兼容适配层，内置豆包、通义千问、文心一言、智谱、Kimi、DeepSeek、阶跃 StepFun、小米 MiMo、MiniMax 九家国内主流服务商，支持多模型并行对比，详见 [03](./03-核心功能模块设计.md)。
- **周期**：9 周（M0 需求原型 → M4 打包发布），详见 [04](./04-项目实施Roadmap.md)。
