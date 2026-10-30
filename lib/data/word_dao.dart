import 'package:sqflite/sqflite.dart';

import '../core/app_date.dart';
import '../core/word_text.dart';
import 'app_database.dart';
import 'word.dart';
import 'word_draft.dart';

/// `words` 表的数据访问层。所有 SQL 都集中在这里。
class WordDao {
  WordDao([AppDatabase? database]) : _db = database ?? AppDatabase.instance;

  final AppDatabase _db;

  Future<Database> get _database => _db.database;

  static const String _table = 'words';

  // ---------------------------------------------------------------- 查询

  /// 今日回顾：学习日期 = 今天，按上传时间倒序。
  Future<List<Word>> wordsByStudyDate(String studyDate) async {
    final Database db = await _database;
    final List<Map<String, Object?>> rows = await db.query(
      _table,
      where: 'study_date = ?',
      whereArgs: <Object?>[studyDate],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Word.fromMap).toList(growable: false);
  }

  /// 整体回顾：关键词 / 日期区间 / 掌握状态 / 排序。
  Future<List<Word>> query({
    String? startDate,
    String? endDate,
    String? keyword,
    bool? mastered,
    WordSortMode sort = WordSortMode.newest,
  }) async {
    final Database db = await _database;
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];

    if (startDate != null && startDate.isNotEmpty) {
      where.add('study_date >= ?');
      args.add(startDate);
    }
    if (endDate != null && endDate.isNotEmpty) {
      where.add('study_date <= ?');
      args.add(endDate);
    }
    if (mastered != null) {
      where.add('mastered = ?');
      args.add(mastered ? 1 : 0);
    }

    final String kw = (keyword ?? '').trim();
    if (kw.isNotEmpty) {
      // 用户输入里的 % _ 属于 LIKE 通配符，先转义，避免意外全表匹配
      final String escaped =
          kw.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      final String like = '%$escaped%';
      where.add("(word LIKE ? ESCAPE '\\' OR meaning LIKE ? ESCAPE '\\'"
          " OR phonetic LIKE ? ESCAPE '\\')");
      args.addAll(<Object?>[like, like, like]);
    }

