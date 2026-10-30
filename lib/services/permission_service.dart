import 'package:permission_handler/permission_handler.dart';

/// 权限请求结果。
enum PermissionOutcome {
  granted,

  /// 本次拒绝，可以再次弹窗
  denied,

  /// 勾选了“不再询问”，只能去系统设置里开
  permanentlyDenied,
}

/// 相机 / 相册权限。
///
/// 设计原则：只在真正要拍照/选图时请求，不在启动时索取任何权限。
class PermissionService {
  const PermissionService();

  /// 拍照前请求 CAMERA。
  Future<PermissionOutcome> ensureCamera() async {
    final PermissionStatus status = await Permission.camera.request();
    return _map(status);
  }

  /// 选图前请求媒体读取权限。
  ///
  /// Android 13+ 对应 READ_MEDIA_IMAGES（含“仅选中的照片”），
  /// Android 12 及以下对应 READ_EXTERNAL_STORAGE。
  /// 即使被拒绝，系统相册选择器（Photo Picker）依然可用，
  /// 因此调用方应允许用户「仍然去选图」。
  Future<PermissionOutcome> ensureGallery() async {
    final Map<Permission, PermissionStatus> statuses =
        await <Permission>[Permission.photos, Permission.storage].request();

    final PermissionStatus? photos = statuses[Permission.photos];
    final PermissionStatus? storage = statuses[Permission.storage];

    if (_isUsable(photos) || _isUsable(storage)) {
      return PermissionOutcome.granted;
    }
    if ((photos?.isPermanentlyDenied ?? false) ||
        (storage?.isPermanentlyDenied ?? false)) {
      return PermissionOutcome.permanentlyDenied;
    }
    return PermissionOutcome.denied;
  }

  Future<bool> openSettings() => openAppSettings();

  bool _isUsable(PermissionStatus? status) {
    if (status == null) return false;
    return status.isGranted || status.isLimited;
  }

  PermissionOutcome _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return PermissionOutcome.granted;
    if (status.isPermanentlyDenied) return PermissionOutcome.permanentlyDenied;
    return PermissionOutcome.denied;
  }
}
