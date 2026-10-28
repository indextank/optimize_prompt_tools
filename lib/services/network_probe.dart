/// 条件导入入口：原生平台走 IO 实现，Web 走桩实现。
library;

import 'network_probe_stub.dart'
    if (dart.library.io) 'network_probe_io.dart' as impl;

/// 经指定代理路径请求 [url]，返回是否连通。
///
/// - [proxyRule] 为 null：跟随系统（不注入 findProxy）
/// - [proxyRule] 为 'DIRECT'：强制直连
/// - [proxyRule] 形如 'PROXY host:port' / 'SOCKS5 host:port'：走自定义代理
Future<bool> probeThroughProxy({
  required String? proxyRule,
  required Uri url,
  required Duration timeout,
}) =>
    impl.probeThroughProxy(proxyRule: proxyRule, url: url, timeout: timeout);
