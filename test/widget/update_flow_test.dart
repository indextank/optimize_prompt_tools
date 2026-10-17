/// 检查更新 Widget 测试：版本读取、已是最新/发现新版本/失败分支、
/// 下载安装流程（注入假安装器）、无资产平台兜底。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prompt_optimizer/app.dart';
import 'package:prompt_optimizer/services/update_installer.dart';
import 'package:prompt_optimizer/services/update_service.dart';
import 'package:prompt_optimizer/state/app_state.dart';
import 'package:prompt_optimizer/ui/update_dialog.dart';

import '../fakes.dart';

/// 假更新服务：固定返回（不触网）
class _FakeUpdateService extends UpdateService {
  _FakeUpdateService({this.result, this.error, this.checksum});

  final UpdateCheckResult? result;
  final Object? error;
  final String? checksum;

  @override
  Future<UpdateCheckResult?> checkLatest(String currentVersion,
      {String? platform}) async {
    if (error != null) throw error!;
    return result;
  }

  @override
  Future<String?> fetchExpectedSha(UpdateCheckResult r) async => checksum;
}

/// 假安装器（失败版）：下载阶段抛错，验证错误反馈与重试入口
class _FailingInstaller implements UpdateInstaller {
  int calls = 0;

  @override
  bool get supportsAutoInstall => true;

  @override
  Future<void> downloadAndInstall({
    required String assetUrl,
    required String assetName,
    void Function(double fraction)? onProgress,
    String? expectedSha256,
  }) async {
    calls++;
    throw const UpdateException('下载失败：网络中断');
  }

  @override
  Future<void> openReleasePage(String url) async {}
}

/// 假安装器：记录调用、立即成功
class _FakeInstaller implements UpdateInstaller {
  final List<String> openedUrls = [];
  final List<String> downloaded = [];
  String? lastSha;

  @override
  bool get supportsAutoInstall => true;

  @override
  Future<void> downloadAndInstall({
    required String assetUrl,
    required String assetName,
    void Function(double fraction)? onProgress,
    String? expectedSha256,
  }) async {
    downloaded.add(assetName);
    lastSha = expectedSha256;
    onProgress?.call(0.5);
    onProgress?.call(1.0);
  }

  @override
  Future<void> openReleasePage(String url) async => openedUrls.add(url);
}

UpdateCheckResult _result({String? assetName, String? assetUrl}) =>
    UpdateCheckResult(
      latestVersion: '9.9.9',
      releaseNotes: '修复若干问题，优化性能',
      releaseUrl: 'https://github.com/indextank/optimize_prompt_tools/releases/tag/v9.9.9',
      assetName: assetName,
      assetUrl: assetUrl,
      assetSize: 5 * 1024 * 1024,
      checksumUrl: assetUrl == null
          ? null
          : 'https://example.com/SHA256SUMS.txt',
    );

Future<void> _pumpApp(WidgetTester tester) async {
  appState = await makeTestAppState(); // 全局状态（PromptOptimizerApp 依赖）
  PackageInfo.setMockInitialValues(
    appName: 'prompt_optimizer',
    packageName: 'dev.promptoptimizer.prompt_optimizer',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const PromptOptimizerApp());
  await tester.pump(); // 版本读取 Future 完成
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    UpdateService.debugOverride = null;
    debugInstallerOverride = null;
  });

  tearDown(() {
    UpdateService.debugOverride = null;
    debugInstallerOverride = null;
  });

  group('版本展示（读自 pubspec 构建元数据）', () {
    testWidgets('展示 v<version> · Build <buildNumber> 与检查更新按钮',
        (tester) async {
      await _pumpApp(tester);
      expect(find.text('v1.0.0 · Build 1'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);
    });
  });

  group('检查更新分支', () {
    testWidgets('已是最新 → 成功 InfoBar', (tester) async {
      UpdateService.debugOverride = () => _FakeUpdateService(result: null);
      await _pumpApp(tester);
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // InfoBar 入场
      expect(find.textContaining('已是最新版本'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('发现新版本 → 弹出更新对话框（版本/说明/安装包信息）',
        (tester) async {
      UpdateService.debugOverride = () => _FakeUpdateService(
          result: _result(
              assetName: 'prompt-optimizer-linux-x64-9.9.9.tar.gz',
              assetUrl: 'https://example.com/a.tar.gz'));
      await _pumpApp(tester);
      await tester.tap(find.text('检查更新'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('发现新版本 v9.9.9'), findsOneWidget);
      expect(find.textContaining('修复若干问题'), findsOneWidget);
      expect(find.textContaining('prompt-optimizer-linux-x64-9.9.9.tar.gz'),
          findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      expect(find.text('稍后再说'), findsOneWidget);
    });

    testWidgets('检查失败 → 错误 InfoBar（含原因）', (tester) async {
      UpdateService.debugOverride = () => _FakeUpdateService(
          error: const UpdateException('网络异常（连接被拒绝）'));
      await _pumpApp(tester);
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
          find.textContaining('检查更新失败'), findsOneWidget);
      expect(find.textContaining('网络异常'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('下载安装流程（假安装器）', () {
    testWidgets('点击立即更新 → 安装器收到资产与校验值，进入安装反馈',
        (tester) async {
      final installer = _FakeInstaller();
      debugInstallerOverride = () => installer;
      UpdateService.debugOverride = () => _FakeUpdateService(
          checksum: 'a' * 64,
          result: _result(
              assetName: 'prompt-optimizer-linux-x64-9.9.9.tar.gz',
              assetUrl: 'https://example.com/a.tar.gz'));
      await _pumpApp(tester);
      await tester.tap(find.text('检查更新'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('立即更新'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(installer.downloaded,
          ['prompt-optimizer-linux-x64-9.9.9.tar.gz']);
      expect(installer.lastSha, 'a' * 64, reason: '校验值应传递给安装器');
      expect(find.textContaining('已调起系统安装器'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
    });

    testWidgets('无平台资产 → 显示打开下载页面，点击跳转 Release 页',
        (tester) async {
      final installer = _FakeInstaller();
      debugInstallerOverride = () => installer;
      UpdateService.debugOverride =
          () => _FakeUpdateService(result: _result());
      await _pumpApp(tester);
      await tester.tap(find.text('检查更新'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('打开下载页面'), findsOneWidget);
      await tester.tap(find.text('打开下载页面'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(installer.openedUrls.single, contains('releases/tag/v9.9.9'));
    });

    testWidgets('对话框直接展示：错误阶段提供重试与手动下载', (tester) async {
      final installer = _FailingInstaller();
      await tester.pumpWidget(FluentApp(
        home: UpdateDialog(
          result: _result(
              assetName: 'prompt-optimizer-linux-x64-9.9.9.tar.gz',
              assetUrl: 'https://example.com/a.tar.gz'),
          service: _FakeUpdateService(),
          installer: installer,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('立即更新'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('下载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('手动下载'), findsOneWidget);
      expect(installer.calls, 1, reason: '失败后安装器只被调用一次（未自动重试）');
      // 点击重试 → 二次调用安装器
      await tester.tap(find.text('重试'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(installer.calls, 2, reason: '重试应再次调用安装器');
    });
  });
}
