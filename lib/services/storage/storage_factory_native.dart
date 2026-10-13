/// native 实现：应用文档目录下 SQLite 文件
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_storage.dart';
import 'sqlite_storage.dart';

Future<AppStorage> openAppStorage() async {
  final dir = await getApplicationDocumentsDirectory();
  return SqliteStorage.open(p.join(dir.path, 'prompt_optimizer.db'));
}
