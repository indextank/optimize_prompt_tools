/// 系统设置页：常规 / 优化偏好 / 网络与代理 / 数据管理 / 关于。
library;

import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../core/models.dart';
import '../../services/export_service.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../file_saver.dart';
import '../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  /// 测试注入：替换导出/导入的文件通道（避免触发原生对话框）
  @visibleForTesting
  static FileSaver? debugFileSaver;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  FileSaver get _fileSaver => SettingsPage.debugFileSaver ?? createFileSaver();
  bool _checkingNet = false;
  String _netStatus = '';
  int _historyCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final n = await appState.storage.recordCount();
    if (mounted) setState(() => _historyCount = n);
  }

  Future<void> _update(AppSettings Function(AppSettings) fn) async {
    final err = await appState.settings.update(fn(appState.settings.settings));
    if (err != null && mounted) {
      displayInfoBar(context,
          builder: (context, close) =>
              InfoBar(title: Text(err), severity: InfoBarSeverity.error, onClose: close));
    }
  }

  Future<void> _checkNetwork() async {
    setState(() {
      _checkingNet = true;
      _netStatus = '';
    });
    var ok = 0;
    for (final svc in appState.services) {
      final key = await appState.readApiKey(svc) ?? '';
      final res = await appState.testConnection(svc, key);
      if (res.success) ok++;
    }
    if (!mounted) return;
    setState(() {
      _checkingNet = false;
      _netStatus = appState.services.isEmpty
          ? '尚未配置服务商'
          : '✓ $ok/${appState.services.length} 家可达';
    });
  }

  void _configToast(String msg, {bool ok = true}) {
    if (!mounted) return;
    displayInfoBar(context,
        builder: (context, close) => InfoBar(
            title: Text(msg),
            severity: ok ? InfoBarSeverity.success : InfoBarSeverity.error,
            onClose: close));
  }

  /// 导出配置：全部系统设置项 → JSON 文件（文件名=配置文件名+导出日期时间）
  Future<void> _exportSettingsConfig() async {
    final now = DateTime.now();
    final name = '提示词优化工具配置_${DateFormat('yyyyMMdd_HHmm').format(now)}';
    try {
      final path = await _fileSaver.save(
        suggestedName: name,
        ext: 'json',
        bytes: utf8.encode(appState.buildSettingsExportJson(now: now)),
      );
      _configToast(path == null ? '已取消导出' : '配置已导出：$path');
    } catch (e) {
      _configToast('导出失败：$e', ok: false);
    }
  }

  /// 导入配置：选择 .json 文件 → 严格校验 → 字段级覆盖写回 → 界面刷新。
  /// 任一环节失败均不写入任何数据，原配置保持不变。
  Future<void> _importSettingsConfig() async {
    const failPrefix = '导入失败：';
    PickedFile? picked;
    try {
      picked = await _fileSaver.pickFile(extensions: ['json']);
    } catch (e) {
      _configToast('$failPrefix无法打开文件选择框（$e）', ok: false);
      return;
    }
    if (picked == null) return; // 用户取消
    if (!picked.name.toLowerCase().endsWith('.json')) {
      _configToast('$failPrefix仅支持 .json 配置文件', ok: false);
      return;
    }
    final String text;
    try {
      text = utf8.decode(picked.bytes);
    } catch (_) {
      _configToast('$failPrefix文件不是有效的 UTF-8 文本', ok: false);
      return;
    }
    try {
      // 纯解析校验（settings + 预置词均通过前不写任何数据）
      final merged = appState.parseImportedSettings(text);
      final presets = appState.parseImportedPresets(text);
      await appState.settings.update(merged);
      final presetCount = await appState.importPresets(presets);
      _configToast(presetCount > 0
          ? '配置导入成功，已应用（含编程预置词 $presetCount 条）'
          : '配置导入成功，已应用');
    } on FormatException catch (e) {
      _configToast('$failPrefix${e.message}', ok: false);
    } catch (e) {
      _configToast('$failPrefix$e', ok: false);
    }
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('清空历史记录'),
        content: Text('将删除全部 $_historyCount 条历史记录，该操作不可恢复。确定继续吗？'),
        actions: [
          Button(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) {
      await appState.clearHistory();
      await _loadStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState.settings,
      builder: (context, _) {
        final s = appState.settings.settings;
        return ScaffoldPage.withPadding(
          padding: const EdgeInsets.fromLTRB(26, 18, 26, 14),
          content: ListView(children: [
            const Text('系统设置',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('外观、优化偏好、网络与数据管理；配置变更即时生效并本地保存',
                style: TextStyle(fontSize: 12.5, color: AppTokens.text3)),
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, c) {
              final twoCol = c.maxWidth > 980;
              final groups = [
                _generalGroup(s),
                _optimizeGroup(s),
                _networkGroup(s),
                _dataGroup(s),
              ];
              if (!twoCol) {
                return Column(children: [
                  for (final g in groups) Padding(
                      padding: const EdgeInsets.only(bottom: 12), child: g),
                ]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: [
                  groups[0], const SizedBox(height: 12), groups[2],
                ])),
                const SizedBox(width: 12),
                Expanded(child: Column(children: [
                  groups[1], const SizedBox(height: 12), groups[3],
                ])),
              ]);
            }),
          ]),
        );
      },
    );
  }

  // ---------------------------------------------------------------- 常规
  Widget _generalGroup(AppSettings s) => _group('🖥 常规', [
        _row('主题模式', '深色模式随系统或手动切换',
            ComboBox<AppThemeMode>(
              value: s.themeMode,
              items: const [
                ComboBoxItem(value: AppThemeMode.light, child: Text('浅色')),
                ComboBoxItem(value: AppThemeMode.dark, child: Text('深色')),
                ComboBoxItem(value: AppThemeMode.system, child: Text('跟随系统')),
              ],
              onChanged: (v) => _update((c) => c.copyWith(themeMode: v)),
            )),
        _row('界面语言', '当前版本提供简体中文',
            ComboBox<String>(
              value: s.language,
              items: const [
                ComboBoxItem(value: 'zh_CN', child: Text('简体中文')),
              ],
              onChanged: (v) => _update((c) => c.copyWith(language: v)),
            )),
        _row('开机自动启动', '最小化到系统托盘，不打扰桌面（桌面端生效）',
            ToggleSwitch(
              key: const Key('toggle-autoStart'),
              checked: s.autoStart,
              onChanged: (v) => _update((c) => c.copyWith(autoStart: v)),
            )),
        _row('全局唤起热键', '任意界面按下即唤起优化窗口（桌面端；Wayland 下自动降级）',
            Row(mainAxisSize: MainAxisSize.min, children: [
              Card(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(s.hotkey,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ])),
        _row('桌面悬浮球', '点击快速优化剪贴板文本（Android 需授予悬浮窗权限）',
            ToggleSwitch(
              key: const Key('toggle-floatingBall'),
              checked: s.floatingBall,
              onChanged: (v) => _update((c) => c.copyWith(floatingBall: v)),
            )),
      ]);

  // ---------------------------------------------------------------- 优化偏好
  Widget _optimizeGroup(AppSettings s) => _group('✨ 优化偏好', [
        _row('默认优化模式', '快速 / 深度 / 提问式',
            ComboBox<OptimizeMode>(
              value: s.defaultMode,
              items: [
                for (final m in OptimizeMode.values)
                  ComboBoxItem(value: m, child: Text(m.label)),
              ],
              onChanged: (v) => _update((c) => c.copyWith(defaultMode: v)),
            )),
        _row('默认场景模板', '工作台初始场景',
            ComboBox<String>(
              value: appState.scenes.any((e) => e.id == s.defaultScene)
                  ? s.defaultScene
                  : kDefaultScene.id,
              items: [
                for (final sc in appState.scenes)
                  ComboBoxItem(value: sc.id, child: Text(sc.name)),
              ],
              onChanged: (v) => _update((c) => c.copyWith(defaultScene: v)),
            )),
        _row('优化结果语言', '跟随输入或固定中英文',
            ComboBox<String>(
              value: s.resultLanguage,
              items: const [
                ComboBoxItem(value: 'follow', child: Text('跟随输入语言')),
                ComboBoxItem(value: 'zh', child: Text('固定中文')),
                ComboBoxItem(value: 'en', child: Text('固定英文')),
              ],
              onChanged: (v) => _update((c) => c.copyWith(resultLanguage: v)),
            )),
        _row('优化完成后自动复制', '结果直接写入剪贴板',
            ToggleSwitch(
              key: const Key('toggle-autoCopy'),
              checked: s.autoCopy,
              onChanged: (v) => _update((c) => c.copyWith(autoCopy: v)),
            )),
        _row('历史记录保留天数', '超期自动清理，0 为永久保留',
            SizedBox(
              width: 140,
              child: NumberBox<int>(
                value: s.retentionDays,
                min: 0,
                max: 3650,
                onChanged: (v) =>
                    _update((c) => c.copyWith(retentionDays: v ?? c.retentionDays)),
              ),
            )),
      ]);

  // ---------------------------------------------------------------- 网络与代理
  Widget _networkGroup(AppSettings s) => _group('🌐 网络与代理', [
        _row('代理模式', '国内模型 API 建议直连',
            ComboBox<ProxyMode>(
              value: s.proxyMode,
              items: const [
                ComboBoxItem(value: ProxyMode.system, child: Text('跟随系统')),
                ComboBoxItem(value: ProxyMode.direct, child: Text('直连')),
                ComboBoxItem(value: ProxyMode.custom, child: Text('自定义')),
              ],
              onChanged: (v) => _update((c) => c.copyWith(proxyMode: v)),
            )),
        if (s.proxyMode == ProxyMode.custom)
          _row(
              '自定义代理地址',
              'http:// 、https:// 或 socks5:// 开头',
              SizedBox(
                width: 220,
                child: TextBox(
                  key: const Key('proxy-url-field'),
                  placeholder: 'http://127.0.0.1:7890',
                  controller: TextEditingController(text: s.proxyUrl),
                  onChanged: (t) => _update((c) => c.copyWith(proxyUrl: t)),
                ),
              )),
        _row('请求超时时间', '5-300 秒',
            SizedBox(
              width: 140,
              child: NumberBox<int>(
                value: s.timeoutSecs,
                min: 5,
                max: 300,
                onChanged: (v) =>
                    _update((c) => c.copyWith(timeoutSecs: v ?? c.timeoutSecs)),
              ),
            )),
        _row(
            '连通性检测',
            '批量检测已配置服务商可达性',
            Row(mainAxisSize: MainAxisSize.min, children: [
              Button(
                onPressed: _checkingNet ? null : _checkNetwork,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_checkingNet)
                    const SizedBox(
                        width: 12, height: 12, child: ProgressRing(strokeWidth: 2)),
                  const SizedBox(width: 4),
                  const Text('📶 立即检测'),
                ]),
              ),
              if (_netStatus.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(_netStatus,
                    style: const TextStyle(fontSize: 11.5, color: AppTokens.success)),
              ],
            ])),
      ]);

  // ---------------------------------------------------------------- 数据管理
  Widget _dataGroup(AppSettings s) => _group('🗄 数据管理', [
        _row(
            '配置备份与迁移',
            '导出不含 API 密钥，密钥需重新录入',
            Row(mainAxisSize: MainAxisSize.min, children: [
              Button(
                onPressed: _exportSettingsConfig,
                child: const Text('⬆ 导出配置'),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: _importSettingsConfig,
                child: const Text('⬇ 导入配置'),
              ),
            ])),
        _row('历史记录', '共 $_historyCount 条',
            Button(onPressed: _clearHistory, child: const Text('🗑 清空历史'))),
        _row('恢复默认设置', '重置全部偏好选项（不影响模型配置）',
            Button(
              onPressed: () => _update((c) => const AppSettings()),
              child: const Text('恢复默认'),
            )),
      ]);

  // ---------------------------------------------------------------- 布局工具
  Widget _group(String title, List<Widget> rows) => Card(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(title,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          const Divider(),
          ...rows,
        ]),
      );

  Widget _row(String label, String desc, Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 11, color: AppTokens.text3)),
            ]),
          ),
          const SizedBox(width: 12),
          child,
        ]),
      );
}
