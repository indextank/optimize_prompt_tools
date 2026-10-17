/// Linux 桌面打包回归：deb/rpm 的启动 wrapper 与菜单图标链路。
///
/// 覆盖两个曾出现的真实缺陷：
/// 1. wrapper exec 路径硬编码下划线，与实际安装目录（连字符 PKG_NAME）不一致
///    → 安装后运行报 "exec: ... not found"。
/// 2. hicolor 仅装 256 单尺寸 → 菜单按像素比请求 16/22/24/32/48 时命中失败，
///    图标显示为空白/占位。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hicolor 多尺寸图标齐全（菜单各像素比请求均能命中）', () {
    final sizes = [16, 22, 24, 32, 48, 64, 128, 256];
    for (final s in sizes) {
      final f = File('packaging/hicolor/${s}x$s/apps/prompt_optimizer.png');
      expect(f.existsSync(), isTrue,
          reason: '缺少 hicolor ${s}x$s 图标（菜单小尺寸请求会命中失败）');
      final b = f.readAsBytesSync();
      final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
      final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
      expect((w, h), (s, s), reason: '${s}x$s 图标实际尺寸不符');
    }
    // scalable 矢量兜底
    expect(File('packaging/hicolor/scalable/apps/prompt_optimizer.svg').existsSync(),
        isTrue, reason: '缺少 scalable SVG 兜底');
  });

  test('打包脚本的 hicolor 安装为多尺寸（非单 256）+ 缓存刷新', () {
    final script = File('build-linux.sh');
    if (!script.existsSync()) return; // 脚本不入仓库，缺失时跳过
    final s = script.readAsStringSync();
    expect(s, contains('install_hicolor_icons'),
        reason: '应调用多尺寸图标安装函数');
    expect(s, contains('gtk-update-icon-cache'),
        reason: 'deb/rpm 安装后必须刷新图标缓存，否则菜单图标不立即生效');
    expect(s, contains('update-desktop-database'),
        reason: 'deb/rpm 安装后必须刷新桌面数据库');
  });

  test('wrapper exec 路径与实际安装目录一致（连字符 PKG_NAME，非硬编码下划线）', () {
    final script = File('build-linux.sh');
    if (!script.existsSync()) return; // 脚本不入仓库，缺失时跳过
    final s = script.readAsStringSync();

    // 1) 不能出现旧的硬编码下划线路径（曾致 exec not found）
    expect(s, isNot(contains('/usr/lib/prompt_optimizer/prompt_optimizer')),
        reason: 'wrapper 不得硬编码下划线路径，实际安装目录用连字符 PKG_NAME');

    // 2) 必须以 PKG_NAME 变量注入 wrapper 目标路径
    expect(s, contains(r'/usr/lib/${PKG_NAME}/prompt_optimizer'),
        reason: 'wrapper 目标路径必须与安装目录用同一 PKG_NAME 变量');

    // 3) deb 与 rpm 段都应传入该路径
    final callCount = RegExp(r'write_wrapper .*?/usr/lib/\$\{PKG_NAME\}/prompt_optimizer',
            dotAll: true)
        .allMatches(s)
        .length;
    expect(callCount, greaterThanOrEqualTo(2),
        reason: 'deb 与 rpm 两处 write_wrapper 调用都必须传入一致的可执行路径');
  });
}
