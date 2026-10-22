/// 存储层抽象：服务配置 / 历史记录 / 场景模板 / 设置项。
///
/// native 端为 SQLite 实现（`sqlite_storage.dart`），web 端为本地存储实现
/// （`web_storage.dart`），由 `storage_factory.dart` 按平台条件导出。
library;

import '../../core/models.dart';

abstract class AppStorage {
  // ---- 服务配置 ----
  Future<List<ServiceConfig>> loadServices();

  /// 保存（新增或按 id 覆盖）；若 [service.isDefault] 为 true，需保证默认唯一
  Future<void> saveService(ServiceConfig service);
  Future<void> deleteService(String id);

  /// 拖动调整服务顺序（[orderedIds] 为调整后的完整 id 顺序）
  Future<void> reorderServices(List<String> orderedIds);

  // ---- 历史记录 ----
  Future<List<OptimizeRecord>> loadRecords({int limit = 200, int offset = 0});
  Future<void> saveRecord(OptimizeRecord record);
  Future<void> deleteRecord(String id);
  Future<int> recordCount();

  /// 全文搜索（匹配原文与最新版本结果文本）+ 场景/模型过滤
  Future<List<OptimizeRecord>> searchRecords({String keyword = '', String scene = '', String provider = ''});

  /// 清理超期历史；[retentionDays] 为 0 表示永久保留（不清理）；返回删除条数
  Future<int> purgeExpiredRecords(int retentionDays, {int? nowEpochSec});

  // ---- 场景模板（自定义；内置模板不落库） ----
  Future<List<SceneTemplate>> loadCustomTemplates();
  Future<void> saveTemplate(SceneTemplate template);
  Future<void> deleteTemplate(String id);

  // ---- 编程预置词（技术背景；校验：名称必填/唯一、内容 ≤300 字） ----
  Future<List<CodingPreset>> loadPresets();

  /// 新增或按 id 覆盖（编辑）；校验失败抛 [FormatException]
  Future<void> savePreset(CodingPreset preset);
  Future<void> deletePreset(String id);

  // ---- 设置项 ----
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String value);

  Future<void> close();
}
