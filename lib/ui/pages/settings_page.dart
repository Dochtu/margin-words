import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/image_store.dart';
import '../../state/settings_store.dart';
import '../../state/word_store.dart';
import '../widgets/app_card.dart';
import 'privacy_page.dart';

/// 「我的」：学习设置、外观、数据与隐私。
///
/// 模型与智能体参数只写在 `lib/core/app_config.dart`，这里没有任何配置入口。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsStore settings = context.watch<SettingsStore>();
    final WordStore store = context.watch<WordStore>();
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 18),
              child: Text(
                '我的',
                style: TextStyle(
                  fontSize: 24,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),

            // ------------------------------------------------ 数据概览
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: <Widget>[
                  _Stat(value: '${store.totalCount}', label: '全部单词'),
                  _Divider(),
                  _Stat(value: '${store.masteredCount}', label: '已掌握'),
                  _Divider(),
                  _Stat(value: '${store.todayCount}', label: '今日新增'),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ------------------------------------------------ 学习设置
            const SectionLabel('学习设置'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('重复单词处理',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(
                    settings.mergeDuplicates
                        ? '再次上传同名单词时，更新释义并刷新时间'
                        : '每次上传都新增一条记录，保留历史',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: const <ButtonSegment<bool>>[
                        ButtonSegment<bool>(value: true, label: Text('合并更新')),
                        ButtonSegment<bool>(value: false, label: Text('新增记录')),
                      ],
                      selected: <bool>{settings.mergeDuplicates},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<bool> v) => context
                          .read<SettingsStore>()
                          .setMergeDuplicates(v.first),
                      style: ButtonStyle(
                        textStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 12.5),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile.adaptive(
                    value: settings.saveSourceImage,
                    onChanged: (bool v) => context
                        .read<SettingsStore>()
                        .setSaveSourceImage(v),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('保存来源图片',
                        style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      '把照片副本存到应用私有目录，便于日后回看（占用空间）',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ------------------------------------------------ 外观
            const SectionLabel('外观'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('深色模式',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const <ButtonSegment<ThemeMode>>[
                        ButtonSegment<ThemeMode>(
                            value: ThemeMode.system, label: Text('跟随系统')),
                        ButtonSegment<ThemeMode>(
                            value: ThemeMode.light, label: Text('浅色')),
                        ButtonSegment<ThemeMode>(
                            value: ThemeMode.dark, label: Text('深色')),
                      ],
                      selected: <ThemeMode>{settings.themeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<ThemeMode> v) =>
                          context.read<SettingsStore>().setThemeMode(v.first),
                      style: ButtonStyle(
                        textStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 12.5),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ------------------------------------------------ 数据与隐私
            const SectionLabel('数据与隐私'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: Icon(Icons.privacy_tip_outlined,
                        size: 20, color: scheme.primary),
                    title: const Text('隐私说明', style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      '数据只存在本机，卸载即清除',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded,
                        size: 20, color: scheme.onSurfaceVariant),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const PrivacyPage()),
                    ),
                  ),
                  const Divider(indent: 52, endIndent: 12),
                  ListTile(
                    leading: Icon(Icons.delete_outline_rounded,
                        size: 20, color: scheme.error),
                    title: Text(
                      '清空所有单词',
                      style: TextStyle(fontSize: 14, color: scheme.error),
                    ),
                    subtitle: Text(
                      '同时删除复习记录与来源图片',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => _confirmClear(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                '错题单词本 v1.0.0 · 仅 Android · 无需登录',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('清空所有单词？'),
        content: const Text(
          '所有单词、复习记录、来源图片都会被删除，且无法恢复。\n'
          '这个操作不会影响你的设置项。',
          style: TextStyle(fontSize: 14, height: 1.7),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    await context.read<WordStore>().clearAllData();
    await const ImageStore().clearAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空所有单词')),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.8,
      height: 26,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
    );
  }
}
