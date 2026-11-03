/// 平台字体策略测试：
/// - Windows：优先 Microsoft YaHei UI（微软雅黑），回退 Microsoft YaHei/SimSun；
/// - Linux：Noto Sans CJK SC，回退其它 Noto CJK / 思源黑体；
/// - macOS：PingFang SC。
///
/// 通过 debugDefaultTargetPlatformOverride 模拟各平台，断言**主族名**与
/// **回退链**同时进入 FluentThemeData.typography，避免“只设 fontFamily、
/// 缺字形时回退到无中文字形”的旧问题。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/ui/theme.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Windows：微软雅黑优先，并带雅黑/宋体回退链', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    expect(resolveCjkFontFamily(), 'Microsoft YaHei UI');
    final fallback = resolveCjkFontFallback();
    expect(fallback.first, 'Microsoft YaHei');
    expect(fallback, contains('SimSun'));

    final theme = buildFluentTheme(Brightness.light);
    expect(theme.typography.body!.fontFamily, 'Microsoft YaHei UI');
    expect(
        theme.typography.body!.fontFamilyFallback, contains('Microsoft YaHei'));
    expect(theme.typography.caption!.fontFamilyFallback, contains('SimSun'));
    expect(theme.typography.title!.fontFamily, 'Microsoft YaHei UI');
  });

  test('Linux：Noto Sans CJK SC 优先，并带 Noto CJK 家族回退链', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    expect(resolveCjkFontFamily(), 'Noto Sans CJK SC');
    final fallback = resolveCjkFontFallback();
    expect(fallback, contains('Noto Sans CJK TC'));
    expect(fallback, contains('Source Han Sans SC'));

    final theme = buildFluentTheme(Brightness.dark);
    expect(theme.typography.body!.fontFamily, 'Noto Sans CJK SC');
    expect(theme.typography.body!.fontFamilyFallback,
        contains('Noto Sans CJK TC'));
    expect(theme.typography.body!.fontFamilyFallback,
        isNot(contains('Microsoft YaHei UI')));
  });

  test('macOS：PingFang SC 优先', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    expect(resolveCjkFontFamily(), 'PingFang SC');
    expect(resolveCjkFontFallback(), contains('Hiragino Sans GB'));

    final theme = buildFluentTheme(Brightness.light);
    expect(theme.typography.body!.fontFamily, 'PingFang SC');
  });

  test('深浅主题字体策略一致（颜色不影响 family/fallback）', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final light = buildFluentTheme(Brightness.light);
    final dark = buildFluentTheme(Brightness.dark);
    expect(light.typography.body!.fontFamily, dark.typography.body!.fontFamily);
    expect(light.typography.body!.fontFamilyFallback,
        dark.typography.body!.fontFamilyFallback);
  });
}
