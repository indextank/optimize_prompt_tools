/// 核心数据模型测试（序列化回环 / 契约容错 / 导出隔离 / 六段式渲染）
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';

void main() {
  group('ServiceConfig', () {
    test('JSON 序列化回环', () {
      final s = ServiceConfig(
        id: 'a1',
        provider: 'deepseek',
        apiUrl: 'https://api.deepseek.com',
        keyRef: 'a1',
        model: 'deepseek-flash',
        temperature: 0.7,
        maxInputTokens: 1048576,
        maxOutputTokens: 65536,
        thinkingMode: 'on',
        imageInput: true,
        isDefault: true,
        createdAt: 1759700000,
      );
      final back = ServiceConfig.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.provider, 'deepseek');
      expect(back.temperature, 0.7);
      expect(back.thinkingMode, 'on');
      expect(back.imageInput, isTrue);
      expect(back.isDefault, isTrue);
    });

    test('导出 JSON 不含密钥与密钥引用', () {
      final s = testSvc();
      final exp = s.toExportJson();
      expect(exp.keys, isNot(contains('key_ref')));
      expect(exp.keys, isNot(contains('api_key')));
      expect(exp.keys, isNot(contains('id')));
    });

    test('fromJson 缺失字段给默认值', () {
      final s = ServiceConfig.fromJson({'provider': 'kimi'});
      expect(s.model, '');
      expect(s.temperature, 1.0);
      expect(s.thinkingMode, 'default');
    });
  });

  group('OptimizeResult 契约容错', () {
    test('缺失字段不崩溃并给默认值', () {
      final r = OptimizeResult.fromJson({'role': '工程师'});
      expect(r.role, '工程师');
      expect(r.requirements, isEmpty);
      expect(r.scoreAfter, isNull);
    });

    test('评分越界被钳制到 0-100', () {
      final r = OptimizeResult.fromJson({'score_before': -5, 'score_after': 188});
      expect(r.scoreBefore, 0);
      expect(r.scoreAfter, 100);
    });

    test('评分非数字时为 null', () {
      final r = OptimizeResult.fromJson({'score_after': 'good'});
      expect(r.scoreAfter, isNull);
    });

    test('诊断项解析与固定状态', () {
      final r = OptimizeResult.fromJson({
        'diagnosis': [
          {'item': 'a', 'status': 'fixed'},
          {'item': 'b', 'status': 'need_confirm', 'before': 'x'},
        ]
      });
      expect(r.diagnosis, hasLength(2));
      expect(r.diagnosis[0].isFixed, isTrue);
      expect(r.diagnosis[1].isFixed, isFalse);
    });

    test('非结构化降级构造', () {
      final r = OptimizeResult.unstructured('纯文本结果', scoreBefore: 50);
      expect(r.isStructured, isFalse);
      expect(r.toPlainText(), '纯文本结果');
      expect(r.hasContent, isTrue);
    });

    test('空结果 hasContent=false', () {
      expect(const OptimizeResult().hasContent, isFalse);
      expect(OptimizeResult.unstructured('  ').hasContent, isFalse);
    });
  });

  group('六段式渲染', () {
    test('按序输出六段，列表编号，空段省略', () {
      final r = OptimizeResult(
        role: '角色',
        goal: '目标',
        requirements: const ['要求一', '要求二'],
        constraints: const [],
        outputFormat: '格式',
        acceptance: const ['标准一'],
      );
      final t = r.toPlainText();
      expect(t, contains('【角色定位】\n角色'));
      expect(t, contains('【任务目标】'));
      expect(t, contains('1. 要求一'));
      expect(t, contains('2. 要求二'));
      expect(t, isNot(contains('【约束条件】'))); // 空段省略
      expect(t, contains('【输出格式】'));
      expect(t, contains('【验收标准】'));
      // 段落顺序
      expect(t.indexOf('角色定位'), lessThan(t.indexOf('任务目标')));
      expect(t.indexOf('任务目标'), lessThan(t.indexOf('具体要求')));
      expect(t.indexOf('具体要求'), lessThan(t.indexOf('输出格式')));
    });
  });

  group('OptimizeRecord 版本链', () {
    test('JSON 回环 + latest 取最高版本', () {
      final rec = OptimizeRecord(
        id: 'r1',
        scene: 'ai_coding',
        mode: OptimizeMode.deep,
        rawText: '原文',
        versions: [
          OptimizeVersion(
              v: 1,
              result: const OptimizeResult(role: 'v1'),
              createdAt: 1),
          OptimizeVersion(
              v: 3, result: const OptimizeResult(role: 'v3'), edited: true, createdAt: 3),
          OptimizeVersion(
              v: 2, result: const OptimizeResult(role: 'v2'), createdAt: 2),
        ],
        providers: const ['deepseek'],
        scoreBefore: 60,
        scoreAfter: 90,
        elapsedMs: 1200,
        tokens: 999,
        createdAt: 1759700000,
      );
      final back = OptimizeRecord.fromJson(
          jsonDecode(jsonEncode(rec.toJson())));
      expect(back.latest.v, 3);
      expect(back.latest.result.role, 'v3');
      expect(back.latest.edited, isTrue);
      expect(back.mode, OptimizeMode.deep);
      expect(back.tokens, 999);
    });

    test('mode 解析容错', () {
      expect(OptimizeMode.parse('quick'), OptimizeMode.quick);
      expect(OptimizeMode.parse('whatever'), OptimizeMode.deep);
    });
  });

  group('内置场景模板', () {
    test('8 类内置场景且 id 唯一', () {
      expect(kBuiltinScenes, hasLength(8));
      final ids = kBuiltinScenes.map((e) => e.id).toSet();
      expect(ids, hasLength(8));
      expect(ids, containsAll(
          ['general', 'ai_coding', 'bug_fix', 'writing', 'translate', 'draw', 'data_analysis', 'prd']));
    });
  });
}

ServiceConfig testSvc() => const ServiceConfig(
      id: 'x',
      provider: 'kimi',
      apiUrl: 'https://api.kimi.com/coding/v1',
      keyRef: 'secure://x',
      model: 'k3',
      isDefault: true,
    );
