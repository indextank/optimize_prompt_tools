/// Web 桩：浏览器无法自定义 HttpClient 代理，仅做普通请求探测。
library;

import 'package:dio/dio.dart';

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
