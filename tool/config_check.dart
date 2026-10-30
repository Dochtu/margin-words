// 配置自检：不启动 App，直接打印"读到了什么、从哪读的"。
// 用法：
//   dart run tool/config_check.dart
//   dart run tool/config_check.dart --define=LLM_MODEL=test-model
import 'package:wordbook/core/app_config.dart';

void main() {
  print(AppConfig.describe());
  print('---');
  for (final String line in AppConfig.diagnosis()) {
    print(line);
  }
}
