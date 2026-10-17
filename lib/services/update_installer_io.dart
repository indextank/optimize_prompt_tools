/// IO 平台安装器实现（Linux / Windows / Android）。
///
/// 桌面端（Linux/Windows）：
///   下载安装包 → SHA256 校验 → 解压到临时目录 → 写外挂替换脚本（等待本进程
///   退出后备份旧版/覆盖新文件/拉起新进程/自删除）→ 退出应用。
/// Android：
///   下载 APK → SHA256 校验 → MethodChannel 拉起系统安装器（FileProvider）。
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'update_installer.dart';
import 'update_service.dart';

const MethodChannel _updaterChannel =
    MethodChannel('dev.promptoptimizer/updater');

class PlatformInstaller implements UpdateInstaller {
  PlatformInstaller({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  bool get supportsAutoInstall =>
      Platform.isLinux || Platform.isWindows || Platform.isAndroid;

  @override
  Future<void> downloadAndInstall({
    required String assetUrl,
    required String assetName,
    void Function(double fraction)? onProgress,
    String? expectedSha256,
  }) async {
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}${Platform.pathSeparator}$assetName');

    // ---------------- 下载（流式 + 进度） ----------------
    try {
      await _dio.download(
        assetUrl,
        file.path,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
        options: Options(
          headers: {'User-Agent': 'prompt-optimizer-updater'},
          receiveTimeout: const Duration(minutes: 10),
        ),
      );
    } on DioException catch (e) {
      throw UpdateException('下载失败：${e.message ?? '网络中断'}');
    }

    // ---------------- SHA256 校验（有校验值时强制通过） ----------------
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != expectedSha256.toLowerCase()) {
        await file.delete().catchError((_) => file);
        throw const UpdateException('安装包完整性校验失败，已删除下载文件，请重试');
      }
    }

    // ---------------- 分平台安装 ----------------
    if (Platform.isAndroid) {
      await _updaterChannel.invokeMethod<bool>('installApk', {'path': file.path});
      return; // 系统安装器接管，应用无需退出
    }

    if (Platform.isLinux) return _installLinux(file);
    if (Platform.isWindows) return _installWindows(file);
    throw const UpdateException('当前平台暂不支持自动安装');
  }

  // ------------------------------------------------------------------ Linux
  Future<void> _installLinux(File archive) async {
    final exe = File(Platform.resolvedExecutable);
    final appDir = exe.parent; // bundle 根（含 lib/ data/ prompt_optimizer）
    final tmp = await getTemporaryDirectory();
    final newDir =
        Directory('${tmp.path}${Platform.pathSeparator}update_new')
          ..createSync(recursive: true);

    final tar = await Process.run('tar', ['-xzf', archive.path, '-C', newDir.path]);
    if (tar.exitCode != 0) {
      throw UpdateException('解压失败：${tar.stderr}'.trim());
    }
    if (!File('${newDir.path}${Platform.pathSeparator}prompt_optimizer')
        .existsSync()) {
      throw const UpdateException('安装包结构异常：未找到可执行文件');
    }
    if (!appDir.existsSync() || !_isWritable(appDir)) {
      throw UpdateException('安装目录不可写（${appDir.path}），请以可写目录重新安装后重试');
    }

    final script = File('${tmp.path}${Platform.pathSeparator}apply_update.sh');
    final pid = pidOfSelf();
    script.writeAsStringSync('''
#!/bin/sh
# 提示词优化工具 自动更新脚本（等待旧进程退出后替换并重启）
while kill -0 $pid 2>/dev/null; do sleep 0.5; done
APP_DIR="${appDir.path}"
NEW_DIR="${newDir.path}"
if [ -e "\$APP_DIR.bak" ]; then rm -rf "\$APP_DIR.bak"; fi
if [ -d "\$APP_DIR" ]; then mv "\$APP_DIR" "\$APP_DIR.bak"; fi
mkdir -p "\$APP_DIR"
cp -a "\$NEW_DIR/." "\$APP_DIR/"
chmod +x "\$APP_DIR/prompt_optimizer"
"\$APP_DIR/prompt_optimizer" >/dev/null 2>&1 &
rm -rf "\$NEW_DIR"
rm -f "\$0"
''');
    await Process.run('chmod', ['+x', script.path]);

    await Process.start('sh', [script.path], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0); // 交棒给更新脚本
  }

  // ---------------------------------------------------------------- Windows
  Future<void> _installWindows(File archive) async {
    final exe = File(Platform.resolvedExecutable);
    final appDir = exe.parent;
    final tmp = await getTemporaryDirectory();
    final newDir =
        Directory('${tmp.path}${Platform.pathSeparator}update_new')
          ..createSync(recursive: true);

    // Windows 10+ 自带 bsdtar，可直接解 zip
    final tar = await Process.run('tar', ['-xf', archive.path, '-C', newDir.path]);
    if (tar.exitCode != 0) {
      throw UpdateException('解压失败：${tar.stderr}'.trim());
    }
    if (!File('${newDir.path}${Platform.pathSeparator}prompt_optimizer.exe')
        .existsSync()) {
      throw const UpdateException('安装包结构异常：未找到可执行文件');
    }
    if (!_isWritable(appDir)) {
      throw UpdateException('安装目录不可写（${appDir.path}），请将程序移至用户目录后重试');
    }

    final script = File('${tmp.path}${Platform.pathSeparator}apply_update.bat');
    script.writeAsStringSync(r'''
@echo off
rem 提示词优化工具 自动更新脚本（等待旧进程退出后替换并重启）
:wait
timeout /t 1 /nobreak >nul
tasklist /fi "PID eq __PID__" 2>nul | find /i "prompt_optimizer.exe" >nul
if not errorlevel 1 goto wait
set "APP_DIR=__APPDIR__"
set "NEW_DIR=__NEWDIR__"
if exist "%APP_DIR%.bak" rmdir /s /q "%APP_DIR%.bak"
if exist "%APP_DIR%" move "%APP_DIR%" "%APP_DIR%.bak" >nul
mkdir "%APP_DIR%"
xcopy /e /y "%NEW_DIR%\*" "%APP_DIR%\" >nul
start "" "%APP_DIR%\prompt_optimizer.exe"
rmdir /s /q "%NEW_DIR%"
del "%~f0"
''', flush: true);
    final content = script.readAsStringSync()
        .replaceAll('__PID__', '$pid')
        .replaceAll('__APPDIR__', appDir.path)
        .replaceAll('__NEWDIR__', newDir.path);
    script.writeAsStringSync(content, flush: true);

    await Process.start('cmd', ['/c', script.path],
        mode: ProcessStartMode.detached, runInShell: true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  // ------------------------------------------------------------------ 公共
  @override
  Future<void> openReleasePage(String url) async {
    if (Platform.isAndroid) {
      await _updaterChannel.invokeMethod<bool>('openUrl', {'url': url});
      return;
    }
    final cmd = Platform.isWindows
        ? ['start', '', url]
        : [url];
    final exe = Platform.isWindows ? 'cmd' : 'xdg-open';
    await Process.start(exe, cmd, mode: ProcessStartMode.detached);
  }

  /// 自身进程 PID
  static int pidOfSelf() => pid;

  static bool _isWritable(Directory dir) {
    try {
      final probe = File('${dir.path}${Platform.pathSeparator}.write_probe')
        ..writeAsStringSync('probe');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }
}
