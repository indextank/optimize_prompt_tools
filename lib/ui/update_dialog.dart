/// 更新对话框：新版本信息展示 + 下载进度 + 安装反馈。
///
/// 数据来自 [UpdateCheckResult]（UpdateService 产出），执行交给
/// [UpdateInstaller]（平台实现：桌面外挂脚本替换重启 / Android 系统安装器）。
library;

import 'package:fluent_ui/fluent_ui.dart';

import '../services/update_installer.dart';
import '../services/update_service.dart';
import 'theme.dart';

/// 展示更新流程对话框（模态）。
Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateCheckResult result,
  required UpdateService service,
  UpdateInstaller? installer,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => UpdateDialog(
      result: result,
      service: service,
      installer: installer ?? createInstaller(),
    ),
  );
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.result,
    required this.service,
    required this.installer,
  });

  final UpdateCheckResult result;
  final UpdateService service;
  final UpdateInstaller installer;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { idle, downloading, installing, error }

class _UpdateDialogState extends State<UpdateDialog> {
  _Phase _phase = _Phase.idle;
  double? _fraction;
  String? _error;

  bool get _hasAsset =>
      widget.result.assetUrl != null && widget.result.assetName != null;

  Future<void> _start() async {
    if (!_hasAsset) {
      // 当前平台暂无安装包 → 跳转 Release 页面手动下载
      await widget.installer.openReleasePage(widget.result.releaseUrl);
      return;
    }
    setState(() {
      _phase = _Phase.downloading;
      _fraction = null;
      _error = null;
    });
    try {
      final sha = await widget.service.fetchExpectedSha(widget.result);
      await widget.installer.downloadAndInstall(
        assetUrl: widget.result.assetUrl!,
        assetName: widget.result.assetName!,
        expectedSha256: sha,
        onProgress: (f) {
          if (mounted) setState(() => _fraction = f);
        },
      );
      // 桌面端：安装器内部完成替换并重启（通常到不了这里）；
      // Android：系统安装器已拉起。
      if (mounted) setState(() => _phase = _Phase.installing);
    } on UpdateException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = '更新失败：$e';
        });
      }
    }
  }

  String _sizeText() {
    final size = widget.result.assetSize;
    if (size <= 0) return '';
    return '（${(size / 1024 / 1024).toStringAsFixed(1)} MB）';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final r = widget.result;
    final notes = r.releaseNotes.isEmpty ? '（本次发布未提供更新说明）' : r.releaseNotes;

    return ContentDialog(
      title: Text('发现新版本 v${r.latestVersion}'),
      constraints: const BoxConstraints(maxWidth: 520),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('当前版本已过时，升级后可获得最新功能与修复。',
            style: TextStyle(fontSize: 12.5, color: theme.resources.controlStrokeColorDefault)),
        const SizedBox(height: AppTokens.gapM),
        // 更新说明（可滚动，超长 Release 不撑爆对话框）
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(AppTokens.gapM),
          decoration: BoxDecoration(
            color: theme.resources.cardBackgroundFillColorDefault,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.resources.controlStrokeColorDefault),
          ),
          child: SingleChildScrollView(child: Text(notes, style: const TextStyle(fontSize: 12.5, height: 1.6))),
        ),
        if (_hasAsset) ...[
          const SizedBox(height: AppTokens.gapM),
          Text('安装包：${r.assetName} ${_sizeText()}',
              style: TextStyle(fontSize: 11.5, color: theme.resources.controlStrokeColorDefault),
              overflow: TextOverflow.ellipsis),
        ],
        // ---------------- 阶段反馈区 ----------------
        if (_phase == _Phase.downloading) ...[
          const SizedBox(height: AppTokens.gapM),
          ProgressBar(value: _fraction),
          const SizedBox(height: AppTokens.gapXs),
          Text(
            _fraction == null
                ? '正在下载安装包…'
                : '正在下载安装包… ${(_fraction! * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 11.5, color: theme.resources.controlStrokeColorDefault),
          ),
        ] else if (_phase == _Phase.installing) ...[
          const SizedBox(height: AppTokens.gapM),
          const Row(children: [
            SizedBox(width: 16, height: 16, child: ProgressRing()),
            SizedBox(width: AppTokens.gapS),
            Expanded(child: Text('已调起系统安装器，请按提示完成升级', style: TextStyle(fontSize: 12.5))),
          ]),
        ] else if (_phase == _Phase.error) ...[
          const SizedBox(height: AppTokens.gapM),
          Text(_error ?? '更新失败', style: TextStyle(fontSize: 12.5, color: AppTokens.danger)),
        ],
      ]),
      actions: _buildActions(context),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (_phase) {
      case _Phase.idle:
        return [
          Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后再说'),
          ),
          if (_hasAsset)
            FilledButton(
              onPressed: _start,
              child: const Text('立即更新'),
            )
          else
            FilledButton(
              onPressed: _start, // 跳转 Release 页面
              child: const Text('打开下载页面'),
            ),
        ];
      case _Phase.downloading:
        return [
          Text('下载中，请保持网络连接…',
              style: const TextStyle(fontSize: 11.5, color: AppTokens.text3)),
        ];
      case _Phase.installing:
        return [
          Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ];
      case _Phase.error:
        return [
          Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _start, // 重试
            child: const Text('重试'),
          ),
          Button(
            onPressed: () => widget.installer.openReleasePage(widget.result.releaseUrl),
            child: const Text('手动下载'),
          ),
        ];
    }
  }
}
