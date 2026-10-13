/// Web 端存储实现（SharedPreferences → localStorage）。
/// 语义与 SQLite 实现完全一致，供浏览器构建使用。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models.dart';
import 'app_storage.dart';

class WebStorage implements AppStorage {
  WebStorage._(this._prefs);

  final SharedPreferences _prefs;

  static const _svcKey = 'services';
  static const _recKey = 'records';
  static const _tplKey = 'templates';
  static const _setPrefix = 'setting_';

  static Future<WebStorage> create() async =>
      WebStorage._(await SharedPreferences.getInstance());

  List<Map<String, dynamic>> _readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    return [
      for (final e in (jsonDecode(raw) as List))
        Map<String, dynamic>.from(e as Map)
    ];
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> list) =>
      _prefs.setString(key, jsonEncode(list));

  // ---------------- 服务配置 ----------------
  @override
  Future<List<ServiceConfig>> loadServices() async =>
      [for (final j in _readList(_svcKey)) ServiceConfig.fromJson(j)];

  @override
  Future<void> saveService(ServiceConfig service) async {
    final list = _readList(_svcKey);
    if (service.isDefault) {
      for (final j in list) {
        if (j['id'] != service.id && j['is_default'] == true) j['is_default'] = false;
      }
    }
    final idx = list.indexWhere((j) => j['id'] == service.id);
    if (idx >= 0) {
      list[idx] = service.toJson();
    } else {
      list.add(service.toJson());
    }
    await _writeList(_svcKey, list);
  }

  @override
  Future<void> deleteService(String id) async {
    final list = _readList(_svcKey)..removeWhere((j) => j['id'] == id);
    await _writeList(_svcKey, list);
  }

  // ---------------- 历史记录 ----------------
  @override
  Future<List<OptimizeRecord>> loadRecords({int limit = 200, int offset = 0}) async {
    final all = _readList(_recKey)
      ..sort((a, b) =>
          ((b['created_at'] as num?)?.toInt() ?? 0)
              .compareTo((a['created_at'] as num?)?.toInt() ?? 0));
    return [
      for (final j in all.skip(offset).take(limit)) OptimizeRecord.fromJson(j)
    ];
  }

  @override
  Future<void> saveRecord(OptimizeRecord record) async {
    final list = _readList(_recKey);
    final idx = list.indexWhere((j) => j['id'] == record.id);
    if (idx >= 0) {
      list[idx] = record.toJson();
    } else {
      list.add(record.toJson());
    }
    await _writeList(_recKey, list);
  }

  @override
  Future<void> deleteRecord(String id) async {
    final list = _readList(_recKey)..removeWhere((j) => j['id'] == id);
    await _writeList(_recKey, list);
  }

  @override
  Future<int> recordCount() async => _readList(_recKey).length;

  @override
  Future<List<OptimizeRecord>> searchRecords(
      {String keyword = '', String scene = '', String provider = ''}) async {
    final all = await loadRecords(limit: 100000);
    // 「模型」筛选：记录 providers 字段存的是服务 id，而筛选传的是 provider 类型，
    // 需反查服务表把类型映射为 id 集合再匹配（否则永远筛不出结果——历史页筛选 bug 根因）
    final providerIds = provider.isEmpty
        ? const <String>{}
        : {
            for (final s in await loadServices())
              if (s.provider == provider) s.id
          };
    return all.where((r) {
      if (scene.isNotEmpty && r.scene != scene) return false;
      if (provider.isNotEmpty &&
          !r.providers.any((id) => id == provider || providerIds.contains(id))) {
        return false;
      }
      if (keyword.isNotEmpty) {
        final k = keyword.toLowerCase();
        final inRaw = r.rawText.toLowerCase().contains(k);
        final inResult = r.latest.result.toPlainText().toLowerCase().contains(k) ||
            r.latest.result.rawText.toLowerCase().contains(k);
        if (!inRaw && !inResult) return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<int> purgeExpiredRecords(int retentionDays, {int? nowEpochSec}) async {
    if (retentionDays <= 0) return 0;
    final now = nowEpochSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cutoff = now - retentionDays * 86400;
    final list = _readList(_recKey);
    final kept = [
      for (final j in list)
        if (((j['created_at'] as num?)?.toInt() ?? 0) >= cutoff) j
    ];
    final removed = list.length - kept.length;
    if (removed > 0) await _writeList(_recKey, kept);
    return removed;
  }

  // ---------------- 场景模板 ----------------
  @override
  Future<List<SceneTemplate>> loadCustomTemplates() async =>
      [for (final j in _readList(_tplKey)) SceneTemplate.fromJson(j)];

  @override
  Future<void> saveTemplate(SceneTemplate template) async {
    final list = _readList(_tplKey);
    final idx = list.indexWhere((j) => j['id'] == template.id);
    if (idx >= 0) {
      list[idx] = template.toJson();
    } else {
      list.add(template.toJson());
    }
    await _writeList(_tplKey, list);
  }

  @override
  Future<void> deleteTemplate(String id) async {
    final list = _readList(_tplKey)..removeWhere((j) => j['id'] == id);
    await _writeList(_tplKey, list);
  }

  // ---------------- 设置项 ----------------
  @override
  Future<String?> getSetting(String key) async => _prefs.getString('$_setPrefix$key');

  @override
  Future<void> setSetting(String key, String value) =>
      _prefs.setString('$_setPrefix$key', value);

  @override
  Future<void> close() async {}
}
