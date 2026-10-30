import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// 3D 翻卡：绕 Y 轴旋转，正面/背面各自渲染，翻转后文字不会镜像。
class FlipCard extends StatelessWidget {
  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.showBack,
    this.duration = const Duration(milliseconds: 400),
  });

  final Widget front;
  final Widget back;
  final bool showBack;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: showBack ? 1 : 0),
      duration: duration,
      curve: Curves.easeInOutCubic,
      builder: (BuildContext context, double value, Widget? child) {
        final double angle = value * math.pi;
        final bool isBack = value > 0.5;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: isBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: back,
                )
              : front,
        );
      },
    );
  }
}

/// 翻卡外壳：纸卡质感 —— 实色纸面 + 发丝描边 + 一条横线（像笔记纸的横格），不用渐变与投影。
class FlipCardShell extends StatelessWidget {
  const FlipCardShell({
    super.key,
    required this.child,
    this.highlight = false,
  });

  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color surface = Theme.of(context).cardColor;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: highlight
            ? Color.alphaBlend(
                scheme.primary.withValues(alpha: 0.035),
                surface,
              )
            : surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg + 2),
        border: Border.all(color: scheme.outlineVariant, width: 1),
      ),
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }
}
