/// 应用状态层测试（集成粒度：真实存储 + 内存密钥库 + 假 LLM）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/errors.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/key_store.dart';
import 'package:prompt_optimizer/state/app_state.dart';

import '../fakes.dart';

void main() {
  late FakeLlmClient llm;
  late AppState state;
  late MemoryKeyStore keyStore;

  setUp(() async {
    llm = FakeLlmClient();
    keyStore = MemoryKeyStore();
    state = await makeTestAppState(llm: llm, keyStore: keyStore);
    state.session.outputStyle = OutputStyle.full; // 本文件用例均基于六段式契约
  });

  ServiceConfig svcOf(String id, {String provider = 'deepseek', bool isDefault = false}) =>
      testService(id: id, provider: provider, isDefault: isDefault);

  group('服务配置管理', () {
    test('首个服务自动设为默认', () async {
      await state.saveService(svcOf('a'), apiKey: 'sk-a');
      expect(state.services.single.isDefault, isTrue);
      expect(state.settings.settings.defaultServiceId, 'a');
    });

    test('密钥写入安全存储且可按 keyRef 读取', () async {
      await state.saveService(svcOf('a'), apiKey: 'sk-secret');
      final svc = state.services.single;
      expect(svc.keyRef, isNotEmpty);
      expect(await keyStore.read(svc.keyRef), 'sk-secret');
    });

    test('删除服务清理密钥、默认标记、并行选择与会话引用', () async {
      await state.saveService(svcOf('a'), apiKey: 'k');
      await state.saveService(svcOf('b', provider: 'kimi'), apiKey: 'k2');
      await state.settings.update(
          state.settings.settings.copyWith(parallelEnabled: true));
      state.session.parallelServiceId = 'b';
      final svcB = state.services.firstWhere((s) => s.id == 'b');
      await state.deleteService(svcB);
      expect(state.services, hasLength(1));
      expect(await keyStore.read(svcB.keyRef), isNull);
      expect(state.session.parallelServiceId, isNull, reason: '删除服务应清空会话并行选择');
      expect(state.session.sessionServiceId, isEmpty);
    });

    test('默认服务唯一且全局切换生效', () async {
      await state.saveService(svcOf('a', isDefault: true));
      await state.saveService(svcOf('b', provider: 'kimi'));
      await state.setDefaultService('b');
      expect(state.defaultService!.id, 'b');
      expect(state.services.where((s) => s.isDefault), hasLength(1));
    });

    test('会话级切换优先于全局默认', () async {
      await state.saveService(svcOf('a', isDefault: true));
      await state.saveService(svcOf('b', provider: 'kimi'));
      expect(state.effectiveService!.id, 'a');
      state.setSessionService('b');
      expect(state.effectiveService!.id, 'b');
    });
  });

  group('优化主流程', () {
    setUp(() async {
      await state.saveService(svcOf('a'), apiKey: 'sk');
      state.session.rawText = '帮我写个爬虫';
      state.session.mode = OptimizeMode.deep;
      state.session.outputStyle = OutputStyle.full; // 结构化契约用例显式指定完整模式 // 深度流程显式指定（默认为快速）
    });

    test('深度优化：结果落库、评分记录、会话就绪', () async {
      llm.enqueueText(kValidContractJson);
      final rec = await state.startOptimize();
      expect(rec, isNotNull);
      expect(rec!.providers, ['a']);
      expect(rec.scoreAfter, 92);
      expect(state.session.currentRecord!.id, rec.id);
      final history = await state.storage.loadRecords();
      expect(history.single.id, rec.id);
    });

    test('未配置服务时不可优化', () async {
      final empty = await makeTestAppState(llm: FakeLlmClient());
      empty.session.rawText = '文本';
      expect(empty.canOptimize, isFalse);
      expect(await empty.startOptimize(), isNull);
    });

    test('空输入与超长输入不可优化', () async {
      state.session.rawText = '   ';
      expect(state.canOptimize, isFalse);
      state.session.rawText = '长' * 10001;
      expect(state.canOptimize, isFalse);
    });

    test('调用失败写入可读错误信息（鉴权失败）', () async {
      llm.enqueueError(
          const LlmException(LlmErrorKind.unauthorized, '401', statusCode: 401));
      final rec = await state.startOptimize();
      expect(rec, isNull);
      expect(state.session.errorMessage, contains('API KEY'));
    });

    test('未知异常兜底为通用错误文案', () async {
      llm.enqueueError(StateError('unexpected'));
      final rec = await state.startOptimize();
      expect(rec, isNull);
      expect(state.session.errorMessage, contains('优化失败'));
    });

    test('提问式：先问题后终稿，全程落库', () async {
      state.session.mode = OptimizeMode.ask;
      llm.enqueueText(kValidQuestionsJson);
      final r1 = await state.startOptimize();
      expect(r1, isNull); // 尚未生成结果
      expect(state.session.askAnswering, isTrue);
      expect(state.session.questions, hasLength(5));

      state.session.answers[0] = '有反爬';
      llm.enqueueText(kValidContractJson);
      final rec = await state.finalizeAsk();
      expect(rec, isNotNull);
      expect(rec!.mode, OptimizeMode.ask);
      expect(state.session.askAnswering, isFalse);
      // 终稿请求包含问答
      final last = llm.capturedRequests.last.messages.last.content;
      expect(last, contains('A1：有反爬'));
    });

    test('并行优化：默认+对比模型，全部成功落库', () async {
      await state.saveService(svcOf('b', provider: 'kimi'), apiKey: 'k2');
      await state.settings.update(
          state.settings.settings.copyWith(parallelEnabled: true));
      state.session.parallelServiceId = 'b';
      llm.enqueueText(kValidContractJson);
      llm.enqueueText(kValidContractJson);
      final rec = await state.startOptimize();
      expect(rec, isNotNull);
      expect(rec!.providers, hasLength(2));
      expect(state.session.parallelStates, hasLength(2));
      expect(state.session.parallelStates.values.every((s) => s.success), isTrue);
    });

    test('并行对比：两路请求真正同时发起（非排队串行）', () async {
      llm.chunkDelay = const Duration(milliseconds: 5); // 每路约 500ms 完成
      llm.enqueueText('甲模型输出' * 100);
      llm.enqueueText('乙模型输出' * 100);
      await state.saveService(svcOf('b', provider: 'kimi'), apiKey: 'sk-b');
      await state.settings.update(
          state.settings.settings.copyWith(parallelEnabled: true));
      state.session.parallelServiceId = 'b';
      state.session.rawText = '原文';
      final fut = state.startOptimize();
      // 100ms 时若为串行，第二路尚未发起（第一路需 ~500ms）
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(llm.capturedRequests, hasLength(2),
          reason: '并行对比的两路请求应同时发起以加快整体速度');
      expect(state.session.parallelStates.values.where((s) => s.success).length,
          lessThan(2),
          reason: '此时两路均应仍在进行中（证明请求同时发出而非已完成）');
      final rec = await fut;
      expect(rec, isNotNull);
      expect(state.session.parallelStates.values.every((s) => s.success), isTrue);
    });

    test('简单模式并行对比：两路均输出简单模式格式（修复并行错出完整格式）', () async {
      await state.saveService(svcOf('b', provider: 'kimi'), apiKey: 'sk-b');
      await state.settings.update(
          state.settings.settings.copyWith(parallelEnabled: true));
      state.session.parallelServiceId = 'b';
      state.session.outputStyle = OutputStyle.simple; // 简单模式
      llm.enqueueText('模型甲的一段连贯提示词');
      llm.enqueueText('模型乙的一段连贯提示词');
      final rec = await state.startOptimize();
      expect(rec, isNotNull);
      expect(state.session.parallelStates, hasLength(2));
      for (final st in state.session.parallelStates.values) {
        expect(st.success, isTrue);
        expect(st.runResult!.result.isStructured, isFalse,
            reason: '简单模式下并行各路必须输出非结构化整段文本');
      }
      // 两路请求的系统提示词均为简单模式模板
      for (final req in llm.capturedRequests) {
        expect(req.messages.first.content, contains('简单模式'));
        expect(req.messages.first.content, isNot(contains('JSON 契约')));
      }
    });

    test('并行：单家失败仍落库成功方结果', () async {
      await state.saveService(svcOf('b', provider: 'kimi'), apiKey: 'k2');
      await state.settings.update(
          state.settings.settings.copyWith(parallelEnabled: true));
      state.session.parallelServiceId = 'b';
      llm.enqueueText(kValidContractJson);
      llm.enqueueError(
          const LlmException(LlmErrorKind.unauthorized, '401', statusCode: 401));
      final rec = await state.startOptimize();
      expect(rec, isNotNull);
      final states = state.session.parallelStates.values.toList();
      expect(states.where((s) => s.success), hasLength(1));
      expect(states.where((s) => s.error != null), hasLength(1));
    });
  });

  group('复查编辑', () {
    setUp(() async {
      await state.saveService(svcOf('a'), apiKey: 'sk');
      state.session.rawText = '原文';
      state.session.mode = OptimizeMode.deep;
      state.session.outputStyle = OutputStyle.full; // 结构化契约用例显式指定完整模式 // 深度流程显式指定（默认为快速）
      llm.enqueueText(kValidContractJson);
      await state.startOptimize();
    });

    test('保存编辑追加新版本且版本链完整', () async {
      final edited = state.session.currentRecord!.latest.result
          .copyWithSections(role: '改后的角色');
      final updated = await state.saveEditedResult(edited);
      expect(updated!.versions, hasLength(2));
      expect(updated.latest.v, 2);
      expect(updated.latest.edited, isTrue);
      expect(updated.latest.result.role, '改后的角色');
      // 落库一致
      final history = await state.storage.loadRecords();
      expect(history.single.versions, hasLength(2));
    });

    test('回滚到历史版本（追加式）', () async {
      final r1 = state.session.currentRecord!.latest.result;
      await state.saveEditedResult(r1.copyWithSections(goal: 'v2 目标'));
      final rolled = await state.rollbackToVersion(1);
      expect(rolled!.latest.v, 3);
      expect(rolled.latest.result.goal, r1.goal);
    });

    test('回滚不存在版本返回 null', () async {
      expect(await state.rollbackToVersion(99), isNull);
    });

    test('AI 重写段落', () async {
      llm.enqueueText('新的验收标准内容');
      final out =
          await state.rewriteSection('acceptance', '验收标准', '旧内容');
      expect(out, '新的验收标准内容');
    });
  });

  group('配置导入导出', () {
    test('导出不含密钥', () async {
      await state.saveService(svcOf('a'), apiKey: 'sk-leak-guard');
      final json = state.exportConfigJson();
      expect(json, isNot(contains('sk-leak-guard')));
      expect(json, isNot(contains('key_ref')));
      final decoded = jsonDecode(json);
      expect(decoded['services'], hasLength(1));
      expect(decoded['settings'], isNotNull);
    });

    test('导入跳过未知服务商，导入后无密钥需重录', () async {
      final json = jsonEncode({
        'version': 1,
        'services': [
          {'provider': 'deepseek', 'api_url': 'https://api.deepseek.com', 'model': 'deepseek-flash'},
          {'provider': 'unknown-vendor', 'api_url': 'https://x.com', 'model': 'm'},
        ],
      });
      final n = await state.importConfigJson(json);
      expect(n, 1);
      expect(state.services.single.provider, 'deepseek');
      expect(state.services.single.keyRef, isEmpty);
    });

    test('导入非法 JSON 抛 FormatException', () {
      expect(() => state.importConfigJson('{"x":1}'), throwsFormatException);
    });
  });

  group('历史', () {
    test('打开记录回填会话', () async {
      await state.saveService(svcOf('a'), apiKey: 'sk');
      state.session.rawText = '原文A';
      state.session.mode = OptimizeMode.deep;
      llm.enqueueText(kValidContractJson);
      final rec = (await state.startOptimize())!;
      state.session.rawText = '';
      await state.openRecord(rec);
      expect(state.session.rawText, '原文A');
      expect(state.session.currentRecord!.id, rec.id);
      expect(state.session.mode, OptimizeMode.deep);
    });

    test('清空历史', () async {
      await state.saveService(svcOf('a'), apiKey: 'sk');
      state.session.rawText = '原文';
      state.session.mode = OptimizeMode.deep;
      llm.enqueueText(kValidContractJson);
      await state.startOptimize();
      expect(await state.storage.recordCount(), 1);
      await state.clearHistory();
      expect(await state.storage.recordCount(), 0);
    });
  });
}
