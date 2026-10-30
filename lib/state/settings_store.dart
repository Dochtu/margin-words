import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../data/settings_repository.dart';
import '../data/word.dart';

/// 设置状态：读一次缓存到内存，修改后写回 SharedPreferences 并通知 UI。
///
/// 模型、Key、接口地址、智能体地址，以及"是否允许上传照片""是否联网校验音标"
/// 全部是 [AppConfig] 里的代码常量，App 内不提供任何配置入口。
/// 这里只保留运行时可调的偏好：重复策略、是否存原图、主题、回顾模式。
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._repo) {
    _load();
  }

  final SettingsRepository _repo;

  late bool _mergeDuplicates;
  late bool _saveSourceImage;
  late ThemeMode _themeMode;
  late ReviewMode _reviewMode;
  late bool _onboarded;

  void _load() {
    _mergeDuplicates = _repo.mergeDuplicates;
    _saveSourceImage = _repo.saveSourceImage;
    _themeMode = _repo.themeMode;
    _reviewMode = _repo.reviewMode;
    _onboarded = _repo.onboarded;
  }

  bool get mergeDuplicates => _mergeDuplicates;
  bool get saveSourceImage => _saveSourceImage;
  ThemeMode get themeMode => _themeMode;
  ReviewMode get reviewMode => _reviewMode;
  bool get onboarded => _onboarded;

  // ---- 以下两项只读，来自 AppConfig（代码常量） ----

  /// 是否允许把照片发给视觉模型（圈选识别）
  bool get agentAllowVision => AppConfig.agentAllowVision;

  /// 是否联网校验 / 补全音标
  bool get validatePhoneticOnline => AppConfig.validatePhoneticOnline;

  Future<void> setMergeDuplicates(bool value) async {
    if (_mergeDuplicates == value) return;
    _mergeDuplicates = value;
    await _repo.setBool(SettingsRepository.kMergeDuplicates, value);
    notifyListeners();
  }

  Future<void> setSaveSourceImage(bool value) async {
    if (_saveSourceImage == value) return;
    _saveSourceImage = value;
    await _repo.setBool(SettingsRepository.kSaveSourceImage, value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    await _repo.setString(
      SettingsRepository.kThemeMode,
      value == ThemeMode.light
          ? 'light'
          : (value == ThemeMode.dark ? 'dark' : 'system'),
    );
    notifyListeners();
  }

  Future<void> setReviewMode(ReviewMode value) async {
    if (_reviewMode == value) return;
    _reviewMode = value;
    await _repo.setString(SettingsRepository.kReviewMode, value.storageValue);
    notifyListeners();
  }

  Future<void> markOnboarded() async {
    if (_onboarded) return;
    _onboarded = true;
    await _repo.setBool(SettingsRepository.kOnboarded, true);
    notifyListeners();
  }
}
