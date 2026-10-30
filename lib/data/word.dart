/// 单词实体，对应 SQLite 表 `words`。
class Word {
  const Word({
    required this.id,
    required this.word,
    required this.wordKey,
    required this.phonetic,
    required this.meaning,
    required this.sourceImagePath,
    required this.createdAt,
    required this.studyDate,
    required this.mastered,
    required this.reviewCount,
    required this.lastReviewAt,
    required this.updatedAt,
  });

  final int id;

  /// 展示用的原始拼写，例如 `give up`
  final String word;

  /// 归一化后的去重键：小写 + 折叠多余空格
  final String wordKey;

  /// 音标，形如 `/ˈæpl/`，可能为空字符串
  final String phonetic;

  /// 中文释义
  final String meaning;

  /// 来源图片路径（用户开启“保存原图”时才写入）
  final String? sourceImagePath;

  /// 上传时间（毫秒时间戳）
  final int createdAt;

  /// 学习日期 `yyyy-MM-dd`，默认取上传当天
  final String studyDate;

  /// 是否已掌握
  final bool mastered;

  /// 复习次数
  final int reviewCount;

  /// 最近复习时间（毫秒时间戳），从未复习为 null
  final int? lastReviewAt;

  /// 最近一次修改时间
  final int updatedAt;

  factory Word.fromMap(Map<String, Object?> map) {
    return Word(
      id: (map['id'] as num?)?.toInt() ?? 0,
      word: (map['word'] as String?) ?? '',
      wordKey: (map['word_key'] as String?) ?? '',
      phonetic: (map['phonetic'] as String?) ?? '',
      meaning: (map['meaning'] as String?) ?? '',
      sourceImagePath: map['source_image_path'] as String?,
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
      studyDate: (map['study_date'] as String?) ?? '',
      mastered: ((map['mastered'] as num?)?.toInt() ?? 0) == 1,
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
      lastReviewAt: (map['last_review_at'] as num?)?.toInt(),
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'word': word,
      'word_key': wordKey,
      'phonetic': phonetic,
      'meaning': meaning,
      'source_image_path': sourceImagePath,
      'created_at': createdAt,
      'study_date': studyDate,
      'mastered': mastered ? 1 : 0,
      'review_count': reviewCount,
      'last_review_at': lastReviewAt,
      'updated_at': updatedAt,
    };
  }

  Word copyWith({
    int? id,
    String? word,
    String? wordKey,
    String? phonetic,
    String? meaning,
    String? sourceImagePath,
    int? createdAt,
    String? studyDate,
    bool? mastered,
    int? reviewCount,
    int? lastReviewAt,
    int? updatedAt,
  }) {
    return Word(
      id: id ?? this.id,
      word: word ?? this.word,
      wordKey: wordKey ?? this.wordKey,
      phonetic: phonetic ?? this.phonetic,
      meaning: meaning ?? this.meaning,
      sourceImagePath: sourceImagePath ?? this.sourceImagePath,
      createdAt: createdAt ?? this.createdAt,
      studyDate: studyDate ?? this.studyDate,
      mastered: mastered ?? this.mastered,
      reviewCount: reviewCount ?? this.reviewCount,
      lastReviewAt: lastReviewAt ?? this.lastReviewAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 回顾模式：英→中 / 中→英
enum ReviewMode {
  enToCn('英 → 中'),
  cnToEn('中 → 英');

  const ReviewMode(this.label);

  final String label;

  String get storageValue => name;

  static ReviewMode fromStorage(String? value) {
    for (final ReviewMode mode in ReviewMode.values) {
      if (mode.name == value) return mode;
    }
    return ReviewMode.enToCn;
  }
}

/// 列表排序方式
enum WordSortMode {
  newest('最新上传'),
  oldest('最早上传'),
  alphabetical('字母 A→Z');

  const WordSortMode(this.label);

  final String label;

  String get storageValue => name;

  static WordSortMode fromStorage(String? value) {
    for (final WordSortMode mode in WordSortMode.values) {
      if (mode.name == value) return mode;
    }
    return WordSortMode.newest;
  }

  /// 拼进 SQL 的 ORDER BY（全部为白名单常量，不存在注入风险）
  String get orderBy {
    switch (this) {
      case WordSortMode.newest:
        return 'created_at DESC, id DESC';
      case WordSortMode.oldest:
        return 'created_at ASC, id ASC';
      case WordSortMode.alphabetical:
        return 'word_key COLLATE NOCASE ASC, id ASC';
    }
  }
}
