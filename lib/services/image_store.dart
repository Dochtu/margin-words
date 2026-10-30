import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 可选：把拍照/选图的临时文件复制到应用私有目录，便于日后回看原图。
///
/// 默认关闭（设置项「保存来源图片」），因为保留原图既占空间也涉及隐私。
class ImageStore {
  const ImageStore();

  static const String _folder = 'word_images';

  Future<Directory> _targetDir() async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/$_folder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 复制临时文件并返回可长期使用的路径；失败返回 null（不影响保存单词）。
  Future<String?> persist(String tempPath) async {
    try {
      final Directory dir = await _targetDir();
      final String name = 'word_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File copied = await File(tempPath).copy('${dir.path}/$name');
      return copied.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 忽略：文件可能已被系统清理
    }
  }

  Future<void> clearAll() async {
    try {
      final Directory dir = await _targetDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // 忽略
    }
  }
}
