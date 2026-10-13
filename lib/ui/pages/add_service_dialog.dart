/// 添加/编辑 AI 服务弹窗（对齐基准项目 ai_service_dialog.py 的界面与交互）。
library;

import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/model_specs.dart';
import '../../core/models.dart';
import '../../services/llm_client.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/editable_dropdown.dart';
import 'model_config_form_logic.dart';

/// 模型拉取函数签名（可注入测试替身）
typedef ModelFetcher = Future<List<String>> Function(
    String provider, String apiUrl, String apiKey);

/// 连接测试函数签名
typedef ConnectionTester = Future<ConnectionTestResult> Function(
    ServiceConfig service, String apiKey);

/// 弹窗返回：配置 + 明文密钥（密钥由调用方写入安全存储，不进配置对象）
typedef AddServiceResult = ({ServiceConfig config, String apiKey});

/// 打开添加弹窗
Future<AddServiceResult?> showAddServiceDialog(BuildContext context,
    {ModelFetcher? modelFetcher, ConnectionTester? connectionTester}) {
  return showDialog<AddServiceResult>(
    context: context,
    builder: (_) => AddServiceDialog(
      modelFetcher: modelFetcher,
      connectionTester: connectionTester,
    ),
  );
}

/// 打开编辑弹窗
Future<AddServiceResult?> showEditServiceDialog(BuildContext context, ServiceConfig config,
    {String? apiKey, ModelFetcher? modelFetcher, ConnectionTester? connectionTester}) {
  return showDialog<AddServiceResult>(
    context: context,
    builder: (_) => AddServiceDialog(
      editing: config,
      editingApiKey: apiKey,
      modelFetcher: modelFetcher,
      connectionTester: connectionTester,
    ),
  );
}

class AddServiceDialog extends StatefulWidget {
  const AddServiceDialog({
    super.key,
    this.editing,
    this.editingApiKey,
    this.modelFetcher,
    this.connectionTester,
  });

  final ServiceConfig? editing;
  final String? editingApiKey;
  final ModelFetcher? modelFetcher;
  final ConnectionTester? connectionTester;

  bool get isEdit => editing != null;

  @override
  State<AddServiceDialog> createState() => AddServiceDialogState();
}

class AddServiceDialogState extends State<AddServiceDialog> {
  late final ServiceFormState form;
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();

