import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'word.dart';

/// 运行时偏好设置（**不含任何模型 / 智能体配置**）。
///
/// 模型、Key、接口地址、智能体地址都是 `lib/core/app_config.dart` 里的代码常量；
/// 这里只存"用起来才需要调"的偏好：重复策略、是否存原图、主题、回顾模式。
class SettingsRepository {
  SettingsRepository(this._prefs);

  static Future<SettingsRepository> open() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return SettingsRepository(prefs);
  }

  final SharedPreferences _prefs;

  static const String kMergeDuplicates = 'merge_duplicates';
  static const String kSaveSourceImage = 'save_source_image';
  static const String kThemeMode = 'theme_mode';
  static const String kReviewMode = 'review_mode';
  static const String kOnboarded = 'onboarded';

  bool get mergeDuplicates => _prefs.getBool(kMergeDuplicates) ?? true;

  bool get saveSourceImage => _prefs.getBool(kSaveSourceImage) ?? false;

  ThemeMode get themeMode {
    switch (_prefs.getString(kThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  ReviewMode get reviewMode =>
      ReviewMode.fromStorage(_prefs.getString(kReviewMode));

  bool get onboarded => _prefs.getBool(kOnboarded) ?? false;

  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  Future<void> remove(String key) => _prefs.remove(key);
}
