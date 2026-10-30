import 'package:flutter/material.dart';

import 'all_words_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';
import 'today_page.dart';

/// 底部导航：今日回顾 / 全部单词 / 我的。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  Future<void> _openChat() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ChatPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          TodayPage(),
          AllWordsPage(),
          SettingsPage(),
        ],
      ),
      floatingActionButton: _index == 2
          ? null
          : FloatingActionButton.extended(
              onPressed: _openChat,
              icon: const Icon(Icons.forum_outlined, size: 20),
              label: const Text(
                '提取单词',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today_rounded),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: '全部',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
