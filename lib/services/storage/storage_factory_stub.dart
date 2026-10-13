/// 存根（VM 测试等场景由 conditional import 决定实际实现）
library;

import 'app_storage.dart';

Future<AppStorage> openAppStorage() =>
    throw UnsupportedError('当前平台无可用存储实现');
