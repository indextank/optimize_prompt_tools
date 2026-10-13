/// Widget 测试包装器
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:prompt_optimizer/ui/theme.dart';

/// 用 FluentApp 包裹被测页面
Widget wrapWithFluentApp(Widget child) {
  return FluentApp(
    theme: buildFluentTheme(Brightness.light),
    home: child,
  );
}
