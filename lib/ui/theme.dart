/// 设计令牌：语义化颜色（浅/深双主题）+ 间距/圆角刻度。
///
/// 颜色以 [AppColors]（`ThemeExtension`）集中提供，业务代码通过
/// `context.colors.<token>` 强类型取值；禁止在页面里散落 `Color(0x...)`
/// 或依赖 `Colors.white` 之类的固定值。
///
/// 取色依据：
/// 1) 参考图示的桌面端中性色阶（深色近黑画布 / 浅色灰白画布 + 白色卡片）；
/// 2) fluent_ui 桌面规范（控件由 FluentThemeData 统一着色）；
/// 3) WCAG AA：正文 ≥ 4.5:1、大字号 ≥ 3:1（见 test/widget/theme_tokens_test.dart）。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// 平台默认中文字体族。
///
/// 策略：
/// - Windows：优先「Microsoft YaHei UI」（微软雅黑），缺失时回退到
///   Microsoft YaHei / SimSun；
/// - Linux：使用「Noto Sans CJK SC」；
/// - macOS：PingFang SC；
/// - Web / 其他平台：PingFang SC / Noto Sans SC。
///
/// 注意：[fontFamily] 只接受单一合法族名（逗号分隔的链会被当作一个无效
/// 族名），多级回退由 [resolveCjkFontFallback] 写入 TextStyle 的
/// `fontFamilyFallback`，仍缺字形时再由引擎做系统级回退。
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
      // 测试环境/移动端无桌面字体：沿用微软雅黑族名（真机由引擎做系统回退）
      return 'Microsoft YaHei UI';
  }
}

/// 与 [resolveCjkFontFamily] 配套的回退链（按优先级排列）。
///
/// Windows 以微软雅黑家族为主，Linux 以 Noto CJK 家族为主。
List<String> resolveCjkFontFallback() {
  if (kIsWeb) {
    return const ['Microsoft YaHei', 'Noto Sans SC', 'sans-serif'];
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return const [
        'Microsoft YaHei',
        'Microsoft YaHei Light',
        'SimSun',
        'Segoe UI',
      ];
    case TargetPlatform.macOS:
      return const ['Hiragino Sans GB', 'Heiti SC', 'Arial Unicode MS'];
    case TargetPlatform.linux:
      return const [
        'Noto Sans CJK TC',
        'Noto Sans CJK JP',
        'Noto Sans SC',
        'Source Han Sans SC',
        'WenQuanYi Micro Hei',
        'DejaVu Sans',
      ];
    default:
      return const ['Noto Sans SC', 'Microsoft YaHei', 'sans-serif'];
  }
}

/// 为全部字号样式补上平台中文字体回退链。
Typography _withCjkFallback(Typography base, List<String> fallback) {
  TextStyle? apply(TextStyle? style) =>
      style?.copyWith(fontFamilyFallback: fallback);
  return Typography.raw(
    display: apply(base.display),
    titleLarge: apply(base.titleLarge),
    title: apply(base.title),
    subtitle: apply(base.subtitle),
    bodyLarge: apply(base.bodyLarge),
    bodyStrong: apply(base.bodyStrong),
    body: apply(base.body),
    caption: apply(base.caption),
  );
}

/// 品牌主色（青绿）在 fluent 控件中的色阶。
///
/// `defaultBrushFor`：浅色取 [dark]（白字 4.95:1），深色取 [lighter]
/// （黑字 ≥ 10:1），与 [AppColors] 的 accent/textOnAccent 对齐。
final AccentColor _appAccentColor = AccentColor.swatch(const {
  'darkest': Color(0xFF063F45),
  'darker': Color(0xFF0A5C64),
  'dark': Color(0xFF0E7C86),
  'normal': Color(0xFF12808A),
  'light': Color(0xFF2FB6C0),
  'lighter': Color(0xFF4DD0DA),
  'lightest': Color(0xFFA7EEF2),
});

FluentThemeData buildFluentTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = dark ? AppColors.dark : AppColors.light;
  return FluentThemeData(
    brightness: brightness,
    accentColor: _appAccentColor,
    scaffoldBackgroundColor: colors.pageBg,
    cardColor: colors.surface,
    // 单一合法族名（Linux: Noto CJK / Windows: 微软雅黑）；
    // 多级回退写入 typography 的 fontFamilyFallback
    fontFamily: resolveCjkFontFamily(),
    typography: _withCjkFallback(
      Typography.fromBrightness(brightness: brightness),
      resolveCjkFontFallback(),
    ),
    extensions: [colors],
  );
}

