/// 统一异常类型
library;

/// LLM 调用异常
class LlmException implements Exception {
  const LlmException(this.kind, this.message, {this.statusCode});

  final LlmErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'LlmException($kind, $statusCode): $message';

  /// 用户可读的错误文案
  String get userMessage => switch (kind) {
        LlmErrorKind.unauthorized => 'API KEY 无效或已过期（HTTP $statusCode）',
        LlmErrorKind.forbidden => '无权限访问该服务（HTTP $statusCode），请检查 Key 权限',
        LlmErrorKind.notFound => 'API 地址不存在或路径错误（HTTP 404）',
        LlmErrorKind.rateLimited => '触发限流（HTTP 429），请稍后重试',
        LlmErrorKind.serverError => '服务商服务端错误（HTTP $statusCode）',
        LlmErrorKind.timeout => '请求超时，请检查网络或增大超时时间',
        LlmErrorKind.network => '网络连接失败，请检查网络与代理设置',
        LlmErrorKind.cancelled => '已取消',
        LlmErrorKind.badResponse => '响应格式异常：$message',
        LlmErrorKind.invalidJson => '模型返回格式不符合契约：$message',
      };
}

enum LlmErrorKind {
  unauthorized,
  forbidden,
  notFound,
  rateLimited,
  serverError,
  timeout,
  network,
  cancelled,
  badResponse,
  invalidJson,
}

/// 存储异常
class StorageException implements Exception {
  const StorageException(this.message);
  final String message;
  @override
  String toString() => 'StorageException: $message';
}
