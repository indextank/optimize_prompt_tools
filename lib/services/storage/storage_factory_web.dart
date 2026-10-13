/// web 实现：SharedPreferences（localStorage）
library;

import 'app_storage.dart';
import 'web_storage.dart';

Future<AppStorage> openAppStorage() => WebStorage.create();