/// 语义化颜色令牌（强类型，编译期即可发现缺失字段）。
///
/// 命名约定：
/// - 表面：pageBg / sidebarBg / surface / surfaceSubtle / surfaceRaised
/// - 交互：hover / pressed / selected
/// - 文字：textPrimary / textSecondary / textTertiary / textDisabled / textOnAccent
/// - 线条：border / divider / focusRing
/// - 强调：accent / accentHover / accentPressed / accentSubtle / accentText
/// - 状态：info / warning / success / danger 各自的底色与文字色
/// - 其他：overlay / shadow / textOnBrand / brandGradient*
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.pageBg,
    required this.sidebarBg,
    required this.surface,
    required this.surfaceSubtle,
    required this.surfaceRaised,
    required this.hover,
    required this.pressed,
    required this.selected,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textOnAccent,
    required this.textOnBrand,
    required this.border,
    required this.divider,
    required this.focusRing,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentSubtle,
    required this.accentText,
    required this.info,
    required this.infoSubtle,
    required this.infoText,
    required this.success,
    required this.successSubtle,
    required this.successText,
    required this.warning,
    required this.warningSubtle,
    required this.warningText,
    required this.danger,
    required this.dangerSubtle,
    required this.dangerText,
    required this.overlay,
    required this.shadow,
    required this.brandGradientStart,
    required this.brandGradientEnd,
  });

  /// 页面级背景（画布）。
  final Color pageBg;

  /// 导航栏 / 侧栏背景，与画布有轻微层次。
  final Color sidebarBg;

  /// 卡片、面板、输入区等主要表面。
  final Color surface;

  /// 次级表面：卡片内嵌套块、只读区、分段控件底。
  final Color surfaceSubtle;

  /// 浮层表面：对话框、下拉菜单、Tooltip。
  final Color surfaceRaised;

  /// 悬停态背景（列表项、标签、菜单项）。
  final Color hover;

  /// 按下态背景。
  final Color pressed;

  /// 选中态背景（导航项、列表项）。
  final Color selected;

  /// 主文字（正文 / 标题）。
  final Color textPrimary;

  /// 次文字（说明 / 辅助信息）。
  final Color textSecondary;

  /// 三级文字（占位、弱提示，仍满足正文对比度）。
  final Color textTertiary;

  /// 禁用文字（不承担可读信息，允许低于 4.5:1）。
  final Color textDisabled;

  /// 强调色填充上的文字。
  final Color textOnAccent;

  /// 品牌色块上的文字（始终为白色）。
  final Color textOnBrand;

  /// 边框。
  final Color border;

  /// 分隔线（比边框更弱）。
  final Color divider;

  /// 聚焦环。
  final Color focusRing;

  /// 强调色（填充、选中指示、主按钮）。
  final Color accent;

  final Color accentHover;
  final Color accentPressed;

  /// 强调色的浅色底（标签/chip 背景）。
  final Color accentSubtle;

  /// 强调色文字（链接、选中文字，保证 ≥ 4.5:1）。
  final Color accentText;

  /// 信息态。
  final Color info;
  final Color infoSubtle;
  final Color infoText;

  /// 成功态。
  final Color success;
  final Color successSubtle;
  final Color successText;

  /// 警告态。
  final Color warning;
  final Color warningSubtle;
  final Color warningText;

  /// 错误态。
  final Color danger;
  final Color dangerSubtle;
  final Color dangerText;

  /// 模态遮罩。
  final Color overlay;

  /// 阴影。
  final Color shadow;

  /// 品牌 logo 渐变。
  final Color brandGradientStart;
  final Color brandGradientEnd;

  /// 浅色主题：中性灰白画布 + 白色卡片，文字层级按 WCAG AA 校准。
  static const AppColors light = AppColors(
    pageBg: Color(0xFFF5F6F7),
    sidebarBg: Color(0xFFF4F5F6),
    surface: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF4F5F6),
    surfaceRaised: Color(0xFFFFFFFF),
    hover: Color(0xFFEDEFF1),
    pressed: Color(0xFFE3E6E9),
    selected: Color(0xFFE9EBEE),
    textPrimary: Color(0xFF1A1C1E),
    textSecondary: Color(0xFF5A6068),
    textTertiary: Color(0xFF667085),
    textDisabled: Color(0xFFA6ACB4),
    textOnAccent: Color(0xFFFFFFFF),
    textOnBrand: Color(0xFFFFFFFF),
    border: Color(0xFFE1E4E8),
    divider: Color(0xFFEBEDF0),
    focusRing: Color(0xFF0E7C86),
    accent: Color(0xFF0E7C86),
    accentHover: Color(0xFF0A6A73),
    accentPressed: Color(0xFF08575F),
    accentSubtle: Color(0xFFE6F4F5),
    accentText: Color(0xFF0B6E77),
    info: Color(0xFF1D4ED8),
    infoSubtle: Color(0xFFE8F0FE),
    infoText: Color(0xFF1D4ED8),
    success: Color(0xFF1A7F37),
    successSubtle: Color(0xFFE9F5EC),
    successText: Color(0xFF166B2E),
    warning: Color(0xFFB45309),
    warningSubtle: Color(0xFFFFF6E5),
    warningText: Color(0xFF8A4B00),
    danger: Color(0xFFC42B1C),
    dangerSubtle: Color(0xFFFDECEA),
    dangerText: Color(0xFFB42318),
    overlay: Color(0x59000000),
    shadow: Color(0x24000000),
    brandGradientStart: Color(0xFF00A6B2),
    brandGradientEnd: Color(0xFF0078D4),
  );

  /// 深色主题：近黑画布 + 略亮卡片，避免纯黑纯白的高对比刺眼与浮层融合。
  static const AppColors dark = AppColors(
    pageBg: Color(0xFF0F1012),
    sidebarBg: Color(0xFF121315),
    surface: Color(0xFF18191C),
    surfaceSubtle: Color(0xFF202226),
    surfaceRaised: Color(0xFF1D1F22),
    hover: Color(0xFF24262A),
    pressed: Color(0xFF2B2E33),
    selected: Color(0xFF24262A),
    textPrimary: Color(0xFFE9EAEC),
    textSecondary: Color(0xFFA8AEB6),
    textTertiary: Color(0xFF8A919A),
    textDisabled: Color(0xFF5F666E),
    textOnAccent: Color(0xFF08191B),
    textOnBrand: Color(0xFFFFFFFF),
    border: Color(0xFF2A2C30),
    divider: Color(0xFF232528),
    focusRing: Color(0xFF4DD0DA),
    accent: Color(0xFF4DD0DA),
    accentHover: Color(0xFF6FDDE5),
    accentPressed: Color(0xFF2FB6C0),
    accentSubtle: Color(0xFF12333A),
    accentText: Color(0xFF4DD0DA),
    info: Color(0xFF7CB2FF),
    infoSubtle: Color(0xFF16263D),
    infoText: Color(0xFF9CC4FF),
    success: Color(0xFF5DD47F),
    successSubtle: Color(0xFF12291A),
    successText: Color(0xFF7BE49A),
    warning: Color(0xFFF2B54A),
    warningSubtle: Color(0xFF33260F),
    warningText: Color(0xFFFFC96B),
    danger: Color(0xFFFF8A80),
    dangerSubtle: Color(0xFF3A1917),
    dangerText: Color(0xFFFFB4AC),
    overlay: Color(0x99000000),
    shadow: Color(0x66000000),
    brandGradientStart: Color(0xFF22C3CE),
    brandGradientEnd: Color(0xFF2F81F7),
  );

  /// 读取当前主题令牌；未注入扩展的主题（测试/视觉沙盒）按亮度回退到
  /// 对应默认调色板，避免 `null` 崩溃。
  static AppColors of(BuildContext context) {
    final theme = FluentTheme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  /// 标签条状态色：激活=卡片表面，非激活=次级表面（悬停/按下加深）。
  WidgetStateColor get tabBackground => WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return pressed;
        if (states.contains(WidgetState.hovered)) return hover;
        return surfaceSubtle;
      });

  WidgetStateColor get tabSelectedBackground =>
      WidgetStateColor.resolveWith((_) => surface);

  WidgetStateColor get tabForeground => WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return textDisabled;
        if (states.contains(WidgetState.hovered)) return textPrimary;
        return textSecondary;
      });

  WidgetStateColor get tabSelectedForeground =>
      WidgetStateColor.resolveWith((_) => textPrimary);

  @override
  AppColors copyWith({
    Color? pageBg,
    Color? sidebarBg,
    Color? surface,
    Color? surfaceSubtle,
    Color? surfaceRaised,
    Color? hover,
    Color? pressed,
    Color? selected,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? textOnAccent,
    Color? textOnBrand,
    Color? border,
    Color? divider,
    Color? focusRing,
    Color? accent,
    Color? accentHover,
    Color? accentPressed,
    Color? accentSubtle,
    Color? accentText,
    Color? info,
    Color? infoSubtle,
    Color? infoText,
    Color? success,
    Color? successSubtle,
    Color? successText,
    Color? warning,
    Color? warningSubtle,
    Color? warningText,
    Color? danger,
    Color? dangerSubtle,
    Color? dangerText,
    Color? overlay,
    Color? shadow,
    Color? brandGradientStart,
    Color? brandGradientEnd,
  }) {
    return AppColors(
      pageBg: pageBg ?? this.pageBg,
      sidebarBg: sidebarBg ?? this.sidebarBg,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      hover: hover ?? this.hover,
      pressed: pressed ?? this.pressed,
      selected: selected ?? this.selected,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      textOnBrand: textOnBrand ?? this.textOnBrand,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      focusRing: focusRing ?? this.focusRing,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentPressed: accentPressed ?? this.accentPressed,
      accentSubtle: accentSubtle ?? this.accentSubtle,
      accentText: accentText ?? this.accentText,
      info: info ?? this.info,
      infoSubtle: infoSubtle ?? this.infoSubtle,
      infoText: infoText ?? this.infoText,
      success: success ?? this.success,
      successSubtle: successSubtle ?? this.successSubtle,
      successText: successText ?? this.successText,
      warning: warning ?? this.warning,
      warningSubtle: warningSubtle ?? this.warningSubtle,
      warningText: warningText ?? this.warningText,
      danger: danger ?? this.danger,
      dangerSubtle: dangerSubtle ?? this.dangerSubtle,
      dangerText: dangerText ?? this.dangerText,
      overlay: overlay ?? this.overlay,
      shadow: shadow ?? this.shadow,
      brandGradientStart: brandGradientStart ?? this.brandGradientStart,
      brandGradientEnd: brandGradientEnd ?? this.brandGradientEnd,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      pageBg: mix(pageBg, other.pageBg),
      sidebarBg: mix(sidebarBg, other.sidebarBg),
      surface: mix(surface, other.surface),
      surfaceSubtle: mix(surfaceSubtle, other.surfaceSubtle),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      hover: mix(hover, other.hover),
      pressed: mix(pressed, other.pressed),
      selected: mix(selected, other.selected),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      textDisabled: mix(textDisabled, other.textDisabled),
      textOnAccent: mix(textOnAccent, other.textOnAccent),
      textOnBrand: mix(textOnBrand, other.textOnBrand),
      border: mix(border, other.border),
      divider: mix(divider, other.divider),
      focusRing: mix(focusRing, other.focusRing),
      accent: mix(accent, other.accent),
      accentHover: mix(accentHover, other.accentHover),
      accentPressed: mix(accentPressed, other.accentPressed),
      accentSubtle: mix(accentSubtle, other.accentSubtle),
      accentText: mix(accentText, other.accentText),
      info: mix(info, other.info),
      infoSubtle: mix(infoSubtle, other.infoSubtle),
      infoText: mix(infoText, other.infoText),
      success: mix(success, other.success),
      successSubtle: mix(successSubtle, other.successSubtle),
      successText: mix(successText, other.successText),
      warning: mix(warning, other.warning),
      warningSubtle: mix(warningSubtle, other.warningSubtle),
      warningText: mix(warningText, other.warningText),
      danger: mix(danger, other.danger),
      dangerSubtle: mix(dangerSubtle, other.dangerSubtle),
      dangerText: mix(dangerText, other.dangerText),
      overlay: mix(overlay, other.overlay),
      shadow: mix(shadow, other.shadow),
      brandGradientStart: mix(brandGradientStart, other.brandGradientStart),
      brandGradientEnd: mix(brandGradientEnd, other.brandGradientEnd),
    );
  }
}

