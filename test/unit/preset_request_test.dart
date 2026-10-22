/// 「选择预置词后组装 AI 请求」核心逻辑测试（第 6/7 步验收）：
/// - 未选择预置词：请求与现状一致（system 无技术背景段）
/// - 选择预置词：背景内容以独立段注入 system（含"非优化对象"边界声明），
///   且绝不拼入 user 消息（待优化原始提示词）
/// - 预置词内容为空：不注入，等同未选择
/// - 端到端：startOptimize 后 AI 实际收到的请求含背景且原始提示词独立
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/optimize_engine.dart';

import '../fakes.dart';

CodingPreset presetOf({String content = 'Windows 11 桌面端，Electron + Vue3，TypeScript'}) =>
    CodingPreset(
        id: 'p1', name: '桌面端', content: content, createdAt: 1700000000);

void main() {
  final scene = kBuiltinScenes[1]; // AI 编程
  const raw = '帮我写一个爬虫';

  group('assembleOptimizeRequest 组装规则', () {
    test('未选择预置词：system 无技术背景，请求与现状一致', () {
      final plan = OptimizeEngine.assembleOptimizeRequest(
        scene: scene,
        mode: OptimizeMode.deep,
        style: OutputStyle.full,
        rawText: raw,
      );
      expect(plan.system, isNot(contains('技术背景')));
      expect(plan.system, isNot(contains('Electron')));
      expect(plan.userMessages, hasLength(1));
      expect(plan.userMessages.single.role, 'user');
      expect(plan.userMessages.single.content, raw);
    });

    test('选择预置词：背景独立注入 system，含"非优化对象"边界声明', () {
      final plan = OptimizeEngine.assembleOptimizeRequest(
        scene: scene,
        mode: OptimizeMode.deep,
        style: OutputStyle.full,
        rawText: raw,
        preset: presetOf(),
      );
      // 背景内容在 system 中
      expect(plan.system, contains('Electron + Vue3，TypeScript'));
      expect(plan.system, contains('技术背景'));
      // 明确声明：背景不是优化对象、禁止拼进优化结果
      expect(plan.system, contains('严禁将其视为需要优化的内容'));
      expect(plan.system, contains('严禁拼接进优化结果'));
      // user 消息仅为待优化原文，预置词内容不得混入
      expect(plan.userMessages, hasLength(1));
      expect(plan.userMessages.single.role, 'user');
      expect(plan.userMessages.single.content, raw);
      expect(plan.userMessages.single.content,
          isNot(contains('Electron')),
          reason: '预置词内容严禁拼接为待优化提示词的一部分');
    });

    test('简单模式同样注入背景（style 不影响背景注入）', () {
      final plan = OptimizeEngine.assembleOptimizeRequest(
        scene: scene,
        mode: OptimizeMode.quick,
        style: OutputStyle.simple,
        rawText: raw,
        preset: presetOf(content: 'UniApp + Vue3 移动端'),
      );
      expect(plan.system, contains('UniApp + Vue3 移动端'));
      expect(plan.system, contains('技术背景'));
    });

    test('预置词内容为空：不注入，等同未选择', () {
      final plan = OptimizeEngine.assembleOptimizeRequest(
        scene: scene,
        mode: OptimizeMode.deep,
        style: OutputStyle.full,
        rawText: raw,
        preset: presetOf(content: '   '),
      );
      expect(plan.system, isNot(contains('技术背景')));
      expect(plan.userMessages.single.content, raw);
    });
  });

  group('buildTechBackground 纯函数', () {
    test('null / 空内容 → null；非空 → 含边界声明的背景段', () {
      expect(OptimizeEngine.buildTechBackground(null), isNull);
      expect(OptimizeEngine.buildTechBackground(presetOf(content: '')), isNull);
      final bg = OptimizeEngine.buildTechBackground(presetOf(content: 'Flutter'));
      expect(bg, contains('Flutter'));
      expect(bg, contains('严禁'));
    });
  });

  group('端到端：startOptimize 后 AI 收到的请求', () {
    test('选择预置词后：system 含背景、user 仅原文（明确分离）', () async {
      final llm = FakeLlmClient()..enqueueText(kValidContractJson);
      final state = await makeTestAppState(llm: llm);
      final svc = testService(id: 'a', model: 'm');
      await state.saveService(svc, apiKey: 'k');
      state.session.rawText = raw;
      state.session.sceneId = 'ai_coding';
      state.session.presetId = null;
      // 注入预置词
      await state.savePreset(presetOf(content: 'HarmonyOS NEXT，ArkTS'));
      state.session.presetId = 'p1';

      await state.startOptimize();

      final req = llm.capturedRequests.single;
      final system = req.messages
          .firstWhere((m) => m.role == 'system')
          .content;
      final userMsgs =
          req.messages.where((m) => m.role == 'user').map((m) => m.content);
      expect(system, contains('HarmonyOS NEXT，ArkTS'));
      expect(system, contains('技术背景'));
      for (final u in userMsgs) {
        expect(u, isNot(contains('HarmonyOS NEXT')),
            reason: '预置词内容不得拼入待优化提示词（user 消息）');
      }
      expect(userMsgs.first, raw);
    });

    test('未选择预置词：请求不含任何背景（与现状一致）', () async {
      final llm = FakeLlmClient()..enqueueText(kValidContractJson);
      final state = await makeTestAppState(llm: llm);
      final svc = testService(id: 'a', model: 'm');
      await state.saveService(svc, apiKey: 'k');
      state.session.rawText = raw;
      state.session.sceneId = 'ai_coding';
      state.session.presetId = null;
      await state.savePreset(presetOf(content: 'HarmonyOS NEXT，ArkTS'));

      await state.startOptimize();

      final req = llm.capturedRequests.single;
      final system = req.messages
          .firstWhere((m) => m.role == 'system')
          .content;
      expect(system, isNot(contains('HarmonyOS NEXT')));
      expect(system, isNot(contains('技术背景')));
    });
  });
}
