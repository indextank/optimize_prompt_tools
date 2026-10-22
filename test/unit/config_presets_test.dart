/// 「导出配置含编程预置词、导入还原」验收：
/// - 导出 JSON 含 presets 段（无任何密钥字段）
/// - 导入还原：空库逐条还原（字段一致）；同 id 覆盖更新
/// - 名称冲突自动去重命名（导入不中断）
/// - 旧版导出（无 presets 段）向后兼容
/// - 非法预置词（空名/超 300 字）整体拒绝、不写任何数据
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/state/app_state.dart';

import '../fakes.dart';

CodingPreset _p(String id, {String name = '桌面端', String content = '内容', int createdAt = 1700000000}) =>
    CodingPreset(id: id, name: name, content: content, createdAt: createdAt);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    appState = await makeTestAppState();
  });

  group('导出含编程预置词', () {
    test('导出 JSON 含 presets 段且字段完整', () async {
      final state = await makeTestAppState();
      await state.savePreset(_p('p1', name: '桌面端', content: 'Electron + Vue3'));
      await state.savePreset(_p('p2', name: '移动端', content: 'UniApp', createdAt: 1700000001));
      final json = state.buildSettingsExportJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded.containsKey('presets'), isTrue);
      final presets = decoded['presets'] as List;
      expect(presets, hasLength(2));
      // 列表按 created_at DESC（新在前），按 id 定位断言字段
      final byId = {
        for (final e in presets) (e as Map<String, dynamic>)['id']: e
      };
      expect(byId['p1']!['name'], '桌面端');
      expect(byId['p1']!['content'], 'Electron + Vue3');
      expect(byId['p1']!['created_at'], 1700000000);
      expect(byId['p2']!['name'], '移动端');
    });

    test('导出内容不含任何密钥字段', () async {
      final state = await makeTestAppState();
      await state.saveService(testService(id: 'a'), apiKey: 'sk-SECRET-VALUE');
      await state.savePreset(_p('p1'));
      final json = state.buildSettingsExportJson();
      expect(json, isNot(contains('sk-SECRET-VALUE')));
      expect(json, isNot(contains('keyRef')));
    });
  });

  group('导入还原', () {
    test('空库导入逐条还原（字段一致）', () async {
      final src = await makeTestAppState();
      await src.savePreset(_p('p1', name: '桌面端', content: 'Electron + Vue3', createdAt: 1700000000));
      await src.savePreset(_p('p2', name: '移动端', content: 'UniApp', createdAt: 1700000001));
      final json = src.buildSettingsExportJson();

      final dst = await makeTestAppState();
      final presets = dst.parseImportedPresets(json);
      final n = await dst.importPresets(presets);
      expect(n, 2);
      expect(dst.presets, hasLength(2));
      final byId = {for (final p in dst.presets) p.id: p};
      expect(byId['p1']!.name, '桌面端');
      expect(byId['p1']!.content, 'Electron + Vue3');
      expect(byId['p1']!.createdAt, 1700000000);
      expect(byId['p2']!.name, '移动端');
    });

    test('同 id 覆盖更新（不产生重复）', () async {
      final src = await makeTestAppState();
      await src.savePreset(_p('p1', name: '旧名', content: '旧内容'));
      final json = src.buildSettingsExportJson();

      final dst = await makeTestAppState();
      await dst.savePreset(_p('p1', name: '本地名', content: '本地内容'));
      await dst.importPresets(dst.parseImportedPresets(json));
      expect(dst.presets, hasLength(1));
      expect(dst.presets.single.name, '旧名', reason: '同 id 以导入数据覆盖');
      expect(dst.presets.single.content, '旧内容');
    });

    test('名称冲突自动去重命名（导入不中断）', () async {
      final src = await makeTestAppState();
      await src.savePreset(_p('p1', name: '桌面端', content: '导入内容'));
      final json = src.buildSettingsExportJson();

      final dst = await makeTestAppState();
      await dst.savePreset(_p('local-1', name: '桌面端', content: '本地内容'));
      await dst.importPresets(dst.parseImportedPresets(json));
      expect(dst.presets, hasLength(2));
      final names = dst.presets.map((p) => p.name).toList();
      expect(names, contains('桌面端 (2)'));
      expect(names.where((n) => n == '桌面端'), hasLength(1), reason: '唯一性保持');
    });

    test('旧版导出（无 presets 段）向后兼容', () {
      final state = appState;
      // 旧格式：仅 app/config_version/settings
      final legacy = jsonEncode({
        'app': 'prompt_optimizer',
        'config_version': 1,
        'exported_at': '2026-01-01T00:00:00.000',
        'settings': {'language': 'zh_CN'},
      });
      expect(state.parseImportedPresets(legacy), isEmpty);
    });

    test('非法预置词（超 300 字）整体拒绝', () {
      final state = appState;
      final bad = jsonEncode({
        'app': 'prompt_optimizer',
        'config_version': 1,
        'presets': [
          _p('p1').toJson(),
          _p('p2', name: '超长', content: '字' * 301).toJson(),
        ],
      });
      expect(
          () => state.parseImportedPresets(bad),
          throwsA(predicate((e) =>
              e is FormatException && e.message.contains('300'))));
    });

    test('非法结构（presets 非数组/条目非对象）拒绝', () {
      final state = appState;
      expect(
          () => state.parseImportedPresets(jsonEncode({
                'app': 'prompt_optimizer',
                'config_version': 1,
                'presets': 'oops',
              })),
          throwsA(isA<FormatException>()));
      expect(
          () => state.parseImportedPresets(jsonEncode({
                'app': 'prompt_optimizer',
                'config_version': 1,
                'presets': ['oops'],
              })),
          throwsA(isA<FormatException>()));
    });

    test('导出 → 导入全链路往返一致', () async {
      final src = await makeTestAppState();
      await src.savePreset(_p('p1', name: '桌面端', content: 'Electron\nVue3', createdAt: 1700000000));
      await src.savePreset(_p('p2', name: '移动端', content: 'UniApp', createdAt: 1700000001));
      final json = src.buildSettingsExportJson();

      final dst = await makeTestAppState();
      final merged = dst.parseImportedSettings(json);
      final presets = dst.parseImportedPresets(json);
      await dst.settings.update(merged);
      await dst.importPresets(presets);
      // 再导出，presets 段与源一致
      final round = jsonDecode(dst.buildSettingsExportJson()) as Map<String, dynamic>;
      final srcPresets = (jsonDecode(json) as Map<String, dynamic>)['presets'];
      expect(round['presets'], srcPresets);
    });
  });
}