/// `context.colors.textPrimary` 简写。
extension AppColorsContext on BuildContext {
  AppColors get colors => AppColors.of(this);
}

/// 服务商品牌色（仅用于头像/标识；已按白字 4.5:1 选取深色相）。
///
/// 品牌色不属于主题语义色，但它也不应散落在业务文件中，故集中在此。
abstract final class AppBrandColors {
  static const Color doubao = Color(0xFFC2410C);
  static const Color dashscope = Color(0xFF047857);
  static const Color qianfan = Color(0xFF2932E1);
  static const Color zhipu = Color(0xFF0F52BA);
  static const Color kimi = Color(0xFF6D28D9);
  static const Color deepseek = Color(0xFF1D4ED8);
  static const Color stepfun = Color(0xFF15803D);
  static const Color mimo = Color(0xFFC2410C);
  static const Color minimax = Color(0xFF5B21B6);

  static const Map<String, Color> byProvider = {
    'doubao': doubao,
    'dashscope': dashscope,
    'qianfan': qianfan,
    'zhipu': zhipu,
    'kimi': kimi,
    'deepseek': deepseek,
    'stepfun': stepfun,
    'mimo': mimo,
    'minimax': minimax,
  };
}

/// 布局令牌（不含颜色）。
abstract final class AppTokens {
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
