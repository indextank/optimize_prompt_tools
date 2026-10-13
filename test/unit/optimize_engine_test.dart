/// 优化引擎测试：三模式 / 契约解析 / 重试与降级 / 思考参数注入 / 取消。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/errors.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/optimize_engine.dart';

import '../fakes.dart';

void main() {
  late FakeLlmClient llm;
  late OptimizeEngine engine;
  final svc = testService();

  setUp(() {
    llm = FakeLlmClient();
    engine = OptimizeEngine(client: llm);
  });

  group('输出详略（简单/完整模式）', () {
    test('简单模式：原样返回一段连贯文本（不解析 JSON、无评分）', () async {
      const simpleOut = '请根据图片中红色圈出的区域，修复所有存在的布局问题：所有文本元素与下拉框组件需补充规范的内边距和外边距……';
      llm.enqueueText(simpleOut);
      final r = await engine.optimize(svc, 'sk-test', '修复红圈布局问题',
          mode: OptimizeMode.quick, style: OutputStyle.simple);
      expect(r.result.isStructured, isFalse);
      expect(r.result.rawText, simpleOut);
      expect(r.result.scoreAfter, isNull, reason: '简单模式无评分');
      expect(r.result.toPlainText(), simpleOut);
      // 系统提示词为简单模式模板（禁止分段/JSON）
      final sys = llm.capturedRequests.single.messages.first.content;
      expect(sys, contains('简单模式'));
      expect(sys, isNot(contains('JSON 契约')));
    });

    test('简单模式规则：仅专业化重述，禁止角色定位', () async {
      llm.enqueueText('一段优化后正文');
      await engine.optimize(svc, 'sk-test', '原文', style: OutputStyle.simple);
      final sys = llm.capturedRequests.single.messages.first.content;
      expect(sys, contains('专业化重述'), reason: '简单模式应聚焦原始需求的专业化重述');
      expect(sys, contains('禁止输出任何角色定位'), reason: '必须显式禁止角色定位');
      expect(sys, isNot(contains('将角色要求')), reason: '不得再要求融入角色设定');
      // 输出不含角色定位结构
      llm.enqueueText('一段优化后正文');
      final r0 = await engine.optimize(svc, 'sk-test', '原文', style: OutputStyle.simple);
      expect(r0.result.isStructured, isFalse);
      expect(r0.result.role, isEmpty, reason: '简单模式结果不得含角色定位字段');
    });

    test('简单模式规则：多步骤必须阿拉伯数字编号列表', () async {
      llm.enqueueText('1. 第一步\n2. 第二步');
      await engine.optimize(svc, 'sk-test', '原文', style: OutputStyle.simple);
      final sys = llm.capturedRequests.single.messages.first.content;
      expect(sys, contains('逻辑依赖关系'), reason: '应先梳理步骤逻辑依赖');
      expect(sys, contains('阿拉伯数字编号列表'), reason: '多步骤必须用阿拉伯数字编号列表');
      expect(sys, contains('执行顺序'), reason: '须保证执行顺序符合业务流程');
      expect(sys, contains('边界清晰'), reason: '每步表述须完整无歧义');
      // 编号列表是步骤的唯一例外，其余分段/标记仍禁止
      expect(sys, contains('除上述步骤编号列表外'));
      // 输出原样透传（含编号列表）
      llm.enqueueText('1. 第一步\n2. 第二步');
      final r = await engine.optimize(svc, 'sk-test', '原文', style: OutputStyle.simple);
      expect(r.result.rawText, '1. 第一步\n2. 第二步');
      expect(r.result.isStructured, isFalse);
    });

    test('简单模式：剥离模型误输出的代码围栏', () async {
      llm.enqueueText('```text\n一段优化后的提示词正文\n```');
      final r = await engine.optimize(svc, 'sk-test', '原文',
          style: OutputStyle.simple);
      expect(r.result.rawText, '一段优化后的提示词正文');
    });

    test('简单模式：模型返回契约 JSON 也按纯文本处理（不做结构化解析）', () async {
      llm.enqueueText(kValidContractJson);
      final r = await engine.optimize(svc, 'sk-test', '原文',
          style: OutputStyle.simple);
      expect(r.result.isStructured, isFalse);
      expect(r.result.rawText, kValidContractJson);
    });

    test('完整模式：六段式契约结构化解析（回归）', () async {
      llm.enqueueText(kValidContractJson);
      final r = await engine.optimize(svc, 'sk-test', '帮我写爬虫',
          style: OutputStyle.full);
      expect(r.result.isStructured, isTrue);
      expect(r.result.role, '资深 Python 工程师');
    });

    test('提问式终稿同样支持简单模式', () async {
      const simpleOut = '结合问答后的一段连贯提示词';
      llm.enqueueText(simpleOut);
      final r = await engine.finalizeAsk(
          svc, 'sk-test', '原文', [const ClarifyQuestion(question: 'Q1', decides: 'D1')], ['A1'],
          style: OutputStyle.simple);
      expect(r.result.isStructured, isFalse);
      expect(r.result.rawText, simpleOut);
    });
  });

  group('快速/深度优化主流程', () {
    test('深度优化：解析六段式契约并返回元数据', () async {
      llm.enqueueText(kValidContractJson);
      final r = await engine.optimize(svc, 'sk-test', '帮我写爬虫',
          mode: OptimizeMode.deep, scene: kBuiltinScenes[1]);
      expect(r.result.isStructured, isTrue);
      expect(r.result.role, '资深 Python 工程师');
      expect(r.result.requirements, ['自动分页', '字段完整']);
      expect(r.result.scoreBefore, 62);
      expect(r.result.scoreAfter, 92);
      expect(r.result.diagnosis, hasLength(1));
      expect(r.totalTokens, 42);
      expect(r.elapsedMs, greaterThanOrEqualTo(0));
      // 系统提示词含场景指引与契约约束
      final req = llm.capturedRequests.single;
      expect(req.model, 'deepseek-flash');
      expect(req.messages.first.role, 'system');
      expect(req.messages.first.content, contains('编程任务'));
      expect(req.messages.first.content, contains('role'));
      expect(req.messages.last.content, '帮我写爬虫');
      // stream_options 请求用量
      expect(req.buildBody(stream: true)['stream_options'],
          {'include_usage': true});
    });

    test('快速优化：同一契约，提示词标注快速模式', () async {
      llm.enqueueText(kValidContractJson);
      await engine.optimize(svc, 'sk-test', '原文', mode: OptimizeMode.quick);
      expect(llm.capturedRequests.single.messages.first.content, contains('快速优化模式'));
    });

    test('流式进度回调累计文本', () async {
      llm.enqueueText(kValidContractJson);
      final progress = <String>[];
      await engine.optimize(svc, 'sk', '原文',
          onProgress: progress.add);
      expect(progress, isNotEmpty);
      expect(progress.last, kValidContractJson);
    });

    test('思考模式参数注入请求体（deepseek 开启）', () async {
      llm.enqueueText(kValidContractJson);
      await engine.optimize(
          svc.copyWith(thinkingMode: 'on'), 'sk', '原文');
      expect(llm.capturedRequests.single.extraBody, {
        'thinking': {'type': 'enabled'}
      });
    });

    test('跟随默认不附加思考参数', () async {
      llm.enqueueText(kValidContractJson);
      await engine.optimize(svc, 'sk', '原文');
      expect(llm.capturedRequests.single.extraBody, isEmpty);
    });
  });

  group('契约解析与降级', () {
    test('代码围栏包裹的 JSON 可解析', () {
      final r = OptimizeEngine.parseResultContract(
          '```json\n$kValidContractJson\n```');
      expect(r.role, '资深 Python 工程师');
    });

    test('前后杂讯容错', () {
      final r = OptimizeEngine.parseResultContract(
          '好的，这是结果：\n$kValidContractJson\n希望对你有帮助');
      expect(r.goal, contains('豆瓣'));
    });

    test('无 JSON 抛 FormatException', () {
      expect(() => OptimizeEngine.parseResultContract('没有 JSON'),
          throwsFormatException);
    });

    test('首次非法 JSON 自动重试一次后成功', () async {
      llm.enqueueText('这不是 JSON');
      llm.enqueueText(kValidContractJson);
      final r = await engine.optimize(svc, 'sk', '原文');
      expect(r.result.isStructured, isTrue);
      expect(llm.capturedRequests, hasLength(2));
      // 第二次请求带格式修正指令
      expect(llm.capturedRequests[1].messages.last.content, contains('JSON 契约'));
    });

    test('两次均非法则降级为非结构化文本，不抛异常', () async {
      llm.enqueueText('坏输出一');
      llm.enqueueText('坏输出二');
      final r = await engine.optimize(svc, 'sk', '原文');
      expect(r.result.isStructured, isFalse);
      expect(r.result.rawText, '坏输出二');
      expect(llm.capturedRequests, hasLength(2));
    });

    test('契约字段全空视为非法（触发重试与降级）', () async {
      llm.enqueueText('{}');
      llm.enqueueText('{"role": ""}');
      final r = await engine.optimize(svc, 'sk', '原文');
      expect(r.result.isStructured, isFalse);
    });

    test('评分越界在解析层被钳制', () {
      final r = OptimizeEngine.parseResultContract(
          '{"role":"x","score_after":300}');
      expect(r.scoreAfter, 100);
    });

    test('嵌套引号与转义大括号不破坏 JSON 提取', () {
      const inner = '{"role":"含 } 与 \\" 的文本","goal":"g"}';
      final r = OptimizeEngine.parseResultContract('前缀 $inner 后缀');
      expect(r.role, '含 } 与 " 的文本');
    });
  });

  group('输入校验', () {
    test('空输入抛 LlmException', () async {
      expect(() => engine.optimize(svc, 'sk', '   '),
          throwsA(isA<LlmException>()));
      expect(() => engine.askQuestions(svc, 'sk', ''), throwsA(isA<LlmException>()));
    });

    test('超过长度上限抛异常且不发起请求', () async {
      final long = '长' * (OptimizeEngine.maxInputChars + 1);
      await expectLater(engine.optimize(svc, 'sk', long),
          throwsA(isA<LlmException>()));
      expect(llm.capturedRequests, isEmpty);
      // 边界：恰好上限可正常调用
      llm.enqueueText(kValidContractJson);
      await engine.optimize(svc, 'sk', '长' * OptimizeEngine.maxInputChars);
      expect(llm.capturedRequests, hasLength(1));
    });
  });

  group('提问式优化', () {
    test('第一轮解析 5-8 个问题', () async {
      llm.enqueueText(kValidQuestionsJson);
      final qs = await engine.askQuestions(svc, 'sk', '帮我写爬虫');
      expect(qs, hasLength(5));
      expect(qs.first.question, contains('反爬'));
      expect(qs.first.decides, isNotEmpty);
    });

    test('问题数量超范围触发重试', () async {
      llm.enqueueText('{"questions":[{"question":"q","decides":"d"}]}'); // 仅 1 个
      llm.enqueueText(kValidQuestionsJson);
      final qs = await engine.askQuestions(svc, 'sk', '原文');
      expect(qs, hasLength(5));
      expect(llm.capturedRequests, hasLength(2));
    });

    test('两次均非法则抛 FormatException', () async {
      llm.enqueueText('{}');
      llm.enqueueText('{"questions":[]}');
      expect(() => engine.askQuestions(svc, 'sk', '原文'),
          throwsFormatException);
    });

    test('终轮：答案组装进提示词，跳过项标注', () async {
      llm.enqueueText(kValidContractJson);
      final qs = OptimizeEngine.parseQuestionsContract(kValidQuestionsJson);
      final answers = ['有反爬', null, '本地', '', '全字段'];
      final r = await engine.finalizeAsk(svc, 'sk', '帮我写爬虫', qs, answers);
      expect(r.result.isStructured, isTrue);
      final sent = llm.capturedRequests.single.messages.last.content;
      expect(sent, contains('Q1：目标站点有反爬吗？'));
      expect(sent, contains('A1：有反爬'));
      expect(sent, contains('A2：跳过')); // null 与空串都标注跳过
      expect(sent, contains('A4：跳过'));
    });

    test('终轮：答案数量不匹配抛 ArgumentError', () async {
      expect(
          () => engine.finalizeAsk(svc, 'sk', '原文', const [], ['a']),
          throwsArgumentError);
    });
  });

  group('段落重写与取消', () {
    test('rewriteSection 返回重写文本并携带上下文', () async {
      llm.enqueueText('重写后的段落内容');
      final cur = OptimizeEngine.parseResultContract(kValidContractJson);
      final out = await engine.rewriteSection(
          svc, 'sk', cur, 'acceptance', '验收标准', '旧内容');
      expect(out, '重写后的段落内容');
      final sys = llm.capturedRequests.single.messages.first.content;
      expect(sys, contains('验收标准'));
      expect(sys, contains('资深 Python 工程师')); // 完整提示词上下文
    });

    test('rewriteSection 空结果抛异常', () async {
      llm.enqueueText('   ');
      expect(
          () => engine.rewriteSection(
              svc, 'sk', const OptimizeResult(role: 'x'), 'role', '角色定位', '旧'),
          throwsA(isA<LlmException>()));
    });

    test('取消令牌中断流式调用', () async {
      llm.chunkDelay = const Duration(milliseconds: 3); // 放慢流式，确保取消落在进行中
      llm.enqueueText(kValidContractJson * 5); // 长输出
      final state = await makeTestAppState(llm: llm);
      await state.saveService(testService(), apiKey: 'sk');
      state.session.rawText = '原文';
      final fut = state.startOptimize();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      state.cancelOptimize();
      final rec = await fut;
      expect(rec, isNull);
      expect(state.session.optimizing, isFalse);
      expect(state.session.errorMessage, isNull); // 取消不算错误
    });
  });
}
