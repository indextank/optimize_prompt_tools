/// 应用设置服务：类型化读写 + 变更通知 + 校验。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/shortcuts.dart';
import 'storage/app_storage.dart';

/// 主题模式
enum AppThemeMode { light, dark, system }

/// 代理模式
enum ProxyMode { system, direct, custom }

/// 应用设置（值对象）
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.language = 'zh_CN',
    this.autoStart = false,
    this.hotkey = 'Ctrl+Shift+Space',
    this.optimizeHotkey = 'Ctrl+Enter',
    this.defaultMode = OptimizeMode.quick,
    this.defaultScene = 'ai_coding',
    this.resultLanguage = 'follow',
    this.autoCopy = false,
    this.retentionDays = 30,
    this.proxyMode = ProxyMode.system,
    this.proxyUrl = '',
    this.timeoutSecs = 30,
    this.parallelEnabled = false,
    this.defaultServiceId = '',
  });

  final AppThemeMode themeMode;
  final String language;
  final bool autoStart;

  /// 全局唤起热键（系统级注册；桌面端生效）。
  final String hotkey;

  /// 工作台「快速优化」快捷键（应用内）。
  final String optimizeHotkey;

  final OptimizeMode defaultMode;
  final String defaultScene;

  /// follow | zh | en
  final String resultLanguage;
  final bool autoCopy;

  /// 历史保留天数；0 = 永久
  final int retentionDays;
  final ProxyMode proxyMode;
  final String proxyUrl;
  final int timeoutSecs;
  final bool parallelEnabled;
  final String defaultServiceId;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? language,
    bool? autoStart,
    String? hotkey,
    String? optimizeHotkey,
    OptimizeMode? defaultMode,
    String? defaultScene,
    String? resultLanguage,
    bool? autoCopy,
    int? retentionDays,
    ProxyMode? proxyMode,
    String? proxyUrl,
    int? timeoutSecs,
    bool? parallelEnabled,
    String? defaultServiceId,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
        autoStart: autoStart ?? this.autoStart,
        hotkey: hotkey ?? this.hotkey,
        optimizeHotkey: optimizeHotkey ?? this.optimizeHotkey,
        defaultMode: defaultMode ?? this.defaultMode,
        defaultScene: defaultScene ?? this.defaultScene,
        resultLanguage: resultLanguage ?? this.resultLanguage,
        autoCopy: autoCopy ?? this.autoCopy,
        retentionDays: retentionDays ?? this.retentionDays,
        proxyMode: proxyMode ?? this.proxyMode,
        proxyUrl: proxyUrl ?? this.proxyUrl,
        timeoutSecs: timeoutSecs ?? this.timeoutSecs,
        parallelEnabled: parallelEnabled ?? this.parallelEnabled,
        defaultServiceId: defaultServiceId ?? this.defaultServiceId,
      );

  Map<String, dynamic> toJson() => {
        'theme_mode': themeMode.name,
        'language': language,
        'auto_start': autoStart,
        'hotkey': hotkey,
        'optimize_hotkey': optimizeHotkey,
        'default_mode': defaultMode.name,
        'default_scene': defaultScene,
        'result_language': resultLanguage,
        'auto_copy': autoCopy,
        'retention_days': retentionDays,
        'proxy_mode': proxyMode.name,
        'proxy_url': proxyUrl,
        'timeout_secs': timeoutSecs,
        'parallel_enabled': parallelEnabled,
        'default_service_id': defaultServiceId,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: AppThemeMode.values.firstWhere((e) => e.name == j['theme_mode'],
            orElse: () => AppThemeMode.system),
        language: j['language'] as String? ?? 'zh_CN',
        autoStart: j['auto_start'] as bool? ?? false,
        hotkey: j['hotkey'] as String? ?? 'Ctrl+Shift+Space',
        optimizeHotkey:
            j['optimize_hotkey'] as String? ?? 'Ctrl+Enter',
        defaultMode: OptimizeMode.parse(j['default_mode'] as String? ?? 'quick'),
        defaultScene: j['default_scene'] as String? ?? 'ai_coding',
        resultLanguage: j['result_language'] as String? ?? 'follow',
        autoCopy: j['auto_copy'] as bool? ?? false,
        retentionDays: (j['retention_days'] as num?)?.toInt() ?? 30,
        proxyMode: ProxyMode.values.firstWhere((e) => e.name == j['proxy_mode'],
            orElse: () => ProxyMode.system),
        proxyUrl: j['proxy_url'] as String? ?? '',
        timeoutSecs: (j['timeout_secs'] as num?)?.toInt() ?? 30,
        // 每次运行软件「并行对比」默认关闭：不沿用上次运行的开启状态
        parallelEnabled: false,
        defaultServiceId: j['default_service_id'] as String? ?? '',
      );

  /// 校验；返回错误文案（null = 合法）
  String? validate() {
    final shortcutError = _validateShortcuts();
    if (shortcutError != null) return shortcutError;
    if (timeoutSecs < 5 || timeoutSecs > 300) return '请求超时时间需在 5-300 秒之间';
    if (retentionDays < 0 || retentionDays > 3650) return '历史保留天数需在 0-3650 之间';
    if (proxyMode == ProxyMode.custom && proxyUrl.trim().isNotEmpty) {
      final u = proxyUrl.trim();
      // 仅在已出现协议分隔符时校验前缀，避免逐字键入过程中被中间态误拦截。
      if (u.contains('://') &&
          !u.startsWith('http://') &&
          !u.startsWith('https://') &&
          !u.startsWith('socks5://')) {
        return '代理地址需以 http:// 、https:// 或 socks5:// 开头';
      }
    }
    return null;
  }

  /// 四个可配置快捷键：格式合法、必须带修饰键、彼此不得冲突。
  String? _validateShortcuts() {
    final entries = <(String, String)>[
      ('全局唤起热键', hotkey),
      ('快速优化快捷键', optimizeHotkey),
    ];
    final seen = <ShortcutBinding, String>{};
    for (final (label, raw) in entries) {
      final error = validateShortcutText(raw, field: label);
      if (error != null) return error;
      final binding = ShortcutBinding.tryParse(raw)!;
      if (binding.label == kCloseTabShortcut ||
          binding.label == kNewTabShortcut) {
        return '$label不能使用固定的标签快捷键（$kCloseTabShortcut / $kNewTabShortcut）';
      }
      final previous = seen[binding];
      if (previous != null) {
        return '$label与「$previous」快捷键冲突，请更换组合';
      }
      seen[binding] = label;
    }
    return null;
  }
}

/// 设置服务
class SettingsService extends ChangeNotifier {
  SettingsService(this._storage, this._settings);

  final AppStorage _storage;
  AppSettings _settings;

  static const _key = 'app_settings';

  AppSettings get settings => _settings;

  /// 从存储加载
  static Future<SettingsService> load(AppStorage storage) async {
    final raw = await storage.getSetting(_key);
    AppSettings s = const AppSettings();
    if (raw != null && raw.isNotEmpty) {
      try {
        s = AppSettings.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {
        // 损坏则回退默认
        s = const AppSettings();
      }
    }
    return SettingsService(storage, s);
  }

  /// 更新并持久化；校验失败返回错误文案且不保存
  Future<String?> update(AppSettings next) async {
    final err = next.validate();
    if (err != null) return err;
    _settings = next;
    await _storage.setSetting(_key, jsonEncode(next.toJson()));
    notifyListeners();
    return null;
  }
}
