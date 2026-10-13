/// AI 模型配置页：默认服务 + 并行对比 + 服务卡片列表（对齐基准 ai_page.py）。
library;

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants.dart';
import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'add_service_dialog.dart';

class ModelConfigPage extends StatefulWidget {
  const ModelConfigPage({super.key});

  @override
  State<ModelConfigPage> createState() => _ModelConfigPageState();
}

class _ModelConfigPageState extends State<ModelConfigPage> {
  final Map<String, String> _connStatus = {}; // serviceId → 状态文本

  Future<void> _addService() async {
    final res = await showAddServiceDialog(context);
    if (res != null) {
      await appState.saveService(res.config,
          apiKey: res.apiKey.isEmpty ? null : res.apiKey);
      _toast('已添加服务', InfoBarSeverity.success);
    }
  }

  Future<void> _editService(ServiceConfig svc) async {
    final key = await appState.readApiKey(svc);
    if (!mounted) return;
    final res = await showEditServiceDialog(context, svc, apiKey: key);
    if (res != null) {
      // 密钥框留空 = 保持原密钥不变
      await appState.saveService(res.config,
          apiKey: res.apiKey.isEmpty ? null : res.apiKey);
      _toast('已保存修改', InfoBarSeverity.success);
    }
  }

  Future<void> _deleteService(ServiceConfig svc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('删除服务'),
        content: Text(
            '确定删除「${getProviderConfig(svc.provider)?.name ?? svc.provider} · ${svc.model}」吗？\n该服务的 API KEY 将一并从安全存储中清除。'),
        actions: [
          Button(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await appState.deleteService(svc);
      if (mounted) _toast('已删除', InfoBarSeverity.warning);
    }
  }

  bool _batchTesting = false;

  Future<void> _testAll() async {
    if (_batchTesting) return; // 防重入（按钮置灰之外的第二道保险）
    setState(() => _batchTesting = true);
    try {
      for (final svc in appState.services) {
        setState(() => _connStatus[svc.id] = '检测中…');
        final key = await appState.readApiKey(svc) ?? '';
        final res = await appState.testConnection(svc, key);
        if (!mounted) return;
        setState(() => _connStatus[svc.id] =
            res.success ? '✓ 连接正常 · ${res.latencyMs}ms' : '✗ ${res.message}');
      }
    } finally {
      if (mounted) setState(() => _batchTesting = false);
    }
  }

  void _toast(String msg, InfoBarSeverity sev) {
    displayInfoBar(context,
        builder: (context, close) =>
            InfoBar(title: Text(msg), severity: sev, onClose: close));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final services = appState.services;
        final defaultSvc = appState.defaultService;
        final compact = MediaQuery.of(context).size.width < AppTokens.compactBreakpoint;
        return ScaffoldPage.withPadding(
          padding: EdgeInsets.fromLTRB(compact ? 14 : 26, 14, compact ? 14 : 26, 12),
          content: ListView(children: [
            const Text('AI 模型配置',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('配置国内主流大模型服务，支持多模型并行优化与一键切换；密钥仅本地加密存储',
                style: TextStyle(fontSize: 12.5, color: AppTokens.text3)),
            const SizedBox(height: 14),
            // ---------------- 默认优化服务 ----------------
            _Group(title: '默认优化服务', children: [
              _row(
                label: '默认AI服务',
                desc: '优化提示词时默认使用的模型服务，可在工作台临时切换。',
                child: ConstrainedBox(
                  // 限宽 + isExpanded：长模型名（如 glm-5.3-flashx）时下拉内容
                  // 省略号收缩，避免 fluent ComboBox 内部 Row 溢出
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: ComboBox<String>(
                    isExpanded: true,
                    // null 时显示占位符（极端场景：有服务但默认未指定）
                    placeholder: const Text('请选择默认服务'),
                    // 0 服务时值为 ''，正好落在「未配置」项上直观展示
                    value: services.isEmpty ? '' : defaultSvc?.id,
                    items: [
                      // 仅在「未配置任何服务」的初始状态保留「未配置」选项；
                      // 已有 ≥1 个配置时立即移除，避免无效选项干扰
                      if (services.isEmpty)
                        const ComboBoxItem(value: '', child: Text('未配置')),
                      for (final s in services)
                        ComboBoxItem(
                            value: s.id,
                            child: Text(
                                '${getProviderConfig(s.provider)?.name ?? s.provider} · ${s.model}',
                                overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      if (v != null && v.isNotEmpty) appState.setDefaultService(v);
                    },
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            // ---------------- 已配置的AI服务 ----------------
            _Group(
                title: '已配置的AI服务（${appState.configuredServiceCount}）',
                children: [
              if (services.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: Text('暂未配置任何AI服务，请点击下方按钮添加。',
                          style: TextStyle(color: AppTokens.text3))),
                )
              else
                for (final svc in services)
                  _ServiceCard(
                    service: svc,
                    status: _connStatus[svc.id],
                    onEdit: () => _editService(svc),
                    onDelete: () => _deleteService(svc),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(children: [
                  FilledButton(
                      onPressed: _addService, child: const Text('＋ 添加AI服务')),
                  const SizedBox(width: 10),
                  if (services.isNotEmpty)
                    // 检测全部完成前置灰，杜绝重复点击发起并发检测
                    Button(
                        onPressed: _batchTesting ? null : _testAll,
                        child: Text(_batchTesting ? '⏳ 检测中…' : '📶 批量检测连通性')),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            InfoBar(
              title: const Text('支持服务商'),
              content: const Text(
                  '豆包（火山方舟）、通义千问（阿里云百炼）、文心一言（百度千帆）、智谱、Kimi、DeepSeek、阶跃 StepFun、小米 MiMo、MiniMax。均为 OpenAI 兼容协议，密钥仅本地加密存储。'),
              severity: InfoBarSeverity.info,
            ),
          ]),
        );
      },
    );
  }

  Widget _row({required String label, required String desc, required Widget child}) {
    final compact = MediaQuery.of(context).size.width < AppTokens.compactBreakpoint;
    final labelWidget = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      child,
      const SizedBox(height: 4),
      Text(desc, style: const TextStyle(fontSize: 11.5, color: AppTokens.text3)),
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: compact
          // 窄屏：标签在上、控件在下，杜绝横向挤压
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              labelWidget,
              const SizedBox(height: 8),
              content,
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 130, child: labelWidget),
              Expanded(child: content),
            ]),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        const Divider(),
        ...children,
      ]),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.onEdit,
    required this.onDelete,
    this.status,
  });

  final ServiceConfig service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String? status;

  static const _colors = {
    'doubao': Color(0xFFFF6A00),
    'dashscope': Color(0xFF00B578),
    'qianfan': Color(0xFF2932E1),
    'zhipu': Color(0xFF0F52BA),
    'kimi': Color(0xFF7B61FF),
    'deepseek': Color(0xFF4A90D9),
    'stepfun': Color(0xFF1AAD19),
    'mimo': Color(0xFFFF6900),
    'minimax': Color(0xFF6B4FBB),
  };

  @override
  Widget build(BuildContext context) {
    final cfg = getProviderConfig(service.provider);
    final url = service.apiUrl.length <= 42
        ? service.apiUrl
        : '${service.apiUrl.substring(0, 42)}…';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: service.isDefault ? const Color(0xFFF0F4FF) : Colors.white,
        border: Border.all(
            color: service.isDefault
                ? AppTokens.defaultBlue.withValues(alpha: .3)
                : AppTokens.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: MediaQuery.of(context).size.width < AppTokens.compactBreakpoint
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _infoRow(cfg, url),
              const SizedBox(height: 8),
              // 右对齐：无状态时按钮同样贴右缘，与桌面态一致
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (status != null)
                  Expanded(
                    child: Text(status!,
                        overflow: TextOverflow.ellipsis,
                        style: _statusStyle()),
                  ),
                Button(onPressed: onEdit, child: const Text('✏️ 编辑')),
                const SizedBox(width: 8),
                Button(onPressed: onDelete, child: const Text('🗑 删除')),
              ]),
            ])
          : Row(children: [
              Expanded(child: _infoRow(cfg, url)),
              if (status != null)
                // 不用 Flexible：与 Expanded 同排时其未用尽的分配额会滞留为空隙，
                // 把右侧按钮组整体拉离右缘（旧截图症状）。自然宽 + 上限约束即可。
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(status!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _statusStyle()),
                  ),
                ),
              Button(onPressed: onEdit, child: const Text('✏️ 编辑')),
              const SizedBox(width: 8),
              Button(onPressed: onDelete, child: const Text('🗑 删除')),
            ]),
    );
  }

  /// 图标 + 名称 + 模型/URL 信息行（桌面与紧凑两态共用）
  Widget _infoRow(ProviderConfig? cfg, String url) {
    return Row(children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _colors[service.provider] ?? AppTokens.text3,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          (cfg?.name ?? service.provider).characters.first,
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
              child: Text(cfg?.name ?? service.provider,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            if (service.isDefault)
              const Text('  ★ 默认',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTokens.defaultBlue,
                      fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 2),
          Text('模型: ${service.model}  |  $url',
              style: const TextStyle(fontSize: 11.5, color: AppTokens.text3),
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]);
  }

  TextStyle _statusStyle() => TextStyle(
      fontSize: 11.5,
      color: status!.startsWith('✓')
          ? AppTokens.success
          : status!.startsWith('✗')
              ? AppTokens.danger
              : AppTokens.text3);
}

