/// 存储路径决策测试：
/// - resolveDbPath：Linux → ~/.config/prompt_optimizer/，Windows → %APPDATA% 子目录
/// - shouldMigrateLegacyDb：新库不存在且旧库存在时才迁移
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/services/storage/storage_factory_native.dart';

void main() {
  group('resolveDbPath 平台决策', () {
    test('Linux：使用 XDG configHome（~/.config），非 dataHome', () {
      final path = resolveDbPath(
        platform: 'linux',
        linuxConfigHome: '/home/user/.config',
      );
      expect(path, '/home/user/.config/prompt_optimizer/prompt_optimizer.db');
      // 必须是 .config 而非 .local/share（getApplicationSupportDirectory 的默认行为）
      expect(path, isNot(contains('.local/share')));
    });

    test('Linux：尊重 XDG_CONFIG_HOME 环境覆盖', () {
      final path = resolveDbPath(
        platform: 'linux',
        linuxConfigHome: '/custom/cfg',
      );
      expect(path, '/custom/cfg/prompt_optimizer/prompt_optimizer.db');
    });

    test('Windows：%APPDATA%（RoamingAppData）子目录', () {
      final supportDir = r'C:\Users\me\AppData\Roaming\prompt_optimizer';
      final path = resolveDbPath(platform: 'windows', supportDir: supportDir);
      // 分隔符由宿主平台 p.join 决定（Linux 宿主跑测试为 /），断言语义而非字面符
      expect(path.startsWith(supportDir), isTrue,
          reason: 'DB 必须位于 %APPDATA% 的应用子目录内');
      expect(path.endsWith('prompt_optimizer.db'), isTrue);
    });

    test('其他平台（macOS/Android）：沿用平台默认支持目录', () {
      final path = resolveDbPath(
        platform: 'macos',
        supportDir: '/Users/me/Library/Application Support/prompt_optimizer',
      );
      expect(path,
          '/Users/me/Library/Application Support/prompt_optimizer/prompt_optimizer.db');
    });
  });

  group('shouldMigrateLegacyDb 迁移判定', () {
    test('新库不存在 + 旧库存在 → 迁移', () {
      expect(
          shouldMigrateLegacyDb(newExists: false, oldExists: true), isTrue);
    });

    test('新库已存在 → 不迁移（不覆盖用户新数据）', () {
      expect(
          shouldMigrateLegacyDb(newExists: true, oldExists: true), isFalse);
    });

    test('旧库不存在 → 不迁移', () {
      expect(
          shouldMigrateLegacyDb(newExists: false, oldExists: false), isFalse);
    });
  });
}
