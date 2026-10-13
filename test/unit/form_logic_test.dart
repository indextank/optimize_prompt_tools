/// 添加/编辑服务弹窗表单联动逻辑测试（对齐基准弹窗规则）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt_optimizer/core/model_specs.dart';
import 'package:prompt_optimizer/core/models.dart';
import 'package:prompt_optimizer/ui/pages/model_config_form_logic.dart';

void main() {
  ServiceFormState newForm() {
    final f = ServiceFormState(provider: 'doubao', apiUrl: '');
    f.onProviderChanged('doubao');
    return f;
  }

  group('服务商联动', () {
    test('切换服务商：地址与模型联动到该家默认并应用规格', () {
      final f = newForm();
      f.onProviderChanged('deepseek');
      expect(f.apiUrl, 'https://api.deepseek.com');
      expect(f.model, 'deepseek-flash');
      expect(f.temperature, 1.0);
      expect(f.maxInputTokens, 1048576);
      expect(f.maxOutputTokens, 65536); // 官方默认而非上限
    });

    test('kimi 默认 Coding Plan 地址', () {
      final f = newForm();
      f.onProviderChanged('kimi');
      expect(f.apiUrl, 'https://api.kimi.com/coding/v1');
    });

    test('stepfun 温度默认 0.5（官方值）', () {
      final f = newForm();
      f.onProviderChanged('stepfun');
      expect(f.temperature, 0.5);
    });
  });

  group('思考模式收敛规则（对齐基准）', () {
    test('toggle 模型三选项齐全', () {
      final f = newForm(); // doubao → toggle（回退规格）
      f.onProviderChanged('deepseek');
      expect(f.thinkingOptions,
          [kThinkingModeDefault, kThinkingModeOn, kThinkingModeOff]);
      expect(f.thinkingEnabled, isTrue);
    });

    test('forcedOn 模型不提供「关闭」', () {
      final f = newForm();
      f.onProviderChanged('zhipu');
      f.onModelChanged('glm-5.3');
      expect(f.thinkingOptions, [kThinkingModeDefault, kThinkingModeOn]);
      // 当前为 off 时被拉回 default
      f.thinkingMode = kThinkingModeOff;
      f.onModelChanged('glm-5.3');
      expect(f.thinkingMode, kThinkingModeDefault);
    });

    test('none 模型固定「跟随」且禁用', () {
      final f = newForm();
      f.onProviderChanged('dashscope');
      f.onModelChanged('qwen-long'); // thinking none
      expect(f.thinkingOptions, [kThinkingModeDefault]);
      expect(f.thinkingEnabled, isFalse);
      expect(f.thinkingMode, kThinkingModeDefault);
    });
  });

  group('图片输入收敛规则', () {
    test('非多模态固定不支持且禁用', () {
      final f = newForm();
      f.onProviderChanged('deepseek'); // vision=false
      expect(f.visionEnabled, isFalse);
      expect(f.imageInput, isFalse);
    });

    test('多模态模型可开启；切回非多模态自动复位', () {
      final f = newForm();
      f.onProviderChanged('dashscope');
      f.onModelChanged('qwen3.8-flash'); // vision=true
      expect(f.visionEnabled, isTrue);
      f.imageInput = true;
      f.onModelChanged('qwen-turbo'); // vision=false
      expect(f.imageInput, isFalse);
    });
  });

  group('编辑模式回读（顺序：先规格后覆盖）', () {
    test('已存参数覆盖规格默认值', () {
      final saved = ServiceConfig(
        id: 'e1',
        provider: 'deepseek',
        apiUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
        temperature: 0.3,
        maxInputTokens: 500000,
        maxOutputTokens: 8000,
        thinkingMode: 'on',
        createdAt: 1,
      );
      final f = newForm();
      f.restoreFrom(saved, apiKey: 'sk-saved');
      // 规格默认值是 temp 1.0 / out 65536，但已存值必须保留
      expect(f.temperature, 0.3);
      expect(f.maxInputTokens, 500000);
      expect(f.maxOutputTokens, 8000);
      expect(f.thinkingMode, 'on');
      expect(f.apiKey, 'sk-saved');
    });

    test('已存思考模式与当前模型规格冲突时回退 default', () {
      final saved = testServiceConfig(thinkingMode: 'off'); // forcedOn 模型不允许 off
      final f = newForm();
      f.restoreFrom(saved.copyWith(provider: 'zhipu', model: 'glm-5.3'));
      expect(f.thinkingMode, kThinkingModeDefault);
    });
  });

  group('校验', () {
    test('合法配置通过', () {
      final f = newForm();
      f.onProviderChanged('deepseek');
      expect(f.validate(), isNull);
    });

    test('空地址 / 非 http 地址 / 空模型拦截', () {
      final f = newForm();
      f.apiUrl = '';
      expect(f.validate(), contains('地址'));
      f.apiUrl = 'ftp://x';
      expect(f.validate(), contains('http'));
      f.apiUrl = 'https://api.deepseek.com';
      f.model = ' ';
      expect(f.validate(), contains('模型'));
    });

    test('Temperature 超官方范围拦截', () {
      final f = newForm();
      f.onProviderChanged('deepseek');
      f.temperature = 3.0;
      expect(f.validate(), contains('Temperature'));
    });

    test('最大输入超上下文窗口拦截', () {
      final f = newForm();
      f.onProviderChanged('deepseek');
      f.maxInputTokens = 1048576 + 1;
      expect(f.validate(), contains('上下文窗口'));
    });

    test('最大输出超上限拦截', () {
      final f = newForm();
      f.onProviderChanged('dashscope'); // qwen3.8-flash 上限 131072
      f.maxOutputTokens = 131073;
      expect(f.validate(), contains('生成上限'));
    });
  });

  group('组装持久化对象', () {
    test('toServiceConfig 字段完整且不含明文密钥', () {
      final f = newForm();
      f.onProviderChanged('deepseek');
      f.apiKey = 'sk-should-not-leak';
      final s = f.toServiceConfig(id: 'id9', isDefault: true, createdAt: 7);
      expect(s.id, 'id9');
      expect(s.provider, 'deepseek');
      expect(s.isDefault, isTrue);
      expect(s.createdAt, 7);
      expect(s.keyRef, isEmpty); // 密钥不进入配置对象
    });
  });
}

ServiceConfig testServiceConfig({String thinkingMode = 'default'}) =>
    ServiceConfig(
      id: 'e1',
      provider: 'deepseek',
      apiUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      thinkingMode: thinkingMode,
      createdAt: 1,
    );
