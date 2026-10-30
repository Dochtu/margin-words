import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'data/app_database.dart';
import 'data/settings_repository.dart';
import 'data/word_dao.dart';
import 'services/ocr_service.dart';
import 'services/phonetic_lookup.dart';
import 'state/settings_store.dart';
import 'state/word_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final SettingsRepository repository = await SettingsRepository.open();
    final SettingsStore settings = SettingsStore(repository);
    final WordDao dao = WordDao(AppDatabase.instance);
    final WordStore wordStore = WordStore(dao: dao, settings: settings);
    final PhoneticLookup phonetic = PhoneticLookup(dao);

    // 调试模式下把配置打到 Logcat，方便确认"有没有读到"（Key 已打码）
    if (kDebugMode) {
      debugPrint('[AppConfig] ${AppConfig.describe()}');
    }

    // 先把本地数据读进内存，首帧就能看到内容（纯本地，通常几十毫秒）
    await wordStore.loadAll();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
          ChangeNotifierProvider<WordStore>.value(value: wordStore),
          Provider<WordDao>.value(value: dao),
          Provider<PhoneticLookup>.value(value: phonetic),
          Provider<OcrService>.value(value: const OcrService()),
        ],
        child: const WordbookApp(),
      ),
    );
  } catch (error) {
    runApp(_BootstrapErrorApp(message: error.toString()));
  }
}

/// 数据库初始化失败时的兜底界面（例如存储空间不足、文件损坏）。
class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.error_outline_rounded, size: 44),
                  const SizedBox(height: 16),
                  const Text(
                    '本地数据库初始化失败',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$message\n\n可以尝试：清理存储空间后重新打开应用；'
                    '或在系统设置中清除本应用数据。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
