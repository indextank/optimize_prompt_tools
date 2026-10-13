/// FileSaver 条件导出
library;

import '../services/export_service.dart';
import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_native.dart'
    if (dart.library.js_interop) 'file_saver_web.dart' as impl;

FileSaver createFileSaver() => impl.createFileSaver();
