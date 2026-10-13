/// 模型规格库与服务商配置表测试（移植准确性 + 回退机制 + 思考参数映射）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/constants.dart';
import 'package:prompt_optimizer/core/model_specs.dart';

void main() {
  group('服务商配置表', () {
    test('内置九家服务商且顺序符合需求条目', () {
      expect(kProviderList, [
        'doubao', 'dashscope', 'qianfan', 'zhipu', 'kimi',
        'deepseek', 'stepfun', 'mimo', 'minimax',
      ]);
      expect(kProviderConfigs.length, 9);
      for (final p in kProviderList) {
        expect(kProviderConfigs, contains(p), reason: '$p 缺少配置');
      }
    });

    test('每家配置完整：默认地址/模型清单/默认模型', () {
      for (final p in kProviderList) {
        final c = kProviderConfigs[p]!;
        expect(c.defaultUrl, startsWith('https://'), reason: p);
        expect(c.models, isNotEmpty, reason: p);
        expect(c.models, contains(c.defaultModel), reason: p);
        expect(c.apiUrlOptions, isNotEmpty, reason: p);
        expect(c.apiUrlOptions.map((e) => e.url), contains(c.defaultUrl),
            reason: p);
      }
    });

    test('Coding Plan 双地址联动（百炼/Kimi/智谱/阶跃/MiMo）', () {
      for (final p in ['dashscope', 'kimi', 'zhipu', 'stepfun', 'mimo']) {
        final c = kProviderConfigs[p]!;
        expect(c.apiUrlOptions.length, greaterThanOrEqualTo(2), reason: p);
        expect(c.codingPlanName, isNotNull, reason: p);
      }
      // MiniMax 与按量同地址，仅一个选项
      expect(kProviderConfigs['minimax']!.apiUrlOptions.length, 1);
    });

    test('未知服务商返回 null / 空选项', () {
      expect(getProviderConfig('not-exist'), isNull);
      expect(getProviderUrlOptions('not-exist'), isEmpty);
      expect(providerSupportsCodingPlan('not-exist'), isFalse);
    });
  });

  group('模型规格库（移植基准官方值抽查）', () {
    test('dashscope qwen3.8-flash', () {
      final s = getModelSpec('dashscope', 'qwen3.8-flash');
      expect(s.contextWindow, 1000000);
      expect(s.maxInputTokens, 991808);
      expect(s.maxOutputTokens, 131072);
      expect(s.temperatureDefault, 1.0);
      expect(s.thinking, ThinkingSupport.toggle);
      expect(s.vision, isTrue);
      expect(s.isFallback, isFalse);
    });

    test('deepseek 思考可开关、输出默认 64K', () {
      final s = getModelSpec('deepseek', 'deepseek-flash');
      expect(s.contextWindow, 1048576);
      expect(s.maxOutputDefault, 65536);
      expect(s.thinking, ThinkingSupport.toggle);
    });

    test('kimi-for-coding 强制思考', () {
      final s = getModelSpec('kimi', 'kimi-for-coding');
      expect(s.thinking, ThinkingSupport.forcedOn);
    });

    test('zhipu glm-5.3 强制思考 / glm-4v-flash 无思考', () {
      expect(getModelSpec('zhipu', 'glm-5.3').thinking, ThinkingSupport.forcedOn);
      final v = getModelSpec('zhipu', 'glm-4v-flash');
      expect(v.thinking, ThinkingSupport.none);
      expect(v.vision, isTrue);
    });

    test('minimax M2.x 强制思考、M3 可开关', () {
      expect(getModelSpec('minimax', 'MiniMax-M2.7').thinking,
          ThinkingSupport.forcedOn);
      expect(
          getModelSpec('minimax', 'MiniMax-M3').thinking, ThinkingSupport.toggle);
    });

    test('stepfun 温度默认 0.5', () {
      expect(getModelSpec('stepfun', 'step-3.7-flash').temperatureDefault, 0.5);
    });
  });

  group('规格回退机制', () {
    test('未内置模型回退到服务商保守规格并标注 isFallback', () {
      final s = getModelSpec('deepseek', 'deepseek-2077');
      expect(s.isFallback, isTrue);
      expect(s.contextWindow, 1048576); // deepseek 服务商回退值
      expect(s.provider, 'deepseek');
      expect(s.model, 'deepseek-2077');
    });

    test('豆包/文心无逐模型规格，整家走服务商回退', () {
      final s = getModelSpec('doubao', 'doubao-seed-1-6-250615');
      expect(s.isFallback, isTrue);
      expect(s.contextWindow, greaterThan(0));
      final q = getModelSpec('qianfan', 'ernie-4.5-turbo-128k');
      expect(q.isFallback, isTrue);
    });

    test('未知服务商回退到通用规格', () {
      final s = getModelSpec('unknown-vendor', 'm');
      expect(s.isFallback, isTrue);
      expect(s.contextWindow, 128000);
    });
  });

  group('思考模式请求参数映射（对齐基准 build_thinking_payload）', () {
    test('开启：deepseek/zhipu/mimo 用 thinking.enabled', () {
      for (final p in ['deepseek', 'zhipu', 'mimo']) {
        expect(buildThinkingPayload(p, 'on'), {
          'thinking': {'type': 'enabled'}
        }, reason: p);
      }
    });

    test('开启：minimax 用 adaptive；kimi/stepfun 用 reasoning_effort', () {
      expect(buildThinkingPayload('minimax', 'on'), {
        'thinking': {'type': 'adaptive'}
      });
      expect(buildThinkingPayload('kimi', 'on'), {'reasoning_effort': 'high'});
      expect(buildThinkingPayload('stepfun', 'on'), {'reasoning_effort': 'high'});
    });

    test('关闭：deepseek 等 disabled；kimi/stepfun 无参数', () {
      expect(buildThinkingPayload('deepseek', 'off'), {
        'thinking': {'type': 'disabled'}
      });
      expect(buildThinkingPayload('kimi', 'off'), isEmpty);
      expect(buildThinkingPayload('stepfun', 'off'), isEmpty);
    });

    test('跟随默认：任何服务商都不附加参数', () {
      for (final p in kProviderList) {
        expect(buildThinkingPayload(p, 'default'), isEmpty, reason: p);
      }
    });

    test('未收录服务商（豆包/千帆）开启思考不附加参数', () {
      expect(buildThinkingPayload('doubao', 'on'), isEmpty);
      expect(buildThinkingPayload('qianfan', 'on'), isEmpty);
    });
  });
}
