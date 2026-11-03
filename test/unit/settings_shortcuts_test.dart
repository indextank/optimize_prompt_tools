/// 设置快捷键校验与旧配置兼容测试。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/services/settings_service.dart';
import 'package:prompt_optimizer/state/app_state.dart';

import '../fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;

  setUp(() async {
    state = await makeTestAppState(llm: FakeLlmClient());
  });

  tearDown(() => state.dispose());

  test('默认可配置快捷键：全局唤起 / 快速优化', () {
    final s = state.settings.settings;
    expect(s.hotkey, 'Ctrl+Shift+Space');
    expect(s.optimizeHotkey, 'Ctrl+Enter');
  });

  test('旧配置中的 floating_ball 被忽略，不影响新字段', () async {
    final legacy = jsonEncode({
      'app': 'prompt_optimizer',
      'config_version': 1,
      'settings': {
        'floating_ball': true,
        'hotkey': 'Alt+Shift+P',
        'close_tab_hotkey': 'Alt+W',
        'new_tab_hotkey': 'Alt+T',
      },
    });
    final merged = state.parseImportedSettings(legacy);
    expect(await state.settings.update(merged), isNull);

    final s = state.settings.settings;
    expect(s.hotkey, 'Alt+Shift+P');
    expect(s.optimizeHotkey, 'Ctrl+Enter');
    expect(s.toJson().containsKey('floating_ball'), isFalse);
    expect(s.toJson().containsKey('close_tab_hotkey'), isFalse);
    expect(s.toJson().containsKey('new_tab_hotkey'), isFalse);
  });

  test('非法/无修饰键/重复组合被拒绝且不写入', () async {
    final before = state.settings.settings;

    expect(await state.settings.update(before.copyWith(optimizeHotkey: 'bad')),
        contains('格式无效'));
    expect(
        await state.settings.update(before.copyWith(optimizeHotkey: 'F5')),
        contains('修饰键'));
    expect(
        await state.settings
            .update(before.copyWith(optimizeHotkey: before.hotkey)),
        contains('冲突'));
    expect(
        await state.settings
            .update(before.copyWith(optimizeHotkey: 'Ctrl+W')),
        contains('固定的标签快捷键'));

    final after = state.settings.settings;
    expect(after.optimizeHotkey, before.optimizeHotkey);
  });

  test('自定义快捷键持久化并在重新加载后保留', () async {
    final err = await state.settings.update(state.settings.settings.copyWith(
      hotkey: 'Alt+Shift+P',
      optimizeHotkey: 'Alt+Enter',
    ));
    expect(err, isNull);

    final reloaded = await SettingsService.load(state.storage);
    expect(reloaded.settings.hotkey, 'Alt+Shift+P');
    expect(reloaded.settings.optimizeHotkey, 'Alt+Enter');
    expect(reloaded.settings.toJson().containsKey('close_tab_hotkey'), isFalse);
    expect(reloaded.settings.toJson().containsKey('new_tab_hotkey'), isFalse);
  });
}
