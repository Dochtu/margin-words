import 'package:flutter/material.dart';

/// 视觉体系：纸感文具（Paper & Ink）。
///
/// 设计取舍（针对"AI 味"的几个典型特征逐条回避）：
///   1. 不用紫蓝渐变 —— 主色是墨绿，强调色是陶土，全部纯色，梯度只出现在亮度上；
///   2. 不用 16–20 的大圆角 + 大投影 —— 圆角收到 10/12，卡片改用 1px 发丝描边分层；
///   3. 不用发光/玻璃拟态 —— 所有表面都是实色，层级靠描边、字重和留白；
///   4. 强调色克制 —— 只用于"当前选中/关键动作"，不大面积铺色；
///   5. 配色取自纸张与墨水 —— 暖米白 #F7F4ED、墨色 #1D1C19，长时间看不刺眼。
class AppTheme {
  const AppTheme._();

  // ---------------------------------------------------------------- 浅色
  static const Color paper = Color(0xFFF7F4ED); // 页面底色：暖米白
  static const Color surface = Color(0xFFFFFFFF); // 卡片：纸白
  static const Color ink = Color(0xFF1D1C19); // 正文：墨
  static const Color inkMuted = Color(0xFF6B665C); // 次级文字
  static const Color inkGreen = Color(0xFF2F5A4B); // 主色：墨绿
  static const Color clay = Color(0xFFB5654A); // 强调：陶土
  static const Color hairline = Color(0xFFE5DFD3); // 发丝线

  // ---------------------------------------------------------------- 深色
  static const Color paperDark = Color(0xFF151412);
  static const Color surfaceDark = Color(0xFF1C1B18);
  static const Color inkDark = Color(0xFFEDEAE3);
  static const Color inkMutedDark = Color(0xFF9A958A);
  static const Color inkGreenDark = Color(0xFF8FC3AC);
  static const Color clayDark = Color(0xFFD9906F);
  static const Color hairlineDark = Color(0xFF2E2C27);

  /// 兼容旧引用（图标/启动页等地方用它取主色）。
  static const Color seed = inkGreen;

  // 圆角：整体收紧一档，避免"圆乎乎"的塑料感
  static const double radiusSm = 8;
  static const double radiusMd = 10;
  static const double radiusLg = 12;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final Color bg = isDark ? paperDark : paper;
    final Color card = isDark ? surfaceDark : surface;
    final Color fg = isDark ? inkDark : ink;
    final Color muted = isDark ? inkMutedDark : inkMuted;
    final Color primary = isDark ? inkGreenDark : inkGreen;
    final Color accent = isDark ? clayDark : clay;
    final Color line = isDark ? hairlineDark : hairline;

    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: isDark ? const Color(0xFF10201A) : Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      surface: card,
      onSurface: fg,
      onSurfaceVariant: muted,
      outline: line,
      outlineVariant: line,
      surfaceContainerLowest: bg,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: isDark
          ? const Color(0xFF232219)
          : const Color(0xFFF1EDE4),
      surfaceContainerHighest: isDark
          ? const Color(0xFF2A2823)
          : const Color(0xFFEAE4D8),
      error: isDark ? const Color(0xFFE08A7A) : const Color(0xFF9B3B2C),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardColor: card,
      dividerColor: line,
      splashFactory: InkSparkle.splashFactory,
      fontFamilyFallback: const <String>[
        'Noto Sans SC',
        'Source Han Sans SC',
        'Microsoft YaHei',
      ],
      // 标题统一收一点字距，中文更"紧"，不像默认模板那样松散
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 26,
          height: 1.2,
          letterSpacing: -0.4,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
        titleLarge: TextStyle(
          fontSize: 17,
          height: 1.3,
          letterSpacing: -0.1,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
        bodyMedium: TextStyle(fontSize: 14, height: 1.6, color: fg),
        bodySmall: TextStyle(fontSize: 12.5, height: 1.6, color: muted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          letterSpacing: -0.1,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: line,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 60,
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: primary.withValues(alpha: isDark ? 0.20 : 0.10),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            letterSpacing: 0.2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? primary : muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? primary : muted,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF232219) : const Color(0xFFF2EEE5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        hintStyle: TextStyle(
          fontSize: 14,
          color: muted.withValues(alpha: 0.75),
        ),
        helperStyle: TextStyle(fontSize: 11, color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: primary.withValues(alpha: 0.7), width: 1.2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2E2C27) : ink,
        contentTextStyle: TextStyle(
          fontSize: 13.5,
          color: isDark ? inkDark : const Color(0xFFF7F4ED),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: isDark ? const Color(0xFF10201A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            letterSpacing: 0.1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          foregroundColor: fg,
          side: BorderSide(color: line, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            letterSpacing: 0.1,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          textStyle: const TextStyle(fontSize: 13.5),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: isDark ? const Color(0xFF10201A) : Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        extendedTextStyle: const TextStyle(
          fontSize: 13.5,
          letterSpacing: 0.2,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg + 2),
        ),
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
        contentTextStyle: TextStyle(fontSize: 13.5, height: 1.7, color: muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: line, width: 1),
        backgroundColor: card,
        labelStyle: TextStyle(fontSize: 12.5, color: fg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      // 分段控件统一成"细边框 + 选中淡底"，避免默认的实心大色块
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12.5, letterSpacing: 0.2),
          ),
          side: WidgetStateProperty.all(BorderSide(color: line, width: 1)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? primary.withValues(alpha: isDark ? 0.18 : 0.09)
                : Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected) ? primary : muted;
          }),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: line, width: 1),
        ),
        textStyle: TextStyle(fontSize: 13.5, color: fg),
      ),
      splashColor: primary.withValues(alpha: 0.06),
      highlightColor: primary.withValues(alpha: 0.04),
    );
  }
}
