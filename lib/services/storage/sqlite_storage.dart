/// SQLite 存储实现（Windows / Linux / Android）。
///
/// 设计文档原定 drift，实施期改为手写 DAO 直驱 sqlite3（同等 SQLite 数据层），
/// 理由：避免 build_runner 代码生成链在多端构建中的版本脆弱性，SQL 即真相、
/// 行为可逐条单测。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../core/errors.dart';
import '../../core/models.dart';
import 'app_storage.dart';

class SqliteStorage implements AppStorage {
  SqliteStorage(this._db) {
    _migrate();
  }

  final Database _db;

  /// 打开文件库
  factory SqliteStorage.open(String path) =>
      SqliteStorage(sqlite3.open(path));

  /// 内存库（测试）
  factory SqliteStorage.inMemory() => SqliteStorage(sqlite3.openInMemory());

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS services(
        id TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS records(
        id TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        scene TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS templates(
        id TEXT PRIMARY KEY,
        json TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
  }

  Map<String, dynamic> _decode(String json) {
    try {
      return Map<String, dynamic>.from(jsonDecode(json) as Map);
    } catch (e) {
      throw StorageException('数据损坏: $e');
    }
  }

  // ---------------- 服务配置 ----------------
  @override
  Future<List<ServiceConfig>> loadServices() async {
    final rows = _db.select('SELECT json FROM services ORDER BY created_at ASC, rowid ASC');
    return [for (final r in rows) ServiceConfig.fromJson(_decode(r['json'] as String))];
  }

  @override
  Future<void> saveService(ServiceConfig service) async {
    if (service.isDefault) {
      // 保证默认唯一：读出全部 → 清标记 → 逐个回写
      final all = await loadServices();
      final stmt = _db.prepare(
          'INSERT OR REPLACE INTO services(id, json, created_at) VALUES(?,?,?)');
      try {
        for (final s in all) {
          if (s.id != service.id && s.isDefault) {
            final cleared = s.copyWith(isDefault: false);
            stmt.execute([cleared.id, jsonEncode(cleared.toJson()), cleared.createdAt]);
          }
        }
        stmt.execute([service.id, jsonEncode(service.toJson()), service.createdAt]);
      } finally {
        stmt.dispose();
      }
    } else {
      _db.execute('INSERT OR REPLACE INTO services(id, json, created_at) VALUES(?,?,?)',
          [service.id, jsonEncode(service.toJson()), service.createdAt]);
    }
  }

  @override
  Future<void> deleteService(String id) async {
    _db.execute('DELETE FROM services WHERE id=?', [id]);
  }

  // ---------------- 历史记录 ----------------
  @override
  Future<List<OptimizeRecord>> loadRecords({int limit = 200, int offset = 0}) async {
    final rows = _db.select(
        'SELECT json FROM records ORDER BY created_at DESC LIMIT ? OFFSET ?', [limit, offset]);
    return [for (final r in rows) OptimizeRecord.fromJson(_decode(r['json'] as String))];
  }

  @override
  Future<void> saveRecord(OptimizeRecord record) async {
    _db.execute('INSERT OR REPLACE INTO records(id, json, scene, created_at) VALUES(?,?,?,?)',
        [record.id, jsonEncode(record.toJson()), record.scene, record.createdAt]);
  }

  @override
  Future<void> deleteRecord(String id) async {
    _db.execute('DELETE FROM records WHERE id=?', [id]);
  }

  @override
  Future<int> recordCount() async {
    final rows = _db.select('SELECT COUNT(*) AS c FROM records');
    return (rows.first['c'] as num).toInt();
  }

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
    if (retentionDays <= 0) return 0; // 0 = 永久保留
    final now = nowEpochSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cutoff = now - retentionDays * 86400;
    final stmt = _db.prepare('DELETE FROM records WHERE created_at < ?');
    try {
      stmt.execute([cutoff]);
      return _db.updatedRows;
    } finally {
      stmt.dispose();
    }
  }

  // ---------------- 场景模板 ----------------
  @override
  Future<List<SceneTemplate>> loadCustomTemplates() async {
    final rows = _db.select('SELECT json FROM templates ORDER BY rowid ASC');
    return [for (final r in rows) SceneTemplate.fromJson(_decode(r['json'] as String))];
  }

  @override
  Future<void> saveTemplate(SceneTemplate template) async {
    _db.execute('INSERT OR REPLACE INTO templates(id, json) VALUES(?,?)',
        [template.id, jsonEncode(template.toJson())]);
  }

  @override
  Future<void> deleteTemplate(String id) async {
    _db.execute('DELETE FROM templates WHERE id=?', [id]);
  }

  // ---------------- 设置项 ----------------
  @override
  Future<String?> getSetting(String key) async {
    final rows = _db.select('SELECT value FROM settings WHERE key=?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    _db.execute('INSERT OR REPLACE INTO settings(key, value) VALUES(?,?)', [key, value]);
  }

  @override
  Future<void> close() async {
    _db.dispose();
  }

  /// 仅测试用：执行原始 SQL 注入数据
  @visibleForTesting
  void debugExecute(String sql, [List<Object?> params = const []]) =>
      _db.execute(sql, params);
}
