/// 更新安装器（条件导入入口）：
///   IO 平台（Linux/Windows/Android）→ [UpdateInstaller]
///   Web → 浏览器打开 Release 页面（无法原地升级）
library;

import 'update_installer_stub.dart'
    if (dart.library.io) 'update_installer_io.dart' as impl;

export 'update_installer_stub.dart'
    if (dart.library.io) 'update_installer_io.dart';

/// 平台安装器抽象（供 UI 层依赖注入与测试替换）。
abstract class UpdateInstaller {
  /// 是否支持当前平台的自动下载安装
  bool get supportsAutoInstall;

  /// 下载并安装 [assetUrl]（文件名 [assetName]）。
  ///
  /// [onProgress]：0.0~1.0 下载进度回调。
  /// [expectedSha256]：期望哈希（可空；不匹配时抛 [Exception] 且不安装）。
  /// 桌面端：函数返回前应用已退出（安装由外挂脚本完成后重启新版本）；
  /// Android：返回时系统安装器已拉起。
  Future<void> downloadAndInstall({
    required String assetUrl,
    required String assetName,
    void Function(double fraction)? onProgress,
    String? expectedSha256,
  });

  /// 打开 Release 页面（手动下载兜底）
  Future<void> openReleasePage(String url);
}

/// 测试注入点：替换默认平台安装器构造
UpdateInstaller Function()? debugInstallerOverride;

/// 当前平台安装器实例。
UpdateInstaller createInstaller() =>
    debugInstallerOverride?.call() ?? impl.PlatformInstaller();