  List<String> _models = [];
  String _modelStatus = '';
  bool _modelStatusOk = false;
  String _testStatus = '';
  bool _testOk = false;
  bool _testing = false;
  bool _fetching = false;
  bool _showKey = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final first = kProviderList.first;
    form = ServiceFormState(
      provider: first,
      apiUrl: getProviderConfig(first)!.defaultUrl,
    );
    form.onProviderChanged(first);
    final editing = widget.editing;
    if (editing != null) {
      form.restoreFrom(editing, apiKey: widget.editingApiKey ?? '');
      _models = [form.model];
    }
    _urlCtrl.text = form.apiUrl;
    _keyCtrl.text = form.apiKey;
    _modelCtrl.text = form.model;
    _keyCtrl.addListener(_onKeyChanged);
  }

  /// 切换服务商（下拉与测试入口共用）：同步地址/模型文本与内置模型清单
  void _selectProvider(String v) {
    setState(() {
      form.onProviderChanged(v);
      _urlCtrl.text = form.apiUrl;
      _modelCtrl.text = form.model;
      _models = getProviderConfig(v)!.models; // 必须用新 provider 的配置
    });
  }

  /// 仅测试用：以编程方式切换服务商（等价于下拉选择）
  @visibleForTesting
  void debugSelectProvider(String v) => _selectProvider(v);

  @override
  void dispose() {
    _debounce?.cancel();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _onKeyChanged() {
    form.apiKey = _keyCtrl.text;
    _debounce?.cancel();
    final cfg = getProviderConfig(form.provider);
    if (cfg?.supportsModelListApi ?? false) {
      // 输入停顿 800ms 后自动拉取模型列表（对齐基准）
      _debounce = Timer(const Duration(milliseconds: 800), _fetchModels);
    }
  }

  Future<void> _fetchModels() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _fetching = true;
      _modelStatus = '正在获取模型列表…';
      _modelStatusOk = false;
    });
    final fetcher = widget.modelFetcher ?? appState.fetchModels;
    try {
      final models = await fetcher(form.provider, _urlCtrl.text.trim(), key);
      if (!mounted) return;
      setState(() {
        _models = models;
        _fetching = false;
        _modelStatusOk = true;
        _modelStatus = '获取成功，共 ${models.length} 个可用模型';
        if (models.isNotEmpty && !_models.contains(_modelCtrl.text)) {
          _applyModel(models.first);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _modelStatusOk = false;
        _modelStatus = '获取模型列表失败：$e';
      });
    }
  }

  void _applyModel(String model) {
    setState(() {
      form.onModelChanged(model);
      _modelCtrl.text = model;
    });
  }

  Future<void> _testConnection() async {
    final tester = widget.connectionTester ?? appState.testConnection;
    setState(() {
      _testing = true;
      _testStatus = '测试中…';
    });
    final svc = form.toServiceConfig();
    final res = await tester(svc, _keyCtrl.text.trim());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = res.success;
      _testStatus = res.success ? '✓ 连接成功，延迟 ${res.latencyMs}ms' : '✗ ${res.message}';
    });
  }

  void _save() {
    final err = form.validate();
    if (err != null) {
      setState(() {
        _testOk = false;
        _testStatus = '✗ $err';
      });
      return;
    }
    final editing = widget.editing;
    Navigator.of(context).pop((
      config: form.toServiceConfig(
        id: editing?.id ?? const Uuid().v4(),
        isDefault: editing?.isDefault ?? false,
        createdAt: editing?.createdAt ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
      apiKey: _keyCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cfg = getProviderConfig(form.provider)!;
    final urlOptions = getProviderUrlOptions(form.provider);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 860),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.isEdit ? '编辑AI服务' : '添加AI服务',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('配置AI服务提供商、API密钥和模型参数',
            style: TextStyle(fontSize: 12, color: AppTokens.text3)),
      ]),
      content: SingleChildScrollView(
        // 右侧预留滚动条车道（≥12px）：覆盖式滚动条出现时，
        // 下拉箭头/复选框/按钮等右端控件仍保有安全间距，不与滚动条挤碰
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('AI服务提供商'),
          ComboBox<String>(
            value: form.provider,
            isExpanded: true,
            items: [
              for (final p in kProviderList)
                ComboBoxItem(value: p, child: Text(getProviderConfig(p)!.name)),
            ],
            // 编辑模式禁止修改服务商（对齐基准）
            onChanged: widget.isEdit
                ? null
                : (v) {
                    if (v == null) return;
                    _selectProvider(v);
                  },
          ),
          const SizedBox(height: 12),
          _label('API接口地址'),
          // 可编辑下拉：预设地址全量展示（不按输入过滤），也可直接键入自定义地址
          EditableDropdown(
            controller: _urlCtrl,
            dropdownKey: const Key('api-url-dropdown'),
            textKey: const Key('api-url-field'),
            placeholder: 'https://...',
            options: [for (final o in urlOptions) o.url],
            onChanged: (t) => form.apiUrl = t,
            onSelected: (url) => setState(() => form.apiUrl = url),
          ),
          _hint(cfg.codingPlanName != null
              ? '可从下拉选择官方地址（标准 / ${cfg.codingPlanName}），也可直接输入自定义地址'
              : '可选择官方地址，也可直接输入自定义地址'),
          const SizedBox(height: 12),
          Row(children: [
            _label('API KEY'),
            const Spacer(),
            Checkbox(
              checked: _showKey,
              onChanged: (v) => setState(() => _showKey = v ?? false),
              content: const Text('显示密码', style: TextStyle(fontSize: 11.5)),
            ),
          ]),
          if (_showKey)
            TextBox(controller: _keyCtrl, placeholder: '«redacted:sk-…»')
          else
            PasswordBox(controller: _keyCtrl, placeholder: '«redacted:sk-…»'),
          _hint(_modelStatus.isEmpty ? '输入API KEY后将自动获取可用模型列表' : _modelStatus,
              ok: _modelStatusOk),
          const SizedBox(height: 12),
          Row(children: [
            _label('模型'),
            const Spacer(),
            Button(
              onPressed: _fetching ? null : _fetchModels,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_fetching)
                  const SizedBox(
                      width: 12, height: 12, child: ProgressRing(strokeWidth: 2))
                else
                  const Icon(FluentIcons.sync, size: 12),
                const SizedBox(width: 5),
                const Text('刷新模型列表', style: TextStyle(fontSize: 11.5)),
              ]),
            ),
          ]),
          EditableDropdown(
            controller: _modelCtrl,
            dropdownKey: const Key('model-dropdown'),
            textKey: const Key('model-field'),
            placeholder: '请先输入API KEY获取模型列表',
            // 内置清单与在线拉取结果合并去重，全部展示（修复 Kimi 4 模型只显示 2 个）
            options: {...cfg.models, ..._models}.toList(),
            onChanged: (t) => form.model = t,
            onSelected: _applyModel,
          ),
          if (form.spec.isFallback && form.model.isNotEmpty)
            _hint('该模型未内置官方规格，已按服务商保守规格填充'),
          const SizedBox(height: 6),
          const Divider(),
          const SizedBox(height: 6),
          _label('Temperature'),
          NumberBox<double>(
            value: form.temperature,
            min: form.spec.temperatureMin,
            max: form.spec.temperatureMax,
            smallChange: 0.1,
            precision: 2,
            onChanged: form.spec.temperatureSupported
                ? (v) => form.temperature = v ?? form.temperature
                : null,
          ),
          _hint('官方范围 ${form.spec.temperatureMin}-${form.spec.temperatureMax}，默认 ${form.spec.temperatureDefault}'),
          const SizedBox(height: 12),
          _label('最大输入Token'),
          NumberBox<int>(
            value: form.maxInputTokens,
            min: 1,
            max: form.spec.contextWindow,
            smallChange: 1024,
            onChanged: (v) => form.maxInputTokens = v ?? form.maxInputTokens,
          ),
          _hint('模型上下文窗口 ${_fmt(form.spec.contextWindow)} tokens；不超过所选模型上下文窗口'),
          const SizedBox(height: 12),
          _label('最大输出Token'),
          NumberBox<int>(
            value: form.maxOutputTokens,
            min: 1,
            max: form.spec.maxOutputTokens,
            smallChange: 512,
            onChanged: (v) => form.maxOutputTokens = v ?? form.maxOutputTokens,
          ),
          _hint('模型单次生成的最大Token数，上限 ${_fmt(form.spec.maxOutputTokens)}'),
          const SizedBox(height: 12),
          _label('思考模式'),
          ComboBox<String>(
            value: form.thinkingOptions.contains(form.thinkingMode)
                ? form.thinkingMode
                : kThinkingModeDefault,
            isExpanded: true,
            items: [
              for (final m in form.thinkingOptions)
                ComboBoxItem(value: m, child: Text(kThinkingModeLabels[m]!)),
            ],
            onChanged: form.thinkingEnabled
                ? (v) => setState(() => form.thinkingMode = v ?? form.thinkingMode)
                : null,
          ),
          _hint('仅支持推理思考的模型可配置该项'),
          const SizedBox(height: 12),
          _label('支持图片输入'),
          ComboBox<bool>(
            value: form.visionEnabled ? form.imageInput : false,
            isExpanded: true,
            items: const [
              ComboBoxItem(value: true, child: Text('支持')),
              ComboBoxItem(value: false, child: Text('不支持')),
            ],
            onChanged: form.visionEnabled
                ? (v) => setState(() => form.imageInput = v ?? false)
                : null,
          ),
          _hint('仅具备多模态理解能力的模型可开启图片输入'),
          const SizedBox(height: 14),
          Row(children: [
            Button(
              onPressed: _testing ? null : _testConnection,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_testing)
                  const SizedBox(
                      width: 12, height: 12, child: ProgressRing(strokeWidth: 2))
                else
                  const Icon(FluentIcons.plug_connected, size: 13),
                const SizedBox(width: 6),
                const Text('测试连接'),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_testStatus,
                  style: TextStyle(
                      fontSize: 12,
                      color: _testOk ? AppTokens.success : AppTokens.danger)),
            ),
          ]),
        ]),
        ),
      ),
      actions: [
        Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20), child: Text('取消'))),
        FilledButton(
            onPressed: _save,
            child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20), child: Text('保存'))),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t, style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600)),
      );

  Widget _hint(String t, {bool ok = false}) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(t,
            style: TextStyle(
                fontSize: 11, color: ok ? AppTokens.success : AppTokens.text3)),
      );

  String _fmt(int v) {
    final s = '$v';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
