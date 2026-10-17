/// UpdateService 单元测试：版本规范化/比较、平台资产选择、SHA256SUMS 解析、
/// GitHub Release 接口各分支（有更新/已最新/404/403/网络异常）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/services/update_service.dart';

/// 构造带固定响应的 Dio（拦截器直接短路，无真实网络）
Dio _dioReturning(Object body, {int statusCode = 200}) {
  final dio = Dio()..httpClientAdapter = _StaticAdapter(body, statusCode);
  return dio;
}

class _StaticAdapter implements HttpClientAdapter {
  _StaticAdapter(this.body, this.statusCode);
  final Object body;
  final int statusCode;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final String text = body is String ? body as String : jsonEncode(body);
    return ResponseBody.fromString(
      text,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _release({
  String tag = 'v9.9.9',
  List<Map<String, dynamic>> assets = const [],
  String body = '更新说明',
}) =>
    {
      'tag_name': tag,
      'html_url': 'https://github.com/indextank/optimize_prompt_tools/releases/tag/$tag',
      'body': body,
      'assets': assets,
    };

Map<String, dynamic> _asset(String name, {int size = 100}) => {
      'name': name,
      'browser_download_url': 'https://example.com/$name',
      'size': size,
    };

void main() {
  group('版本规范化与比较', () {
    test('normalizeVersion：去 v 前缀 / build 号 / 预发布后缀', () {
      expect(UpdateService.normalizeVersion('v1.2.3'), '1.2.3');
      expect(UpdateService.normalizeVersion('V1.2.3+45'), '1.2.3');
      expect(UpdateService.normalizeVersion('1.2.3-beta.1'), '1.2.3');
      expect(UpdateService.normalizeVersion(' v2.0.0+7-rc1 '), '2.0.0');
    });

    test('compareVersions：逐段数值比较（1.10.0 > 1.9.0）', () {
      expect(UpdateService.compareVersions('v1.10.0', '1.9.0'), 1);
      expect(UpdateService.compareVersions('1.0.0', 'v1.0.0+9'), 0);
      expect(UpdateService.compareVersions('1.0.0', '1.0.1'), -1);
      expect(UpdateService.compareVersions('2.0', '2.0.0'), 0); // 段缺失补 0
    });

    test('isNewer：仅严格大于返回 true', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('0.9.9', '1.0.0'), isFalse);
    });
  });

  group('平台资产选择（命名约定）', () {
    final assets = [
      _asset('prompt-optimizer-linux-x64-9.9.9.tar.gz'),
      _asset('prompt-optimizer-windows-x64-9.9.9.zip'),
      _asset('prompt-optimizer-9.9.9-universal.apk'),
      _asset('SHA256SUMS.txt'),
    ];

    test('linux/windows/android 各命中对应资产', () {
      expect(UpdateService.selectAsset(assets, 'linux')?['name'],
          'prompt-optimizer-linux-x64-9.9.9.tar.gz');
      expect(UpdateService.selectAsset(assets, 'windows')?['name'],
          'prompt-optimizer-windows-x64-9.9.9.zip');
      expect(UpdateService.selectAsset(assets, 'android')?['name'],
          'prompt-optimizer-9.9.9-universal.apk');
    });

    test('无匹配平台返回 null（SHA256SUMS.txt 不会被误选）', () {
      expect(UpdateService.selectAsset(assets, 'web'), isNull);
      expect(UpdateService.selectAsset([_asset('SHA256SUMS.txt')], 'linux'),
          isNull);
    });
  });

  group('SHA256SUMS 解析', () {
    test('解析标准 sha256sum 输出（含二进制标记 * 与路径前缀容错）', () {
      const sums = 'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899  prompt-optimizer-linux-x64-9.9.9.tar.gz\n'
          '1122334455667788990011223344556677889900112233445566778899001122 *prompt-optimizer-windows-x64-9.9.9.zip\n';
      expect(
          UpdateService.expectedChecksum(
              sums, 'prompt-optimizer-linux-x64-9.9.9.tar.gz'),
          'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899');
      expect(
          UpdateService.expectedChecksum(
              sums, 'prompt-optimizer-windows-x64-9.9.9.zip'),
          '1122334455667788990011223344556677889900112233445566778899001122');
    });

    test('未包含目标文件时返回 null', () {
      const sums = 'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899  other.zip\n';
      expect(UpdateService.expectedChecksum(sums, 'target.zip'), isNull);
    });
  });

