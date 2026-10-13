/// 导出服务测试：三格式内容 / 文件名模板 / 保存流程 / 取消。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/services/export_service.dart';

import '../fakes.dart';

void main() {
  late FakeFileSaver saver;
  late ExportService exporter;

  final record = OptimizeRecord(
    id: 'r1',
    scene: 'ai_coding',
    mode: OptimizeMode.deep,
    rawText: '帮我写个爬虫',
    versions: [
      OptimizeVersion(
        v: 1,
        result: const OptimizeResult(
          role: '资深工程师',
          goal: '目标',
          requirements: ['要求一'],
          constraints: ['约束一'],
          outputFormat: '格式',
          acceptance: ['标准一'],
          scoreBefore: 62,
          scoreAfter: 92,
          diagnosis: [
            DiagnosisItem(item: '角色', status: 'fixed', before: '缺失', action: '已补充'),
            DiagnosisItem(item: '确认项', status: 'need_confirm', action: '建议确认'),
          ],
        ),
        createdAt: 1,
      ),
    ],
    providers: const ['deepseek'],
    scoreBefore: 62,
    scoreAfter: 92,
    createdAt: 1759700000,
  );

  setUp(() {
    saver = FakeFileSaver();
    exporter = ExportService(fileSaver: saver);
  });

  test('Markdown 含六段标题、元信息与诊断附录', () {
    final md = exporter.buildContent(record, ExportFormat.markdown);
    for (final h in ['角色定位', '任务目标', '具体要求', '约束条件', '输出格式', '验收标准']) {
      expect(md, contains('## $h'), reason: h);
    }
    expect(md, contains('## 原始输入'));
    expect(md, contains('帮我写个爬虫'));
    expect(md, contains('62 → 92'));
    expect(md, contains('[已修复] 角色'));
    expect(md, contains('[待确认] 确认项'));
  });

  test('非结构化结果导出为「优化结果」单节', () {
    final rec2 = OptimizeRecord(
      id: 'r2',
      scene: 'general',
      mode: OptimizeMode.quick,
      rawText: '原文',
      versions: [
        OptimizeVersion(v: 1, result: OptimizeResult.unstructured('纯文本输出'))
      ],
      providers: const ['kimi'],
      createdAt: 1759700000,
    );
    final md = exporter.buildContent(rec2, ExportFormat.markdown);
    expect(md, contains('## 优化结果'));
    expect(md, contains('纯文本输出'));
    expect(md, isNot(contains('## 角色定位')));
  });

  test('TXT 为六段式纯文本', () {
    final txt = exporter.buildContent(record, ExportFormat.txt);
    expect(txt, contains('【角色定位】'));
    expect(txt, contains('1. 要求一'));
  });

  test('JSON 含完整结构与诊断', () {
    final j = jsonDecode(exporter.buildContent(record, ExportFormat.json));
    expect(j['scene'], 'ai_coding');
    expect(j['versions'][0]['result']['diagnosis'], hasLength(2));
    expect(j['versions'][0]['result']['role'], '资深工程师');
  });

  test('文件名模板：提示词_{场景}_{yyyyMMdd-HHmm}', () {
    final name = ExportService.suggestedFilename(record,
        at: DateTime(2026, 10, 6, 15, 30));
    expect(name, '提示词_ai_coding_20261006-1530');
  });

  test('导出走 FileSaver 并拼接扩展名', () async {
    final path = await exporter.export(record, ExportFormat.markdown);
    expect(saver.lastExt, 'md');
    expect(saver.lastName, startsWith('提示词_ai_coding_'));
    expect(path, contains('.md'));
    // 内容是 UTF-8 编码的 markdown
    expect(utf8.decode(saver.lastBytes!), contains('## 角色定位'));
  });

  test('用户取消返回 null', () async {
    saver.nextPath = null;
    expect(await exporter.export(record, ExportFormat.txt), isNull);
  });
}
