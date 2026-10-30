import 'package:sqflite/sqflite.dart';

/// SQLite 建库/升级。
///
/// 只使用 sqflite，无需任何 Android 原生配置；
/// 数据库文件位于应用私有目录 `/data/data/com.lz.wordbook/databases/wordbook.db`，
/// 卸载应用即随沙箱一起删除。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String fileName = 'wordbook.db';
  static const int schemaVersion = 1;

  Future<Database>? _opening;

  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    final String path = '${await getDatabasesPath()}/$fileName';
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database db, int version) async {
        final Batch batch = db.batch();
        batch.execute(createWordsTable);
        batch.execute(createPhoneticCacheTable);
        batch.execute('CREATE INDEX idx_words_word_key ON words(word_key)');
        batch.execute('CREATE INDEX idx_words_study_date ON words(study_date)');
        batch.execute('CREATE INDEX idx_words_created_at ON words(created_at)');
        batch.execute('CREATE INDEX idx_words_mastered ON words(mastered)');
        await batch.commit(noResult: true);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        // v1 为首个版本，暂无升级脚本。
        // 后续新增字段时在这里按 oldVersion 逐级 ALTER TABLE，
        // 不要用 drop 重建，避免用户数据丢失。
      },
    );
  }

  /// 单词主表。
  static const String createWordsTable = '''
CREATE TABLE IF NOT EXISTS words (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  word              TEXT    NOT NULL,
  word_key          TEXT    NOT NULL,
  phonetic          TEXT    NOT NULL DEFAULT '',
  meaning           TEXT    NOT NULL DEFAULT '',
  source_image_path TEXT,
  created_at        INTEGER NOT NULL,
  study_date        TEXT    NOT NULL,
  mastered          INTEGER NOT NULL DEFAULT 0,
  review_count      INTEGER NOT NULL DEFAULT 0,
  last_review_at    INTEGER,
  updated_at        INTEGER NOT NULL
)''';

  /// 音标校验缓存：本地词典命中的结果缓存下来，减少联网次数。
  static const String createPhoneticCacheTable = '''
CREATE TABLE IF NOT EXISTS phonetic_cache (
  word_key   TEXT PRIMARY KEY,
  phonetic   TEXT NOT NULL,
  source     TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)''';
}