  group('checkLatest 接口分支', () {
    test('有新版本：返回规范化版本与当前平台资产', () async {
      final dio = _dioReturning(_release(assets: [
        _asset('prompt-optimizer-linux-x64-9.9.9.tar.gz', size: 12345),
        _asset('SHA256SUMS.txt'),
      ]));
      final svc = UpdateService(dio: dio);
      final r = await svc.checkLatest('1.0.0', platform: 'linux');
      expect(r, isNotNull);
      expect(r!.latestVersion, '9.9.9');
      expect(r.assetName, 'prompt-optimizer-linux-x64-9.9.9.tar.gz');
      expect(r.assetUrl, 'https://example.com/prompt-optimizer-linux-x64-9.9.9.tar.gz');
      expect(r.assetSize, 12345);
      expect(r.checksumUrl, isNotNull, reason: 'SHA256SUMS.txt 应被识别为校验源');
      expect(r.releaseNotes, '更新说明');
    });

    test('已是最新：返回 null', () async {
      final dio = _dioReturning(_release(tag: 'v1.0.0'));
      final svc = UpdateService(dio: dio);
      expect(await svc.checkLatest('1.0.0', platform: 'linux'), isNull);
      expect(await svc.checkLatest('2.0.0', platform: 'linux'), isNull);
    });

    test('404：仓库尚未发布 → UpdateException', () async {
      final dio = _dioReturning({'message': 'Not Found'}, statusCode: 404);
      final svc = UpdateService(dio: dio);
      expect(() => svc.checkLatest('1.0.0'), throwsA(isA<UpdateException>()));
    });

    test('403：限流 → UpdateException 提示稍后再试', () async {
      final dio = _dioReturning({'message': 'rate limited'}, statusCode: 403);
      final svc = UpdateService(dio: dio);
      expect(
          () => svc.checkLatest('1.0.0'),
          throwsA(predicate((e) =>
              e is UpdateException && e.message.contains('限流'))));
    });

    test('无平台资产：返回版本信息但资产为 null（引导手动下载）', () async {
      final dio = _dioReturning(_release(assets: [_asset('SHA256SUMS.txt')]));
      final svc = UpdateService(dio: dio);
      final r = await svc.checkLatest('1.0.0', platform: 'linux');
      expect(r, isNotNull);
      expect(r!.assetName, isNull);
      expect(r.assetUrl, isNull);
    });

    test('tag 无 v 前缀/带 build 号均可规范化比较', () async {
      final dio = _dioReturning(_release(tag: '2.0.0+12'));
      final svc = UpdateService(dio: dio);
      final r = await svc.checkLatest('1.9.0');
      expect(r!.latestVersion, '2.0.0');
    });
  });

  group('fetchExpectedSha', () {
    test('校验文件包含目标资产 → 返回小写哈希', () async {
      const sums = 'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899  prompt-optimizer-linux-x64-9.9.9.tar.gz\n';
      final dio = _dioReturning(sums);
      final svc = UpdateService(dio: dio);
      final r = UpdateCheckResult(
        latestVersion: '9.9.9',
        releaseNotes: '',
        releaseUrl: 'https://example.com',
        assetName: 'prompt-optimizer-linux-x64-9.9.9.tar.gz',
        assetUrl: 'https://example.com/a.tar.gz',
        checksumUrl: 'https://example.com/SHA256SUMS.txt',
      );
      final sha = await svc.fetchExpectedSha(r);
      expect(sha,
          'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899');
    });

    test('无校验源 → 返回 null（跳过校验而非失败）', () async {
      final svc = UpdateService(dio: _dioReturning(''));
      const r = UpdateCheckResult(
          latestVersion: '9.9.9', releaseNotes: '', releaseUrl: 'u');
      expect(await svc.fetchExpectedSha(r), isNull);
    });
  });
}
