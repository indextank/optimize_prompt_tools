/// 应用外壳：FluentApp + NavigationView（桌面三栏式导航，窄屏自动紧凑）。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../state/app_state.dart';
import 'ui/pages/history_page.dart';
import 'ui/pages/model_config_page.dart';
import 'ui/pages/preset_page.dart';
import 'ui/pages/review_edit_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/workbench_page.dart';
import 'ui/theme.dart';
import 'ui/update_dialog.dart';

class PromptOptimizerApp extends StatelessWidget {
  const PromptOptimizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState.settings,
      builder: (context, _) {
        final mode = switch (appState.settings.settings.themeMode) {
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
          AppThemeMode.system => ThemeMode.system,
        };
        return FluentApp(
          title: '提示词优化工具',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: buildFluentTheme(Brightness.light),
          darkTheme: buildFluentTheme(Brightness.dark),
          home: const AppShell(),
        );
      },
    );
  }
}

/// 主壳：左侧自绘导航栏（对齐设计稿）+ 页面区
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  // 支持 URL 深链直达页面（如 ?page=4 打开设置），默认工作台
  int _index = _initialIndex();

  static int _initialIndex() {
    try {
      final p = Uri.base.queryParameters['page'];
      final v = int.tryParse(p ?? '');
      if (v != null && v >= 0 && v <= 5) return v;
    } catch (_) {}
    return 0;
  }

  /// 供页面切换导航（如工作台 → 复查编辑）
  void navigateTo(int index) => setState(() => _index = index);

  static const int workbench = 0;
  static const int history = 1;
  static const int modelConfig = 2;
  static const int presets = 3;
  static const int settings = 4;
  static const int reviewEdit = 5;

  static const _navItems = [
    (FluentIcons.lightning_bolt, '优化工作台'),
    (FluentIcons.history, '历史记录'),
    (FluentIcons.robot, 'AI 模型配置'),
    (FluentIcons.library, '编程预置词'),
    (FluentIcons.settings, '系统设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = FluentTheme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final compact = width < 720; // 窄屏（手机竖屏）走底部导航

    final content = Expanded(
      child: switch (_index) {
        1 => const HistoryPage(),
        2 => const ModelConfigPage(),
        3 => const PresetPage(),
        4 => const SettingsPage(),
        5 => const ReviewEditPage(),
        _ => const WorkbenchPage(),
      },
    );

    if (compact) {
      return Column(children: [
        content,
        // ---------------- 底部导航（Android 设计稿） ----------------
        Container(
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2B2B2B) : Colors.white,
            border: Border(
                top: BorderSide(
                    color: dark ? const Color(0xFF3A3A3A) : AppTokens.border)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            for (var i = 0; i < _navItems.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => navigateTo(i),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_navItems[i].$1,
                        size: 18,
                        color: _index == i ? AppTokens.accentDark : AppTokens.text3),
                    const SizedBox(height: 2),
                    Text(_navItems[i].$2.replaceAll('优化工作台', '工作台'),
                        style: TextStyle(
                            fontSize: 10,
                            color: _index == i ? AppTokens.accentDark : AppTokens.text3,
                            fontWeight:
                                _index == i ? FontWeight.w700 : FontWeight.normal)),
                  ]),
                ),
              ),
          ]),
        ),
      ]);
    }

    return Row(children: [
      // ---------------- 导航栏 ----------------
      Container(
        width: 216,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2B2B2B) : Colors.white,
          border: Border(
              right: BorderSide(
                  color: dark ? const Color(0xFF3A3A3A) : AppTokens.border)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 18),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                      colors: [Color(0xFF00B7C2), Color(0xFF0078D4)]),
                ),
                alignment: Alignment.center,
                child: const Text('✨', style: TextStyle(fontSize: 17)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('提示词优化',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text('Prompt Optimizer',
                      style: TextStyle(fontSize: 11, color: AppTokens.text3)),
                ]),
              ),
            ]),
          ),
          for (var i = 0; i < _navItems.length; i++)
            _NavItem(
              icon: _navItems[i].$1,
              label: _navItems[i].$2,
              selected: _index == i,
              onTap: () => navigateTo(i),
            ),
          const Spacer(),
          // ---------------- 版本模块（原设置页底部迁入；替代原平台标注） ----------------
          const _VersionBlock(),
        ]),
      ),
      // ---------------- 页面区 ----------------
      content,
    ]);
  }
}

