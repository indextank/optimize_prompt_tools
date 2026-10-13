/// 应用入口：初始化存储 / 设置 / 密钥库 / 引擎，然后启动 UI。
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/key_store.dart';
import 'services/llm_client.dart';
import 'services/optimize_engine.dart';
import 'services/settings_service.dart';
import 'services/storage/storage_factory.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await openAppStorage();
  final settings = await SettingsService.load(storage);
  final keyStore = kIsWeb ? MemoryKeyStore() as KeyStore : const SecureKeyStore();
  final llmClient = OpenAiCompatibleClient();

  appState = AppState(
    storage: storage,
    keyStore: keyStore,
    settings: settings,
    engine: OptimizeEngine(client: llmClient),
    llmClient: llmClient,
  );
  await appState.init();

  runApp(const PromptOptimizerApp());
}
