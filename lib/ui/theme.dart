/// 设计令牌（对齐基准项目视觉与 docs/images 设计稿）
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// 按平台解析优先中文字体族。
///
/// 此前将逗号分隔的回退链写入 `fontFamily`，会被当成单个无效族名，
/// 回退到不含中文字形的默认字体导致合成渲染发虚。
String resolveCjkFontFamily() {
  if (kIsWeb) return 'PingFang SC';
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return 'Microsoft YaHei UI';
    case TargetPlatform.macOS:
      return 'PingFang SC';
    case TargetPlatform.linux:
      return 'Noto Sans CJK SC';
    default:
      return 'Microsoft YaHei UI';
  }
}

FluentThemeData buildFluentTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return FluentThemeData(
    brightness: brightness,
    accentColor: Colors.teal,
    scaffoldBackgroundColor: dark ? const Color(0xFF202020) : AppTokens.pageBg,
    cardColor: dark ? const Color(0xFF2B2B2B) : AppTokens.cardBg,
    // 单一合法族名；Linux 缺 Noto 时由系统回退到思源黑体等已装 CJK 字体
    fontFamily: resolveCjkFontFamily(),
  );
}

/// 设计令牌
abstract final class AppTokens {
  static const Color pageBg = Color(0xFFF5F6F7);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5E7EB);
  static const Color text = Color(0xFF1F2329);
  static const Color text2 = Color(0xFF646A73);
  static const Color text3 = Color(0xFF8F959E);

  /// 主色青绿（对齐 qfluentwidgets 默认 #009FAA）
  static const Color accent = Color(0xFF009FAA);
  static const Color accentDark = Color(0xFF008A94);
  static const Color accentLight = Color(0xFFE6F7F8);

  /// 「★ 默认」标记蓝（基准 #4A90D9）
  static const Color defaultBlue = Color(0xFF4A90D9);

  /// 成功反馈绿
  static const Color success = Color(0xFF2DA44E);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFD13438);

  // ---------------- TabView 标签（浅色桌面 Fluent 风格） ----------------
  // fluent 默认标签色是半透明 Mica 层（layerOnMicaBaseAltFillColor*），
  // 叠在未绘制区域（引擎黑底）上会形成黑底黑字；此处显式浅色令牌，
  // 保证「激活白卡 / 非激活浅灰深字」，与 _SceneChip/_ModeSegment 的
  // 浅色硬编码视觉语言一致。
  /// 激活 tab 背景：白卡
  static final WidgetStateColor tabSelectedBg =
      WidgetStateColor.resolveWith((states) => cardBg);

  /// 非激活 tab 背景：浅灰（hover/pressed 微调）
  static final WidgetStateColor tabBg = WidgetStateColor.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) return const Color(0xFFE4E7EB);
    if (states.contains(WidgetState.hovered)) return const Color(0xFFF0F1F3);
    return const Color(0xFFE8EAED);
  });

  /// 激活 tab 文字：深色（白卡上高对比）
  static final WidgetStateColor tabSelectedFg =
      WidgetStateColor.resolveWith((states) => text);

  /// 非激活 tab 文字：深灰（hover 加深、disabled 提亮）
  static final WidgetStateColor tabFg = WidgetStateColor.resolveWith((states) {
    if (states.contains(WidgetState.disabled)) return text3;
    if (states.contains(WidgetState.hovered)) return text;
    return text2;
  });

  static const double cardRadius = 8;

  // ---------------- 全局间距规范（统一刻度，禁止零散硬编码） ----------------
  /// 元素间紧凑间距（图标-文字、标签-控件）
  static const double gapXs = 4;

  /// 元素间常规间距（卡片内元素、表单项）
  static const double gapS = 8;

  /// 区块间距（卡片之间、分组之间）
  static const double gapM = 12;

  /// 大区块间距（页面头部与内容、主要分区）
  static const double gapL = 16;

  /// 页面边距（桌面端）
  static const double pagePadH = 26;

  /// 卡片内边距（左右）
  static const double cardPadH = 16;

  /// 紧凑布局断点（窄于此宽度走移动端布局）
  static const double compactBreakpoint = 720;
}