/// 导航栏底部版本模块：版本号（读自 pubspec 构建元数据）+ 真实检查更新。
///
/// 更新链路：UpdateService（GitHub Release 检测）→ UpdateDialog
/// （新版本信息 + 下载进度 + 安装反馈，平台安装器执行升级）。
class _VersionBlock extends StatefulWidget {
  const _VersionBlock();

  @override
  State<_VersionBlock> createState() => _VersionBlockState();
}

class _VersionBlockState extends State<_VersionBlock> {
  String? _versionLabel; // 展示标签：v1.0.0 · Build 1
  String _rawVersion = '0.0.0'; // 比较用原始版本号（来自构建元数据）
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    String label;
    var raw = _rawVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      label = 'v${info.version} · Build ${info.buildNumber}';
      raw = info.version;
    } catch (_) {
      label = 'v- · Build -'; // 构建元数据不可用（如测试环境未 mock）
    }
    if (mounted) {
      setState(() {
        _versionLabel = label;
        _rawVersion = raw;
      });
    }
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final service = UpdateService.debugOverride?.call() ?? UpdateService();
    try {
      final result = await service.checkLatest(_rawVersion);
      if (!mounted) return;
      if (result == null) {
        displayInfoBar(context, builder: (context, close) => InfoBar(
              title: const Text('✓ 当前已是最新版本'),
              severity: InfoBarSeverity.success,
              onClose: close,
            ));
      } else {
        await showUpdateDialog(context, result: result, service: service);
      }
    } on UpdateException catch (e) {
      if (!mounted) return;
      displayInfoBar(context, builder: (context, close) => InfoBar(
            title: Text('检查更新失败：${e.message}'),
            severity: InfoBarSeverity.error,
            onClose: close,
          ));
    } catch (e) {
      if (!mounted) return;
      displayInfoBar(context, builder: (context, close) => InfoBar(
            title: Text('检查更新失败：$e'),
            severity: InfoBarSeverity.error,
            onClose: close,
          ));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = FluentTheme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF242424) : const Color(0xFFF6F7F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: dark ? const Color(0xFF3A3A3A) : AppTokens.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              gradient: const LinearGradient(
                  colors: [Color(0xFF00B7C2), Color(0xFF0078D4)]),
            ),
            alignment: Alignment.center,
            child: const Text('✨', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('提示词优化工具',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 1),
              Text(_versionLabel ?? '正在读取版本…',
                  style: const TextStyle(fontSize: 10.5, color: AppTokens.text3),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        const SizedBox(height: 9),
        Button(
          onPressed: _checking ? null : _checkUpdate,
          child: Center(
              child: _checking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2))
                  : const Text('检查更新', style: TextStyle(fontSize: 12))),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = FluentTheme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? (dark ? const Color(0xFF1B3A3D) : AppTokens.accentLight)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            if (selected)
              Container(
                width: 3,
                height: 16,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                    color: AppTokens.accent, borderRadius: BorderRadius.circular(2)),
              ),
            Icon(icon,
                size: 16,
                color: selected ? AppTokens.accentDark : AppTokens.text2),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? AppTokens.accentDark : AppTokens.text2)),
          ]),
        ),
      ),
    );
  }
}

/// 从任意页面获取壳并跳转
void navigateTo(BuildContext context, int index) {
  context.findAncestorStateOfType<AppShellState>()?.navigateTo(index);
}
