/// 存储工厂：按平台条件选择实现。
library;

import 'app_storage.dart';
import 'storage_factory_stub.dart'
    if (dart.library.io) 'storage_factory_native.dart'
    if (dart.library.js_interop) 'storage_factory_web.dart' as impl;

/// 打开应用存储（native: 应用文档目录下的 SQLite；web: localStorage）
Future<AppStorage> openAppStorage() => impl.openAppStorage();
