/// 历史记录查询条件：场景 / 模型 / 预置词 / 收藏 / 关键词的组合匹配。
///
/// 独立纯逻辑，供 SQLite 与 Web 存储复用，避免两端过滤规则漂移。
library;

import 'package:flutter/foundation.dart';

import '../core/models.dart';

/// 从历史记录提取实际使用过的服务商类型，供「全部模型」下拉只展示已使用项。
Set<String> usedProviderTypes(
  Iterable<OptimizeRecord> records,
  Iterable<ServiceConfig> services,
) {
  final providersById = {for (final s in services) s.id: s.provider};
  return {
    for (final record in records)
      for (final serviceId in record.providers)
        if (providersById.containsKey(serviceId)) providersById[serviceId]!,
  };
}

/// 预置词下拉框的可见场景：全部、AI 编程、Bug 修复。
bool presetFilterVisible(String scene) =>
    scene.isEmpty || scene == 'ai_coding' || scene == 'bug_fix';

@immutable
class HistoryQuery {
  const HistoryQuery({
    this.keyword = '',
    this.scene = '',
    this.provider = '',
    this.presetId = '',
    this.onlyFavorites = false,
  });

  final String keyword;
  final String scene;
  final String provider;

  /// 预置词 id；空字符串表示不筛选。
  final String presetId;
  final bool onlyFavorites;

  bool get hasPresetFilter => presetId.isNotEmpty;

  /// 隐藏场景下必须清空预置词条件，避免不可见条件继续影响结果。
  HistoryQuery normalized() =>
      presetFilterVisible(scene) ? this : copyWith(presetId: '');

  HistoryQuery copyWith({
    String? keyword,
    String? scene,
    String? provider,
    String? presetId,
    bool? onlyFavorites,
  }) =>
      HistoryQuery(
        keyword: keyword ?? this.keyword,
        scene: scene ?? this.scene,
        provider: provider ?? this.provider,
        presetId: presetId ?? this.presetId,
        onlyFavorites: onlyFavorites ?? this.onlyFavorites,
      );

  /// 单条记录匹配。providerIds 为 provider 类型对应的服务 id 集合。
  bool matches(OptimizeRecord record, {Set<String> providerIds = const {}}) {
    if (scene.isNotEmpty && record.scene != scene) return false;
    if (presetId.isNotEmpty && record.presetId != presetId) return false;
    if (onlyFavorites && !record.favorite) return false;
    if (provider.isNotEmpty &&
        !record.providers
            .any((id) => id == provider || providerIds.contains(id))) {
      return false;
    }
    if (keyword.isNotEmpty) {
      final k = keyword.toLowerCase();
      final inRaw = record.rawText.toLowerCase().contains(k);
      final inResult =
          record.latest.result.toPlainText().toLowerCase().contains(k) ||
              record.latest.result.rawText.toLowerCase().contains(k);
      if (!inRaw && !inResult) return false;
    }
    return true;
  }
}
