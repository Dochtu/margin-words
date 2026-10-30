import 'package:flutter/material.dart';

import '../core/app_date.dart';
import '../data/word.dart';
import '../data/word_dao.dart';
import '../data/word_draft.dart';
import 'settings_store.dart';

/// 全局单词状态：今日回顾 + 整体回顾共用同一份 DAO。
class WordStore extends ChangeNotifier {
  WordStore({required WordDao dao, required SettingsStore settings})
      : _dao = dao,
        _settings = settings;

  final WordDao _dao;
  final SettingsStore _settings;

  // ---------------------------------------------------------- 今日回顾
  bool _loadingToday = true;
  List<Word> _todayWords = const <Word>[];
  String? _todayError;

  bool get loadingToday => _loadingToday;
  List<Word> get todayWords => _todayWords;
  String? get todayError => _todayError;

  // ---------------------------------------------------------- 整体回顾
  bool _loadingLibrary = true;
  List<Word> _libraryWords = const <Word>[];
  String _keyword = '';
  DateTimeRange? _range;
  bool? _masteredFilter;
  WordSortMode _sortMode = WordSortMode.newest;
  String? _libraryError;

  bool get loadingLibrary => _loadingLibrary;
  List<Word> get libraryWords => _libraryWords;
  String get keyword => _keyword;
  DateTimeRange? get range => _range;
  bool? get masteredFilter => _masteredFilter;
  WordSortMode get sortMode => _sortMode;
  String? get libraryError => _libraryError;

  bool get hasActiveFilter =>
      _keyword.trim().isNotEmpty || _range != null || _masteredFilter != null;

  // ---------------------------------------------------------- 统计
  int _totalCount = 0;
  int _masteredCount = 0;

  int get totalCount => _totalCount;
  int get masteredCount => _masteredCount;
  int get todayCount => _todayWords.length;
  int get todayMastered => _todayWords.where((Word w) => w.mastered).length;

  // ------------------------------------------------------------ 读取

  Future<void> loadAll() async {
    await Future.wait(<Future<void>>[loadToday(), loadLibrary(), loadStats()]);
  }

  Future<void> loadToday() async {
    _loadingToday = true;
    _todayError = null;
    notifyListeners();
    try {
      _todayWords = await _dao.wordsByStudyDate(AppDate.today());
    } catch (e) {
      _todayError = '读取今日单词失败：$e';
      _todayWords = const <Word>[];
    } finally {
      _loadingToday = false;
      notifyListeners();
    }
  }

  Future<void> loadLibrary() async {
    _loadingLibrary = true;
    _libraryError = null;
    notifyListeners();
    try {
      _libraryWords = await _dao.query(
        startDate: _range == null ? null : AppDate.ymd(_range!.start),
        endDate: _range == null ? null : AppDate.ymd(_range!.end),
        keyword: _keyword,
        mastered: _masteredFilter,
        sort: _sortMode,
      );
    } catch (e) {
      _libraryError = '读取单词失败：$e';
      _libraryWords = const <Word>[];
    } finally {
      _loadingLibrary = false;
      notifyListeners();
    }
  }

  Future<void> loadStats() async {
    try {
      _totalCount = await _dao.countAll();
      _masteredCount = await _dao.countMastered();
    } catch (_) {
      _totalCount = 0;
      _masteredCount = 0;
    }
    notifyListeners();
  }

  Future<Set<String>> existingKeys(Iterable<String> keys) =>
      _dao.existingKeys(keys);

  /// 已掌握单词列表：给筛选智能体理解「只保留我不认识的」用。
  /// 失败时返回空列表（不影响识别主流程）。
  Future<List<String>> masteredWordList({int limit = 400}) async {
    try {
      final List<Word> rows =
          await _dao.query(mastered: true, sort: WordSortMode.newest);
      return rows.take(limit).map((Word w) => w.word).toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  // ------------------------------------------------------------ 筛选

  Future<void> setKeyword(String value) async {
    if (_keyword == value) return;
    _keyword = value;
    await loadLibrary();
  }

  Future<void> setRange(DateTimeRange? value) async {
    _range = value;
    await loadLibrary();
  }

  Future<void> setMasteredFilter(bool? value) async {
    if (_masteredFilter == value) return;
    _masteredFilter = value;
    await loadLibrary();
  }

  Future<void> setSortMode(WordSortMode value) async {
    if (_sortMode == value) return;
    _sortMode = value;
    await loadLibrary();
  }

  Future<void> clearFilters() async {
    _keyword = '';
    _range = null;
    _masteredFilter = null;
    await loadLibrary();
  }

  // ------------------------------------------------------------ 写入

  Future<SaveReport> saveDrafts(
    List<WordDraft> drafts, {
    String? imagePath,
  }) async {
    final SaveReport report = await _dao.saveDrafts(
      drafts,
      merge: _settings.mergeDuplicates,
      imagePath: imagePath,
    );
    await loadAll();
    return report;
  }

  Future<void> markReview(int id, {required bool mastered}) async {
    await _dao.markReview(id, mastered: mastered);
    final int now = DateTime.now().millisecondsSinceEpoch;

    _todayWords = _todayWords.map((Word w) {
      if (w.id != id) return w;
      return w.copyWith(
        mastered: mastered,
        reviewCount: w.reviewCount + 1,
        lastReviewAt: now,
        updatedAt: now,
      );
    }).toList(growable: false);

    _libraryWords = _libraryWords.map((Word w) {
      if (w.id != id) return w;
      return w.copyWith(
        mastered: mastered,
        reviewCount: w.reviewCount + 1,
        lastReviewAt: now,
        updatedAt: now,
      );
    }).toList(growable: false);

    notifyListeners();
    await loadStats();
  }

  Future<void> editWord(
    Word word, {
    required String text,
    required String phonetic,
    required String meaning,
    required bool mastered,
  }) async {
    await _dao.updateWord(
      word.id,
      word: text,
      phonetic: phonetic,
      meaning: meaning,
      mastered: mastered,
    );
    await loadAll();
  }

  Future<void> deleteWord(int id) async {
    await _dao.deleteById(id);
    await loadAll();
  }

  /// 多选删除：一次事务处理，删完统一刷新今日 / 全部 / 统计。
  Future<void> deleteWords(Iterable<int> ids) async {
    final List<int> list = ids.toSet().toList(growable: false);
    if (list.isEmpty) return;
    await _dao.deleteByIds(list);
    await loadAll();
  }

  /// 多选标记掌握状态。
  Future<void> setMasteredFor(Iterable<int> ids, bool mastered) async {
    final List<int> list = ids.toSet().toList(growable: false);
    if (list.isEmpty) return;
    await _dao.setMasteredByIds(list, mastered);
    await loadAll();
  }

  Future<void> clearAllData() async {
    await _dao.clearAll();
    await loadAll();
  }
}
