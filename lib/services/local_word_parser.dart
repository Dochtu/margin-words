import '../core/word_text.dart';
import '../data/word_draft.dart';
import 'recognition_failure.dart';

/// 本地规则解析：在「没有配置大模型」或「大模型不可用」时兜底。
///
/// 针对常见词表排版做启发式匹配：
///   abandon /əˈbændən/ v. 放弃
///   1. abandon  [əˈbændən]  放弃；抛弃
///   abandon 放弃
///   abandon
///   /əˈbændən/ 放弃
/// 它不追求 100% 准确，重点是「不联网也能先把单词存进来」，
/// 存进去之后用户可以在确认页手改。
class LocalWordParser {
  const LocalWordParser._();

  static final RegExp _phoneticPattern =
      RegExp(r'(\[[^\[\]]{1,40}\]|/[^/]{1,44}/)');
  static final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fa5]');
  static final RegExp _indexPrefix =
      RegExp(r'^[\s\(（]*\d{1,3}\s*[\.、\)）]\s*');
  static final RegExp _posSuffix = RegExp(
    r'\s+(n|v|vt|vi|adj|adv|prep|pron|conj|num|art|int|aux|abbr)\.?\s*$',
    caseSensitive: false,
  );
  static final RegExp _splitWords = RegExp(r'\s*[,，/、;；]\s*');

  static const int _maxItems = 60;

  /// 解析一大段 OCR 文字，返回可编辑草稿。
  /// 解析不到任何单词时抛出 [RecognitionFailure]。
  static List<WordDraft> parse(String text) {
    final List<String> lines = text
        .split(RegExp(r'\r?\n'))
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList(growable: false);

    final List<WordDraft> result = <WordDraft>[];
    final Set<String> seen = <String>{};

    void addDraft(String rawWord, String phonetic, String meaning) {
      final String trimmedWord = rawWord.trim();
      if (trimmedWord.isEmpty) return;

      // 一行里出现 "abandon, desert" 这类并列词，拆成多条但共用释义
      final List<String> candidates = trimmedWord.contains(',') ||
              trimmedWord.contains('，') ||
              trimmedWord.contains('、')
          ? trimmedWord.split(_splitWords)
          : <String>[trimmedWord];

      for (final String candidate in candidates) {
        if (result.length >= _maxItems) return;
        final WordDraft? draft = WordDraft.fromRaw(
          word: candidate,
          phonetic: phonetic,
          meaning: meaning,
        );
        if (draft == null) continue;
        if (!seen.add(draft.key)) continue;
        result.add(draft);
      }
    }

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].replaceFirst(_indexPrefix, '').trim();
      if (line.isEmpty) continue;
      if (!RegExp('[A-Za-z]').hasMatch(line)) continue;

      String wordPart = '';
      String phonetic = '';
      String meaning = '';

      final RegExpMatch? phoneticMatch = _phoneticPattern.firstMatch(line);
      if (phoneticMatch != null) {
        phonetic = phoneticMatch.group(0) ?? '';
        wordPart = line.substring(0, phoneticMatch.start).trim();
        meaning = line.substring(phoneticMatch.end).trim();
      } else {
        final RegExpMatch? cjk = _cjkPattern.firstMatch(line);
        if (cjk != null) {
          wordPart = line.substring(0, cjk.start).trim();
          meaning = line.substring(cjk.start).trim();
        } else {
          wordPart = line;
        }
      }

      wordPart = wordPart.replaceAll(':', '').replaceAll('|', ' ').trim();

      // 把词性从「单词部分」挪到释义开头，例如 "abandon v." → "v. 放弃"
      final RegExpMatch? pos = _posSuffix.firstMatch(wordPart);
      if (pos != null) {
        final String posText = pos.group(0)!.trim();
        wordPart = wordPart.substring(0, pos.start).trim();
        if (meaning.isNotEmpty && !meaning.toLowerCase().startsWith('n.')) {
          meaning = '$posText $meaning';
        }
      }

      // 释义为空：尝试借用下一行（竖排词表）
      if (meaning.isEmpty || !_cjkPattern.hasMatch(meaning)) {
        final String? next = i + 1 < lines.length ? lines[i + 1].trim() : null;
        if (next != null && next.isNotEmpty) {
          final RegExpMatch? nextPhonetic = _phoneticPattern.firstMatch(next);
          if (meaning.isEmpty && nextPhonetic != null && nextPhonetic.start == 0) {
            phonetic = nextPhonetic.group(0) ?? phonetic;
            final String rest = next.substring(nextPhonetic.end).trim();
            if (rest.isNotEmpty) meaning = rest;
          } else if (meaning.isEmpty && _cjkPattern.hasMatch(next)) {
            meaning = next;
            i++;
          }
        }
      }

      if (wordPart.isEmpty) continue;
      addDraft(wordPart, phonetic, WordText.cleanMeaning(meaning));
    }

    if (result.isEmpty) {
      throw const RecognitionFailure(
        FailureKind.noWords,
        '这段文字里没有解析出英文单词',
      );
    }
    return result;
  }
}
