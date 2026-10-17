/// GitHub Release 更新检测（平台无关：网络 + 版本比较 + 校验和解析）。
///
/// 数据源：GitHub REST API `/repos/{owner}/{repo}/releases/latest`。
/// 版本比较基于语义化版本（tag 的 `v` 前缀、build 号、预发布后缀均被规范化）。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// 最新版本信息（含当前平台可用的更新资产）。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.latestVersion,
    required this.releaseNotes,
    required this.releaseUrl,
    this.assetName,
    this.assetUrl,
    this.assetSize = 0,
    this.checksumUrl,
  });

  /// 规范化后的最新版本号（无 `v` 前缀，如 `1.2.0`）
  final String latestVersion;

  /// Release 说明（Markdown 原文）
  final String releaseNotes;

  /// Release 页面地址
  final String releaseUrl;

  /// 当前平台安装包资产名（null = 该平台暂无安装包，仅能跳转手动下载）
  final String? assetName;

  /// 安装包下载地址
  final String? assetUrl;

  /// 安装包字节数（GitHub API 提供，0 = 未知）
  final int assetSize;

  /// `SHA256SUMS.txt` 资产下载地址（存在时安装包必须通过校验）
  final String? checksumUrl;
}

/// 更新流程异常（网络失败 / 接口异常 / 校验失败 / 无发布版本）。
class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// GitHub Release 更新检测服务。
class UpdateService {
  UpdateService({
    Dio? dio,
    this.owner = 'indextank',
    this.repo = 'optimize_prompt_tools',
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ));

  final Dio _dio;
  final String owner;
  final String repo;

  /// 测试/调试注入点：替换默认服务构造（widget 测试中返回固定结果）
  static UpdateService Function()? debugOverride;

  /// Release 总页面（无安装包资产或用户取消时的兜底入口）
  String get releasePageUrl =>
      'https://github.com/$owner/$repo/releases/latest';

  /// 当前平台标识（linux / windows / android / web / unsupported）
  static String get currentPlatform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      _ => 'unsupported',
    };
  }

  /// 检查最新版本。
  ///
  /// 返回 null 表示当前已是最新；抛 [UpdateException] 表示检查失败。
  /// [platform] 仅测试注入用，默认取当前运行平台。
  Future<UpdateCheckResult?> checkLatest(
    String currentVersion, {
    String? platform,
  }) async {
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
        options: Options(headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'prompt-optimizer-updater',
        }),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404) {
        throw const UpdateException('仓库尚未发布任何版本，请稍后再试');
      }
      if (code == 403 || code == 429) {
        throw const UpdateException('GitHub 接口限流，请稍后再试');
      }
      throw UpdateException('检查更新失败：网络异常（${e.message ?? '连接被拒绝'}）');
    }

    final data = resp.data;
    if (data == null) throw const UpdateException('检查更新失败：响应为空');

    final latest = normalizeVersion((data['tag_name'] ?? '') as String);
    if (latest.isEmpty) throw const UpdateException('检查更新失败：版本号格式异常');

    if (!isNewer(latest, currentVersion)) return null; // 已是最新

    // 选择当前平台安装包（无匹配资产 → 仅版本信息，UI 引导手动下载）
    final assets = (data['assets'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final asset = selectAsset(assets, platform ?? currentPlatform);
    String? checksumUrl;
    for (final a in assets) {
      if ((a['name'] as String? ?? '') == 'SHA256SUMS.txt') {
        checksumUrl = a['browser_download_url'] as String?;
      }
    }

    return UpdateCheckResult(
      latestVersion: latest,
      releaseNotes: (data['body'] as String? ?? '').trim(),
      releaseUrl: (data['html_url'] as String? ?? releasePageUrl),
      assetName: asset?['name'] as String?,
      assetUrl: asset?['browser_download_url'] as String?,
      assetSize: (asset?['size'] as int? ?? 0),
      checksumUrl: checksumUrl,
    );
  }

  /// 规范化版本号：去 `v/V` 前缀、去 build 号（`+` 后）、去预发布后缀（`-` 后）
  static String normalizeVersion(String raw) {
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final plus = v.indexOf('+');
    if (plus >= 0) v = v.substring(0, plus);
    final dash = v.indexOf('-');
    if (dash >= 0) v = v.substring(0, dash);
    return v;
  }

  /// 语义化版本比较：a > b → 1；a == b → 0；a < b → -1
  static int compareVersions(String a, String b) {
    final pa = normalizeVersion(a).split('.');
    final pb = normalizeVersion(b).split('.');
    for (var i = 0; i < 3; i++) {
      final na = i < pa.length ? (int.tryParse(pa[i]) ?? 0) : 0;
      final nb = i < pb.length ? (int.tryParse(pb[i]) ?? 0) : 0;
      if (na != nb) return na > nb ? 1 : -1;
    }
    return 0;
  }

  /// [latest] 是否比 [current] 更新
  static bool isNewer(String latest, String current) =>
      compareVersions(latest, current) > 0;

  /// 从 Release 资产列表选择当前平台安装包。
  ///
  /// 命名约定（与 CI/release 产物一致）：
  ///   linux   → `prompt-optimizer-linux-x64-<ver>.tar.gz`
  ///   windows → `prompt-optimizer-windows-x64-<ver>.zip`
  ///   android → `prompt-optimizer-<ver>-universal.apk`
  static Map<String, dynamic>? selectAsset(
      List<Map<String, dynamic>> assets, String platform) {
    bool match(String name) => switch (platform) {
          'linux' =>
            name.startsWith('prompt-optimizer-linux-x64-') &&
                name.endsWith('.tar.gz'),
          'windows' =>
            name.startsWith('prompt-optimizer-windows-x64-') &&
                name.endsWith('.zip'),
          'android' =>
            name.startsWith('prompt-optimizer-') &&
                name.endsWith('-universal.apk'),
          _ => false,
        };
    for (final a in assets) {
      final name = (a['name'] as String? ?? '');
      if (match(name)) return a;
    }
    return null;
  }

  /// 下载 Release 的 `SHA256SUMS.txt` 并解析 [assetName] 的期望哈希。
  ///
  /// 返回 null 表示校验文件缺失/不可用（此时跳过校验而非失败）。
  Future<String?> fetchExpectedSha(UpdateCheckResult result) async {
    final url = result.checksumUrl;
    final name = result.assetName;
    if (url == null || name == null) return null;
    try {
      final resp = await _dio.get<String>(
        url,
        options: Options(
          headers: {'User-Agent': 'prompt-optimizer-updater'},
          responseType: ResponseType.plain,
        ),
      );
      final data = resp.data;
      if (data == null) return null;
      return expectedChecksum(data, name);
    } catch (_) {
      return null; // 校验文件获取失败不阻断更新（安装包本身来自 HTTPS GitHub）
    }
  }

  /// 从 `SHA256SUMS.txt` 内容中解析 [assetName] 对应的期望哈希（小写 hex）。
  ///
  /// 行格式：`<sha256><两个空格或空格+*> 文件名`（sha256sum 默认输出）。
  static String? expectedChecksum(String sumsContent, String assetName) {
    for (final line in sumsContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(trimmed);
      if (m != null && m.group(2)!.trim() == assetName) {
        return m.group(1)!.toLowerCase();
      }
    }
    return null;
  }
}