    final List<Map<String, Object?>> rows = await db.query(
      _table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: sort.orderBy,
    );
    return rows.map(Word.fromMap).toList(growable: false);
  }

  /// 已存在单词的去重键集合（确认页用来提示“将合并”）。
  Future<Set<String>> existingKeys(Iterable<String> keys) async {
    final List<String> list = keys
        .map((String e) => WordText.keyOf(e))
        .where((String e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (list.isEmpty) return <String>{};

    final Database db = await _database;
    final String placeholders = List<String>.filled(list.length, '?').join(',');
    final List<Map<String, Object?>> rows = await db.query(
      _table,
      columns: <String>['word_key'],
      where: 'word_key IN ($placeholders)',
      whereArgs: list,
    );
    return rows
        .map((Map<String, Object?> row) => row['word_key'] as String? ?? '')
        .where((String e) => e.isNotEmpty)
        .toSet();
  }

  Future<int> countAll() async {
    final Database db = await _database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_table'),
        ) ??
        0;
  }

  Future<int> countByStudyDate(String studyDate) async {
    final Database db = await _database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM $_table WHERE study_date = ?',
            <Object?>[studyDate],
          ),
        ) ??
        0;
  }

  Future<int> countMastered() async {
    final Database db = await _database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_table WHERE mastered = 1'),
        ) ??
        0;
  }

  // ---------------------------------------------------------------- 写入

  /// 批量保存识别结果。
  ///
  /// [merge] 为 true 时：同名单词更新释义/音标并刷新时间（默认行为）；
  /// 为 false 时：一律新增一条记录。
  Future<SaveReport> saveDrafts(
    List<WordDraft> drafts, {
    required bool merge,
    String? studyDate,
    String? imagePath,
  }) async {
    final Database db = await _database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final String date = studyDate ?? AppDate.today();

    int inserted = 0;
    int merged = 0;
    int skipped = 0;

    await db.transaction((Transaction txn) async {
      for (final WordDraft draft in drafts) {
        if (!draft.selected || draft.isEmpty) {
          skipped++;
          continue;
        }
        final String cleanWord = WordText.cleanWord(draft.word);
        if (cleanWord.isEmpty) {
          skipped++;
          continue;
        }
        final String key = WordText.keyOf(cleanWord);
        final String phonetic = WordText.cleanPhonetic(draft.phonetic);
        final String meaning = WordText.cleanMeaning(draft.meaning);

        if (merge) {
          final List<Map<String, Object?>> found = await txn.query(
            _table,
            columns: <String>['id'],
            where: 'word_key = ?',
            whereArgs: <Object?>[key],
            orderBy: 'created_at DESC',
            limit: 1,
          );
          if (found.isNotEmpty) {
            final int id = (found.first['id'] as num).toInt();
            await txn.update(
              _table,
              <String, Object?>{
                if (phonetic.isNotEmpty) 'phonetic': phonetic,
                if (meaning.isNotEmpty) 'meaning': meaning,
                if (imagePath != null) 'source_image_path': imagePath,
                'word': cleanWord,
                'created_at': now,
                'study_date': date,
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: <Object?>[id],
            );
            merged++;
            continue;
          }
        }

        await txn.insert(_table, <String, Object?>{
          'word': cleanWord,
          'word_key': key,
          'phonetic': phonetic,
          'meaning': meaning,
          'source_image_path': imagePath,
          'created_at': now,
          'study_date': date,
          'mastered': 0,
          'review_count': 0,
          'last_review_at': null,
          'updated_at': now,
        });
        inserted++;
      }
    });

    return SaveReport(inserted: inserted, merged: merged, skipped: skipped);
  }

  /// 回顾时标记「已掌握 / 仍不熟」，复习次数 +1。
  Future<void> markReview(int id, {required bool mastered}) async {
    final Database db = await _database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate(
      'UPDATE $_table SET review_count = review_count + 1, '
      'last_review_at = ?, mastered = ?, updated_at = ? WHERE id = ?',
      <Object?>[now, mastered ? 1 : 0, now, id],
    );
  }

  /// 编辑单词（整体回顾页）。
  Future<void> updateWord(
    int id, {
    required String word,
    required String phonetic,
    required String meaning,
    required bool mastered,
  }) async {
    final Database db = await _database;
    final String cleanWord = WordText.cleanWord(word);
    await db.update(
      _table,
      <String, Object?>{
        'word': cleanWord.isEmpty ? word.trim() : cleanWord,
        'word_key': WordText.keyOf(cleanWord.isEmpty ? word : cleanWord),
        'phonetic': WordText.cleanPhonetic(phonetic),
        'meaning': WordText.cleanMeaning(meaning),
        'mastered': mastered ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteById(int id) async {
    final Database db = await _database;
    await db.delete(_table, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// 多选删除。SQLite 的 IN 参数分块，避免一次绑定过多变量。
  Future<void> deleteByIds(Iterable<int> ids) async {
    final List<int> list = ids.toSet().toList(growable: false);
    if (list.isEmpty) return;
    final Database db = await _database;
    await db.transaction((Transaction txn) async {
      for (int start = 0; start < list.length; start += 500) {
        final int end = start + 500 < list.length ? start + 500 : list.length;
        final List<int> chunk = list.sublist(start, end);
        final String placeholders =
            List<String>.filled(chunk.length, '?').join(',');
        await txn.delete(
          _table,
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
      }
    });
  }

  /// 多选标记已掌握 / 仍不熟。
  Future<void> setMasteredByIds(Iterable<int> ids, bool mastered) async {
    final List<int> list = ids.toSet().toList(growable: false);
    if (list.isEmpty) return;
    final Database db = await _database;
    final int now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((Transaction txn) async {
      for (int start = 0; start < list.length; start += 500) {
        final int end = start + 500 < list.length ? start + 500 : list.length;
        final List<int> chunk = list.sublist(start, end);
        final String placeholders =
            List<String>.filled(chunk.length, '?').join(',');
        await txn.update(
          _table,
          <String, Object?>{'mastered': mastered ? 1 : 0, 'updated_at': now},
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
      }
    });
  }

  Future<void> clearAll() async {
    final Database db = await _database;
    await db.delete(_table);
    await db.delete('phonetic_cache');
  }

  // ------------------------------------------------------- 音标缓存

  Future<String?> cachedPhonetic(String wordKey) async {
    final Database db = await _database;
    final List<Map<String, Object?>> rows = await db.query(
      'phonetic_cache',
      columns: <String>['phonetic'],
      where: 'word_key = ?',
      whereArgs: <Object?>[wordKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['phonetic'] as String?;
  }

  Future<void> cachePhonetic(
    String wordKey,
    String phonetic, {
    String source = 'dictionary_api',
  }) async {
    if (wordKey.isEmpty || phonetic.isEmpty) return;
    final Database db = await _database;
    await db.insert(
      'phonetic_cache',
      <String, Object?>{
        'word_key': wordKey,
        'phonetic': phonetic,
        'source': source,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
