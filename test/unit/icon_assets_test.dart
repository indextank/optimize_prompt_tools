/// 应用图标资产与打包接线回归：
/// - 设计母版/各端尺寸存在且维度正确
/// - Linux runner 资源与 CMake 安装规则接线完好（任务栏图标链路）
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('设计母版与各端图标资产存在且为合法 PNG', () async {
    for (final path in [
      'assets/icon/app_icon_1024.png',
      'linux/runner/resources/app_icon.png',
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-hdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
    ]) {
      final bytes = await File(path).readAsBytes();
      expect(bytes.length, greaterThan(512), reason: '$path 文件过小');
      expect(bytes.sublist(0, 8),
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
          reason: '$path 不是合法 PNG');
    }
  });

  test('各端图标尺寸逐一匹配', () async {
    (int, int) read(String path) {
      final bytes = File(path).readAsBytesSync();
      final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      return (w, h);
    }

    expect(read('assets/icon/app_icon_1024.png'), (1024, 1024));
    expect(read('linux/runner/resources/app_icon.png'), (256, 256));
    expect(read('android/app/src/main/res/mipmap-mdpi/ic_launcher.png'), (48, 48));
    expect(read('android/app/src/main/res/mipmap-hdpi/ic_launcher.png'), (72, 72));
    expect(read('android/app/src/main/res/mipmap-xhdpi/ic_launcher.png'), (96, 96));
    expect(read('android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png'), (144, 144));
    expect(read('android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png'), (192, 192));
  });

  test('Windows ICO 为多尺寸图标', () {
    final bytes = File('windows/runner/resources/app_icon.ico').readAsBytesSync();
    expect(bytes.length, greaterThan(2000));
    // ICO 头：保留字 0 + 类型 1 + 计数
    expect(bytes[0], 0);
    expect(bytes[1], 0);
    expect(bytes[2], 1);
    expect(bytes[3], 0);
    final count = bytes[4] | (bytes[5] << 8);
    expect(count, greaterThanOrEqualTo(4), reason: '应含多个尺寸');
  });

  test('任务栏图标链路接线完好（runner + CMake + 打包脚本）', () {
    final cc = File('linux/runner/my_application.cc').readAsStringSync();
    expect(cc, contains('gtk_window_set_default_icon_from_file'),
        reason: 'runner 必须设置窗口默认图标');
    expect(cc, contains('app_icon.png'), reason: 'runner 必须引用图标文件');

    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('app_icon.png'), reason: 'CMake 必须安装图标到 bundle');
    // 必须注册在 bundle 清理规则之后，否则被 install CODE REMOVE 抹掉
    final removeIdx = cmake.indexOf('file(REMOVE_RECURSE');
    final iconIdx = cmake.indexOf('app_icon.png');
    expect(iconIdx, greaterThan(removeIdx),
        reason: '图标安装规则必须位于 bundle 清理规则之后');

    // 打包脚本不入 git 仓库（见 .gitignore），存在时才校验其引用一致性
    final script = File('build-linux.sh');
    if (script.existsSync()) {
      expect(script.readAsStringSync(), contains('linux/runner/resources/app_icon.png'),
          reason: 'deb/rpm/AppImage 打包应引用同一图标源');
    }
  });
}
