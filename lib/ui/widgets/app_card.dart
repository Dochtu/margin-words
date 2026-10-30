import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// 统一卡片容器：圆角 16、细边框、可选点击水波纹。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
    this.onTap,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final VoidCallback? onTap;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double radius = borderRadius ?? AppTheme.radiusLg;
    final BorderRadius br = BorderRadius.circular(radius);

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).cardColor,
          borderRadius: br,
          border: Border.all(
            color: scheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: br,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: br,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// 小标题：左侧文字 + 右侧一条发丝线，替代"全是圆角卡片"的分区感。
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8, top: 4),
      child: Row(
        children: <Widget>[
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: scheme.outlineVariant,
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}
