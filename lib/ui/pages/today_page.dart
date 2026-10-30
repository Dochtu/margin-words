import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_date.dart';
import '../../data/word.dart';
import '../../state/settings_store.dart';
import '../../state/word_store.dart';
import '../widgets/flip_card.dart';
import '../widgets/state_views.dart';
import 'chat_page.dart';

/// 每日错题回顾：今天上传的单词，翻卡逐词过一遍。
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  int _index = 0;
  bool _flipped = false;
  ReviewMode? _modeCache;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WordStore>().loadToday();
    });
  }

  void _next() {
    setState(() {
      _index++;
      _flipped = false;
    });
  }

  void _restart() {
    setState(() {
      _index = 0;
      _flipped = false;
    });
  }

  Future<void> _judge(Word word, bool mastered) async {
    await context.read<WordStore>().markReview(word.id, mastered: mastered);
    if (!mounted) return;
    _next();
  }

  Future<void> _openChat() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ChatPage()),
    );
    if (!mounted) return;
    context.read<WordStore>().loadToday();
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    final WordStore store = context.watch<WordStore>();
    final SettingsStore settings = context.watch<SettingsStore>();
    final ReviewMode mode = settings.reviewMode;

    // 切换模式后重新从第一张开始
    if (_modeCache != mode) {
      _modeCache = mode;
      _index = 0;
      _flipped = false;
    }

    final List<Word> words = store.todayWords;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Header(
              todayCount: words.length,
              masteredCount: store.todayMastered,
              mode: mode,
              onModeChanged: (ReviewMode value) =>
                  context.read<SettingsStore>().setReviewMode(value),
            ),
            Expanded(
              child: _buildBody(context, store, words, mode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WordStore store,
    List<Word> words,
    ReviewMode mode,
  ) {
    if (store.loadingToday) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (store.todayError != null) {
      return StateView(
        icon: Icons.error_outline_rounded,
        title: '读取失败',
        message: store.todayError,
        action: FilledButton(
          onPressed: () => context.read<WordStore>().loadToday(),
          child: const Text('重试'),
        ),
      );
    }
    if (words.isEmpty) {
      return StateView(
        icon: Icons.inbox_outlined,
        title: '今天还没有错题单词',
        message: '拍一张试卷或课本的照片，识别后会自动进入今天的回顾。\n也可以从相册选图。',
        action: FilledButton.icon(
          onPressed: _openChat,
          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
          label: const Text('拍照识别'),
        ),
        secondaryAction: TextButton(
          onPressed: () => context.read<WordStore>().loadToday(),
          child: const Text('刷新'),
        ),
      );
    }

    if (_index >= words.length) {
      return _CompletionView(
        total: words.length,
        mastered: store.todayMastered,
        onRestart: _restart,
        onRecognize: _openChat,
      );
    }

    final Word word = words[_index];
    final bool enFirst = mode == ReviewMode.enToCn;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
          child: Row(
            children: <Widget>[
              Text(
                '${_index + 1} / ${words.length}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / words.length,
                    minHeight: 4,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.06),
                  ),
                ),
              ),
              if (word.mastered) ...<Widget>[
                const SizedBox(width: 10),
                Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _flipped = !_flipped),
              child: FlipCard(
                showBack: _flipped,
                front: _Face(
                  label: enFirst ? '英文 → 中文' : '中文 → 英文',
                  primary: enFirst ? word.word : word.meaning,
                  secondary: enFirst ? word.phonetic : '',
                  isWord: enFirst,
                  hint: '点击卡片看答案',
                ),
                back: _Face(
                  label: enFirst ? '释义' : '答案',
                  primary: enFirst ? word.meaning : word.word,
                  secondary: enFirst ? '' : word.phonetic,
                  isWord: !enFirst,
                  hint: '',
                ),
              ),
            ),
          ),
        ),
        Padding(
          // 底部预留 FAB 的高度，避免「已掌握」按钮被悬浮按钮压住
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 74),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _judge(word, false),
                  child: const Text('仍不熟'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _judge(word, true),
                  child: const Text('已掌握'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.todayCount,
    required this.masteredCount,
    required this.mode,
    required this.onModeChanged,
  });

  final int todayCount;
  final int masteredCount;
  final ReviewMode mode;
  final ValueChanged<ReviewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '今日回顾',
                style: TextStyle(
                  fontSize: 26,
                  height: 1.1,
                  letterSpacing: -0.6,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                AppDate.todayLabel(),
                style: TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 0.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            todayCount == 0
                ? '今天还没有新增单词'
                : '共 $todayCount 个 · 已掌握 $masteredCount 个',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          _ModeSwitch(value: mode, onChanged: onModeChanged),
        ],
      ),
    );
  }
}

/// 模式切换：下划线式 tab，替代满屏的 SegmentedButton（更克制、更像出版物）。
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.value, required this.onChanged});

  final ReviewMode value;
  final ValueChanged<ReviewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    Widget item(ReviewMode mode) {
      final bool active = value == mode;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(mode),
        child: Padding(
          padding: const EdgeInsets.only(right: 22, bottom: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                mode.label,
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 0.3,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 2,
                width: active ? 26 : 0,
                color: scheme.primary,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          item(ReviewMode.enToCn),
          item(ReviewMode.cnToEn),
        ],
      ),
    );
  }
}

/// 卡片的一面。
class _Face extends StatelessWidget {
  const _Face({
    required this.label,
    required this.primary,
    required this.secondary,
    required this.isWord,
    required this.hint,
  });

  final String label;
  final String primary;
  final String secondary;
  final bool isWord;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return FlipCardShell(
      highlight: isWord,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      primary.isEmpty ? '（暂无内容）' : primary,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isWord ? 32 : 21,
                        height: isWord ? 1.25 : 1.65,
                        fontWeight: isWord ? FontWeight.w700 : FontWeight.w500,
                        letterSpacing: isWord ? 0.2 : 0,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (secondary.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        secondary,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (hint.isNotEmpty)
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.touch_app_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CompletionView extends StatelessWidget {
  const _CompletionView({
    required this.total,
    required this.mastered,
    required this.onRestart,
    required this.onRecognize,
  });

  final int total;
  final int mastered;
  final VoidCallback onRestart;
  final VoidCallback onRecognize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.done_all_rounded,
                size: 24,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '今天的单词过完啦',
              style: TextStyle(
                fontSize: 16.5,
                letterSpacing: -0.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '共 $total 个单词，已掌握 $mastered 个。\n明天再来一遍，记忆会更牢。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                OutlinedButton(
                  onPressed: onRestart,
                  child: const Text('再来一轮'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: onRecognize,
                  child: const Text('继续添加'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '已掌握 ${(mastered / total * 100).round()}%',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
