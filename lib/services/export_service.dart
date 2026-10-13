/// 导出服务：Markdown / TXT / JSON 生成与文件保存。
///
/// 文件保存通过注入的 [FileSaver] 完成：native 端用系统原生文件对话框
/// （file_selector，用户硬性要求），web 端触发浏览器下载，测试端用假实现。
library;

import 'dart:convert';

import 'package:intl/intl.dart';

import '../core/models.dart';

/// 导出格式
enum ExportFormat { markdown, txt, json }

extension ExportFormatExt on ExportFormat {
  String get ext => switch (this) {
        ExportFormat.markdown => 'md',
        ExportFormat.txt => 'txt',
        ExportFormat.json => 'json',
      };

  String get label => switch (this) {
        ExportFormat.markdown => 'Markdown',
        ExportFormat.txt => 'TXT',
        ExportFormat.json => 'JSON',
      };
}

/// 用户选择的本地文件（导入用）
class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}

/// 文件保存/选取抽象
abstract class FileSaver {
  /// 保存文件；返回保存路径（用户取消返回 null）
  Future<String?> save({
    required String suggestedName,
    required String ext,
    required List<int> bytes,
  });

  /// 打开本地文件选择框（限 [extensions] 所列扩展名）；
  /// 返回所选文件（文件名+字节），用户取消返回 null
  Future<PickedFile?> pickFile({required List<String> extensions});
}

class ExportService {
  ExportService({required FileSaver fileSaver}) : _fileSaver = fileSaver;

  final FileSaver _fileSaver;

  /// 文件名模板：提示词_{场景}_{yyyyMMdd-HHmm}
  static String suggestedFilename(OptimizeRecord record, {DateTime? at}) {
    final t = at ?? DateTime.fromMillisecondsSinceEpoch(record.createdAt * 1000);
    return '提示词_${record.scene}_${DateFormat('yyyyMMdd-HHmm').format(t)}';
  }

  /// 生成导出内容
  String buildContent(OptimizeRecord record, ExportFormat format) {
    switch (format) {
      case ExportFormat.markdown:
        return toMarkdown(record);
      case ExportFormat.txt:
        return record.latest.result.toPlainText();
      case ExportFormat.json:
        return const JsonEncoder.withIndent('  ').convert(record.toJson());
    }
  }

  /// 仅导出优化结果正文（复查编辑页「导出 Markdown」）：不含标题、元信息与原始输入
  Future<String?> exportResultOnly(OptimizeResult result, OptimizeRecord record) {
    return _fileSaver.save(
      suggestedName: suggestedFilename(record),
      ext: ExportFormat.markdown.ext,
      bytes: utf8.encode(result.toPlainText()),
    );
  }

  /// 一键导出（内容生成 + 原生保存对话框）
  Future<String?> export(OptimizeRecord record, ExportFormat format) {
    final content = buildContent(record, format);
    return _fileSaver.save(
      suggestedName: suggestedFilename(record),
      ext: format.ext,
      bytes: utf8.encode(content),
    );
  }

  /// Markdown：六段式标题结构 + 元信息 + 诊断附录
  static String toMarkdown(OptimizeRecord record) {
    final r = record.latest.result;
    final b = StringBuffer()
      ..writeln('# 优化提示词')
      ..writeln()
      ..writeln('> 场景：${record.scene} ｜ 模式：${record.mode.label} ｜ 模型：${record.providers.join(", ")}')
      ..writeln('> 质量评分：${record.scoreBefore ?? "-"} → ${record.scoreAfter ?? "-"}')
      ..writeln()
      ..writeln('## 原始输入')
      ..writeln()
      ..writeln(record.rawText)
      ..writeln();
    if (r.isStructured) {
      void sec(String title, String body) {
        if (body.trim().isEmpty) return;
        b..writeln('## $title')..writeln()..writeln(body.trim())..writeln();
      }

      void listSec(String title, List<String> items) {
        if (items.isEmpty) return;
        b..writeln('## $title')..writeln();
        for (final it in items) {
          b.writeln('- $it');
        }
        b.writeln();
      }

      sec('角色定位', r.role);
      sec('任务目标', r.goal);
      listSec('具体要求', r.requirements);
      listSec('约束条件', r.constraints);
      sec('输出格式', r.outputFormat);
      listSec('验收标准', r.acceptance);
    } else {
      b..writeln('## 优化结果')..writeln()..writeln(r.rawText)..writeln();
    }
    if (r.diagnosis.isNotEmpty) {
      b..writeln('---')..writeln()..writeln('## 附：优化诊断')..writeln();
      for (final d in r.diagnosis) {
        b.writeln('- **[${d.status == 'fixed' ? '已修复' : '待确认'}] ${d.item}**：${d.action}');
      }
      b.writeln();
    }
    return b.toString();
  }
}
