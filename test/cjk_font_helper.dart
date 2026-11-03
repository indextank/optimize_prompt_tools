/// 视觉 golden 基线字体解析。
///
/// 运行时字体策略（见 `lib/ui/theme.dart`）：
/// - Windows：Microsoft YaHei UI（微软雅黑，缺失回退 Microsoft YaHei/SimSun）
/// - Linux：Noto Sans CJK SC（缺失回退其它 Noto CJK / 思源黑体）
/// - macOS：PingFang SC
///
/// 已提交的 golden 全部由 **Linux + Noto Sans CJK** 生成。Windows 运行时
/// 使用微软雅黑，字形度量与 Noto 不同；若在 Windows 上直接比较 Noto golden
/// 会得到假失败，因此此处仍只返回 Noto 路径，字体不匹配时跳过视觉套件。
/// 需要真机字体度量但不比对 golden 的用例（如 RenderFlex 溢出回归）应自行
/// 加载微软雅黑（见 workbench_screenshot_regression_test.dart）。
library;

import 'dart:io';

/// Paths that match goldens committed from Linux CI / local runs.
const List<String> kGoldenCjkFontCandidates = [
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
];

/// Returns a font path only when it can match existing goldens; else null.
String? findHostCjkFontPath() {
  for (final path in kGoldenCjkFontCandidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// Skip reason when no matching CJK font is available.
const String kNoCjkFontSkip = 'Golden CJK font (Noto) not available on host';
