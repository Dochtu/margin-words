import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/word.dart';
import '../../state/word_store.dart';
import '../widgets/state_views.dart';
import '../widgets/word_edit_sheet.dart';
import '../widgets/word_tile.dart';

/// 整体错题回顾：全部单词 + 日期筛选 + 关键词搜索 + 排序 + 掌握状态筛选。
class AllWordsPage extends StatefulWidget {
  const AllWordsPage({super.key});

  @override
  State<AllWordsPage> createState() => _AllWordsPageState();
}

class _AllWordsPageState extends State<AllWordsPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  bool _selecting = false;
  final Set<int> _selected = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WordStore>().loadLibrary();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (mounted) context.read<WordStore>().setKeyword(value);
    });
  }

  Future<void> _pickRange(WordStore store) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: store.range,
      helpText: '按学习日期筛选',
      saveText: '确定',
      cancelText: '取消',
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null && mounted) {
      await store.setRange(picked);
    }
  }

  Future<void> _deleteWord(Word word) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除这个单词？'),
        content: Text(
          '「${word.word}」及其复习记录会一并删除，无法恢复。',
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<WordStore>().deleteWord(word.id);
    }
  }

  List<Word> _selectedWords(List<Word> words) {
    return words
        .where((Word word) => _selected.contains(word.id))
        .toList(growable: false);
  }

  void _enterSelection(Word word) {
    if (_selecting) {
      _toggleSelection(word);
      return;
    }
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(word.id);
    });
  }

  void _toggleSelection(Word word) {
    setState(() {
      if (!_selected.remove(word.id)) {
        _selected.add(word.id);
      }
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _exitSelection() {
    if (!_selecting && _selected.isEmpty) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelectAll(List<Word> words) {
    setState(() {
      final bool allSelected = words.isNotEmpty &&
          words.every((Word word) => _selected.contains(word.id));
      if (allSelected) {
        _selected.clear();
        _selecting = false;
      } else {
        _selected
          ..clear()
          ..addAll(words.map((Word word) => word.id));
      }
    });
  }

  Future<void> _deleteSelected(List<Word> words) async {
    final List<Word> selected = _selectedWords(words);
    if (selected.isEmpty) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('删除选中的 ${selected.length} 个单词？'),
        content: const Text(
          '这些单词及其复习记录会一并删除，无法恢复。',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final int count = selected.length;
    await context.read<WordStore>().deleteWords(
          selected.map((Word word) => word.id),
        );
    if (!mounted) return;
    _exitSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除 $count 个单词')),
    );
  }

  Future<void> _markSelected(List<Word> words, bool mastered) async {
    final List<Word> selected = _selectedWords(words);
    if (selected.isEmpty) return;
    final int count = selected.length;
    await context.read<WordStore>().setMasteredFor(
          selected.map((Word word) => word.id),
          mastered,
        );
    if (!mounted) return;
    _exitSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已标记 $count 个为${mastered ? '已掌握' : '仍不熟'}'),
      ),
    );
  }

  Widget _buildHeader(WordStore store, List<Word> words) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (_selecting) {
      final List<Word> selected = _selectedWords(words);
      final bool allSelected =
          words.isNotEmpty && selected.length == words.length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: '退出多选',
              onPressed: _exitSelection,
              icon: const Icon(Icons.close_rounded, size: 22),
            ),
            Expanded(
              child: Text(
                '已选 ${selected.length} 个',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            IconButton(
              tooltip: allSelected ? '取消全选' : '全选',
              onPressed: words.isEmpty ? null : () => _toggleSelectAll(words),
              icon: Icon(
                allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                size: 22,
              ),
            ),
            PopupMenuButton<bool>(
              tooltip: '标记掌握状态',
              enabled: selected.isNotEmpty,
              onSelected: (bool mastered) => _markSelected(words, mastered),
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<bool>>[
                PopupMenuItem<bool>(
                  value: true,
                  height: 44,
                  child: Text('标记已掌握', style: TextStyle(fontSize: 14)),
                ),
                PopupMenuItem<bool>(
                  value: false,
                  height: 44,
                  child: Text('标记仍不熟', style: TextStyle(fontSize: 14)),
                ),
              ],
              icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
            ),
            IconButton(
              tooltip: '删除选中',
              onPressed:
                  selected.isEmpty ? null : () => _deleteSelected(words),
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 22,
                color: selected.isEmpty
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
                    : scheme.error,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            '全部单词',
            style: TextStyle(
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          Flexible(
            child: Text(
              '共 ${store.totalCount} 个 · 长按多选',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final WordStore store = context.watch<WordStore>();
    final List<Word> words = store.libraryWords;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildHeader(store, words),
            if (!_selecting) ...<Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索单词 / 音标 / 释义',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              store.setKeyword('');
                              setState(() {});
                            },
                          ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 10),
              _FilterBar(
                store: store,
                onPickRange: () => _pickRange(store),
              ),
              const SizedBox(height: 6),
            ],
            Expanded(child: _buildList(store, words)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(WordStore store, List<Word> words) {
    if (store.loadingLibrary) {
      return const ListSkeleton();
    }
    if (store.libraryError != null) {
      return StateView(
        icon: Icons.error_outline_rounded,
        title: '读取失败',
        message: store.libraryError,
        action: FilledButton(
          onPressed: () => context.read<WordStore>().loadLibrary(),
          child: const Text('重试'),
        ),
      );
    }
    if (words.isEmpty) {
      if (store.hasActiveFilter) {
        return StateView(
          icon: Icons.filter_alt_off_outlined,
          title: '没有符合条件的单词',
          message: '试试换个关键词，或清除筛选条件。',
          action: OutlinedButton(
            onPressed: () {
              _searchController.clear();
              context.read<WordStore>().clearFilters();
            },
            child: const Text('清除筛选'),
          ),
        );
      }
      return const StateView(
        icon: Icons.menu_book_outlined,
        title: '还没有保存任何单词',
        message: '在「今日」页点右下角的「拍照识别」，\n识别并确认后就会出现在这里。',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: words.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final Word word = words[index];
        return WordTile(
          key: ValueKey<int>(word.id),
          word: word,
          selectionMode: _selecting,
          selected: _selected.contains(word.id),
          onSelect: () => _toggleSelection(word),
          onLongPress: () => _enterSelection(word),
          onEdit: _selecting ? null : () => showWordEditSheet(context, word),
          onDelete: _selecting ? null : () => _deleteWord(word),
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.store, required this.onPickRange});

  final WordStore store;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final String rangeLabel = store.range == null
        ? '日期'
        : '${store.range!.start.month}.${store.range!.start.day}'
            '–${store.range!.end.month}.${store.range!.end.day}';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          _Chip(
            label: '全部',
            selected: store.masteredFilter == null,
            onTap: () => context.read<WordStore>().setMasteredFilter(null),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: '已掌握',
            selected: store.masteredFilter == true,
            onTap: () => context.read<WordStore>().setMasteredFilter(true),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: '仍不熟',
            selected: store.masteredFilter == false,
            onTap: () => context.read<WordStore>().setMasteredFilter(false),
          ),
          const SizedBox(width: 8),
          _FilterButton(
            icon: Icons.calendar_today_outlined,
            label: rangeLabel,
            active: store.range != null,
            onTap: onPickRange,
            onClear: store.range == null
                ? null
                : () => context.read<WordStore>().setRange(null),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<WordSortMode>(
            tooltip: '排序',
            color: Theme.of(context).cardColor,
            onSelected: (WordSortMode value) =>
                context.read<WordStore>().setSortMode(value),
            itemBuilder: (BuildContext context) => WordSortMode.values
                .map(
                  (WordSortMode mode) => PopupMenuItem<WordSortMode>(
                    value: mode,
                    height: 44,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          mode == store.sortMode
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color: mode == store.sortMode
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(mode.label, style: const TextStyle(fontSize: 13.5)),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
            child: _FilterButton(
              icon: Icons.sort_rounded,
              label: store.sortMode.label,
              active: store.sortMode != WordSortMode.newest,
              onTap: null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.45)
                : scheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            letterSpacing: 0.2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color fg = active ? scheme.primary : scheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
          left: 11,
          right: onClear == null ? 11 : 4,
          top: 7,
          bottom: 7,
        ),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? scheme.primary.withValues(alpha: 0.45)
                : scheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
            if (onClear != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.close_rounded, size: 14, color: fg),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}
