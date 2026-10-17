/// Web 平台安装器桩实现：无法原地升级，跳转 Release 页面手动下载。
library;

import 'package:web/web.dart' as web;

import 'update_installer.dart';

class PlatformInstaller implements UpdateInstaller {
  @override
  bool get supportsAutoInstall => false;

  @override
  Future<void> downloadAndInstall({
    required String assetUrl,
    required String assetName,
    void Function(double fraction)? onProgress,
    String? expectedSha256,
  }) async {
    // Web 端走 openReleasePage 兜底，不会到达此处
    throw UnsupportedError('Web 端不支持自动安装');
  }

  @override
  Future<void> openReleasePage(String url) async {
    web.window.open(url, '_blank');
  }
}
