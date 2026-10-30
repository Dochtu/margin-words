import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'state/settings_store.dart';
import 'ui/pages/home_page.dart';

class WordbookApp extends StatelessWidget {
  const WordbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeMode themeMode = context.select<SettingsStore, ThemeMode>(
      (SettingsStore s) => s.themeMode,
    );

    return MaterialApp(
      title: '错题单词本',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomePage(),
    );
  }
}
