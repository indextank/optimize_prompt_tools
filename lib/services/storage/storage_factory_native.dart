/// native 实现：平台配置目录下 SQLite 文件
///
/// 路径决策（用户指定）：
///   Linux   → `~/.config/prompt_optimizer/prompt_optimizer.db`
///             （XDG_CONFIG_HOME，未设置时回退 ~/.config）
///   Windows → `%APPDATA%\prompt_optimizer\prompt_optimizer.db`
///             （RoamingAppData，经 getApplicationSupportDirectory）
///   其他     → 平台默认支持目录（macOS Application Support / Android 私有目录）
///
/// 注意：path_provider 的 getApplicationSupportDirectory 在 Linux 走的是
/// XDG_DATA_HOME（~/.local/share），不满足需求，故 Linux 单独用
/// xdg_directories.configHome（~/.config）。
///
/// 一次性迁移：新路径尚无 DB 而旧路径（Documents/prompt_optimizer.db）存在时，
/// 复制旧库过去（旧文件保留作备份），保证升级后已配置的 AI 服务不丢失。
library;

import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xdg_directories/xdg_directories.dart' as xdg;

import 'app_storage.dart';
import 'sqlite_storage.dart';

const String kDbFileName = 'prompt_optimizer.db';

/// 纯函数：按平台解析 DB 绝对路径（单测覆盖 Linux/Windows 分支）。
@visibleForTesting
String resolveDbPath({
  required String platform,
  String? linuxConfigHome,
  String? supportDir,
}) {
  if (platform == 'linux') {
    assert(linuxConfigHome != null, 'linux 需要 configHome');
    return p.join(linuxConfigHome!, 'prompt_optimizer', kDbFileName);
  }
  assert(supportDir != null, '非 linux 平台需要 supportDir');
  return p.join(supportDir!, kDbFileName);
}

/// 纯函数：是否执行旧库迁移（新库不存在且旧库存在）。
@visibleForTesting
bool shouldMigrateLegacyDb({required bool newExists, required bool oldExists}) =>
    !newExists && oldExists;

Future<AppStorage> openAppStorage() async {
  final String dbPath;
  if (Platform.isLinux) {
    dbPath = resolveDbPath(
      platform: 'linux',
      linuxConfigHome: xdg.configHome.path, // ~/.config（尊重 XDG_CONFIG_HOME）
    );
  } else {
    final support = await getApplicationSupportDirectory();
    dbPath = resolveDbPath(
      platform: Platform.operatingSystem,
      supportDir: support.path,
    );
  }
  await _migrateLegacyDb(dbPath);
  return SqliteStorage.open(dbPath);
}

/// 一次性迁移：旧版 DB 位于 Documents 目录（getApplicationDocumentsDirectory）。
/// 新路径无库且旧库存在时复制过去；旧文件保留作备份。失败不阻断启动。
Future<void> _migrateLegacyDb(String newDbPath) async {
  try {
    final newDb = File(newDbPath);
    if (newDb.existsSync()) return; // 新库已存在，无需迁移
    final oldDir = await getApplicationDocumentsDirectory();
    final oldDb = File(p.join(oldDir.path, kDbFileName));
    if (!shouldMigrateLegacyDb(
        newExists: false, oldExists: oldDb.existsSync())) {
      return; // 旧库不存在
    }
    await Directory(p.dirname(newDbPath)).create(recursive: true);
    await oldDb.copy(newDbPath);
    debugPrint('已迁移旧数据库: ${oldDb.path} → $newDbPath（原文件保留）');
  } catch (e) {
    // 迁移失败不阻断启动：新库为空，旧文件仍在原处
    debugPrint('旧数据库迁移失败（忽略，启动继续）: $e');
  }
}
