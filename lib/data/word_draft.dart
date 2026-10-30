import '../core/word_text.dart';

/// 识别结果的可编辑草稿。确认页直接改这里，保存时一次性写库。
class WordDraft {
  WordDraft({
    required this.word,
    this.phonetic = '',
    this.meaning = '',
    this.imagePath,
  });

  String word;
  String phonetic;
  String meaning;
  String? imagePath;

  /// 是否勾选保存（确认页可以取消勾选）
  bool selected = true;

  /// 数据库中是否已存在同名单词（仅用于提示“将合并”）
  bool existsInDb = false;

  /// 智能体给出的保留理由（可为空，仅用于展示）
  String? reason;

  String get key => WordText.keyOf(word);

  bool get isValid => WordText.isValidWord(WordText.cleanWord(word));

  /// 三个字段全空的行直接忽略
  bool get isEmpty =>
      word.trim().isEmpty && phonetic.trim().isEmpty && meaning.trim().isEmpty;

  WordDraft copy() {
    return WordDraft(
      word: word,
      phonetic: phonetic,
      meaning: meaning,
      imagePath: imagePath,
    )
      ..selected = selected
      ..existsInDb = existsInDb
      ..reason = reason;
  }

  /// 从任意来源构造：会做一次清洗，非法单词返回 null。
  static WordDraft? fromRaw({
    required String word,
    String phonetic = '',
    String meaning = '',
    String? imagePath,
  }) {
    final String cleanWord = WordText.cleanWord(word);
    if (cleanWord.isEmpty) return null;
    return WordDraft(
      word: cleanWord,
      phonetic: WordText.cleanPhonetic(phonetic),
      meaning: WordText.cleanMeaning(meaning),
      imagePath: imagePath,
    );
  }
}

/// 保存结果统计，用于保存后提示。
class SaveReport {
  const SaveReport({
    required this.inserted,
    required this.merged,
    required this.skipped,
  });

  final int inserted;
  final int merged;
  final int skipped;

  int get total => inserted + merged;

  String get summary {
    final List<String> parts = <String>[];
    if (inserted > 0) parts.add('新增 $inserted');
    if (merged > 0) parts.add('合并更新 $merged');
    if (skipped > 0) parts.add('跳过 $skipped');
    if (parts.isEmpty) return '没有可保存的单词';
    return parts.join('，');
  }
}
