/// IO 实现：Dio + HttpClient.findProxy 经指定代理路径探测连通性。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 经 [proxyRule] 请求 [url]；null=跟随系统，DIRECT=直连，其余为代理规则串。
Future<bool> probeThroughProxy({
  required String? proxyRule,
  required Uri url,
  required Duration timeout,
}) async {
  final dio = Dio(BaseOptions(
    connectTimeout: timeout,
    receiveTimeout: timeout,
    responseType: ResponseType.bytes,
  ));
  final adapter = dio.httpClientAdapter;
  if (adapter is IOHttpClientAdapter && proxyRule != null) {
    final rule = proxyRule;
    adapter.createHttpClient = () {
      final client = HttpClient();
      client.findProxy = (_) => rule;
      return client;
    };
  }
  try {
    await dio.getUri<void>(url);
    return true;
  } on DioException {
    return false;
  } catch (_) {
    return false;
  } finally {
    dio.close(force: true);
  }
}
