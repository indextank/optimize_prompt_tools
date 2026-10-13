/// SSE 解析器测试（字节边界 / 多行 data / 注释 / [DONE] / 残余冲刷）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/services/llm_client.dart';

void main() {
  List<String> drive(String input, {int? splitAt}) {
    final out = <String>[];
    final p = SseParser(onData: out.add);
    if (splitAt == null) {
      p.feed(input);
    } else {
      p.feed(input.substring(0, splitAt));
      p.feed(input.substring(splitAt));
    }
    p.close();
    return out;
  }

  test('标准单行 data 事件', () {
    expect(drive('data: {"a":1}\n\n'), ['{"a":1}']);
  });

  test('[DONE] 作为普通数据上抛（由上层判定）', () {
    expect(drive('data: [DONE]\n\n'), ['[DONE]']);
  });

  test('多行 data 合并为一个事件', () {
    expect(drive('data: 第一行\ndata: 第二行\n\n'), ['第一行\n第二行']);
  });

  test('多事件顺序分发', () {
    expect(drive('data: a\n\ndata: b\n\ndata: c\n\n'), ['a', 'b', 'c']);
  });

  test('keep-alive 注释与事件字段被忽略', () {
    expect(drive(': ping\n\nevent: message\ndata: x\n\n'), ['x']);
  });

  test('CRLF 行尾兼容', () {
    expect(drive('data: a\r\n\r\ndata: b\r\n\r\n'), ['a', 'b']);
  });

  test('跨任意字节边界切分结果一致', () {
    const input = 'data: {"choices":[{"delta":{"content":"你好世界"}}]}\n\ndata: [DONE]\n\n';
    final full = drive(input);
    for (var i = 1; i < input.length; i += 3) {
      expect(drive(input, splitAt: i), full, reason: 'splitAt=$i');
    }
  });

  test('流尾无空行时 close 冲刷残余 data', () {
    expect(drive('data: tail'), ['tail']);
  });

  test('空输入不产生事件', () {
    expect(drive(''), isEmpty);
    expect(drive('\n\n: only-comment\n\n'), isEmpty);
  });
}
