import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../widgets/app_card.dart';

/// 隐私说明页：把「什么数据在本机、什么数据会联网」讲清楚。
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('隐私说明')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          AppCard(
            color: scheme.primary.withValues(alpha: 0.05),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '一句话总结',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '单词数据只存在你自己的手机里；不登录、不采集个人信息、没有广告和统计 SDK。'
                  '只有「识别」这一步会把 OCR 出来的文字发给你自己配置的大模型。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.75,
                    color: scheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _Section(
            title: '1. 本机保存了什么',
            body: '单词、音标、中文释义、上传时间、学习日期、掌握状态、复习次数、'
                '最近复习时间。这些数据全部存放在应用私有的 SQLite 数据库'
                '（/data/data/com.lz.wordbook/databases/wordbook.db），'
                '其他应用无法读取，卸载应用即被系统删除。',
          ),
          const _Section(
            title: '2. 图片怎么处理',
            body: '拍照或选图后，图片只在本机用 Google ML Kit 做文字识别（离线模型），'
                '不会上传图片文件。默认不保存原图；'
                '如果你在设置里打开「保存来源图片」，副本会存放在应用私有目录，'
                '随「清空所有单词」一起删除。',
          ),
          const _Section(
            title: '3. 什么时候会联网',
            body: '只有两种情况：\n'
                '① 识别：把本地 OCR 得到的纯文字（不含图片、不含设备信息）发送到'
                '你填写的大模型接口，用于整理成单词表；\n'
                '② 音标校验（可关闭）：向免费词典接口 api.dictionaryapi.dev 查询单词音标。\n'
                '除此之外应用不会发起任何网络请求。',
          ),
          const _Section(
            title: '4. 申请了哪些权限',
            body: '• 相机（CAMERA）：仅在你点「拍照」时申请，用于拍摄要识别的图片。\n'
                '• 媒体/相册（Android 13+ 为 READ_MEDIA_IMAGES，'
                'Android 12 及以下为 READ_EXTERNAL_STORAGE）：仅在你点「从相册选择」时申请。\n'
                '• 网络（INTERNET）：仅用于上面第 3 条的两个场景。\n'
                '拒绝任何权限都不会导致应用无法打开，只是对应功能不可用，'
                '页面会给出说明和跳转系统设置的入口。',
          ),
          const _Section(
            title: '5. 关于 API Key',
            body: 'Key 只保存在本机（SharedPreferences），不会回传给我们或任何服务器。'
                '请注意：Android 上的本地存储并非硬件级加密，'
                '如果手机被 root 或数据被备份导出，Key 有泄露风险。'
                '正式对外分发时，建议部署一个自己的代理服务，'
                '由代理持有 Key，客户端只与代理通信。',
          ),
          const _Section(
            title: '6. 你可以怎么删除数据',
            body: '在「我的 → 清空所有单词」可一次性删除全部单词、复习记录与来源图片；'
                '卸载应用会连同数据库一起清除。应用没有云端副本，删除后无法恢复。',
          ),
          const _Section(
            title: '7. 不收集的信息',
            body: '不收集通讯录、位置、短信、通话记录、IMEI、广告标识符，'
                '不读取已安装应用列表，不做行为埋点，不接入任何第三方统计或广告 SDK。'
                '应用没有账号体系，因此也没有手机号、邮箱等注册信息。',
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '最后更新：2026-10',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        borderRadius: AppTheme.radiusMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.8,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
