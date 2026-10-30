/// 单词文本清洗与校验。
///
/// 大模型/本地 OCR 的输出经常带题号、引号、全角符号、换行等噪声，
/// 统一在这里做一次“入库前清洗”，保证 `word` 列干净、去重键稳定。
class WordText {
  const WordText._();

  static final RegExp _leadingIndex =
      RegExp(r'^[\s\(（]*\d{1,3}\s*[\.、\)）:：]\s*');
  static final RegExp _edgePunctuation =
      RegExp(r'''^[\s"'“”‘’\-–—·•\*\[\]【】<>《》\(\（]+|[\s"'“”‘’\.,;:!。，、；：！？\-–—\*\[\]【】<>》\)\）]+$''');
  static final RegExp _cjk = RegExp(r'[\u4e00-\u9fa5\u3000-\u303f\uff00-\uffef]');
  static final RegExp _validWordChars = RegExp(r"^[A-Za-z][A-Za-z'’\-\. ]{0,48}$");
  static final RegExp _ipaChars = RegExp(
    r"^[A-Za-zæɑɒɔəɜɛɪʊʌθðʃʒŋɡɹɾʔˈˌːˑ\u0250-\u02FF'\-\. ]+$",
  );

  /// 折叠多余空白（含全角空格），首尾去空格。
  static String squeeze(String raw) {
    return raw
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[\t\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// 去重键：小写 + 折叠空白。数据库中唯一语义靠它判断。
  static String keyOf(String raw) => squeeze(raw).toLowerCase();

  /// 清洗成可入库的英文单词/短语；不合法返回空字符串。
  static String cleanWord(String raw) {
    String text = squeeze(raw);
    if (text.isEmpty) return '';

    // 去掉 “1.” “(2)” 这类题号
    for (int i = 0; i < 3; i++) {
      final String next = text.replaceFirst(_leadingIndex, '');
      if (next == text) break;
      text = next;
    }

    // 去掉音标残留，例如 "apple /ˈæpl/"
    text = text.replaceAll(RegExp(r'[\[/][^\]/]{1,44}[\]/]'), ' ');
    text = squeeze(text);

    // 去掉首尾标点
    text = text.replaceAll(_edgePunctuation, '');
    text = squeeze(text);

    // 去掉词性前缀，例如 "n. apple"
    text = text.replaceFirst(
      RegExp(r'^(n|v|vt|vi|adj|adv|prep|pron|conj|num|art|int|aux|abbr)\.\s*',
          caseSensitive: false),
      '',
    );

    text = squeeze(text);
    if (!isValidWord(text)) return '';
    return text;
  }

  static bool isValidWord(String raw) {
    if (raw.isEmpty || raw.length > 48) return false;
    if (_cjk.hasMatch(raw)) return false;
    if (RegExp(r'\d').hasMatch(raw)) return false;
    if (!_validWordChars.hasMatch(raw)) return false;
    final List<String> tokens = raw.split(' ');
    if (tokens.length > 4) return false;
    // 至少要有一个 2 个字母以上的英文词，过滤 "a" "I" 之类虚词
    return tokens.any((String t) => t.replaceAll(RegExp(r"[^A-Za-z]"), '').length >= 2);
  }

  /// 音标规范化：合法则返回 `/.../`，否则返回空字符串（宁可留空也不填错）。
  static String cleanPhonetic(String raw) {
    String text = squeeze(raw);
    if (text.isEmpty) return '';
    text = text.replaceFirst(RegExp(r'^(音标|发音|phonetic)\s*[:：]\s*', caseSensitive: false), '');
    text = text.trim();

    if (_cjk.hasMatch(text)) return '';

    // 统一成 /xxx/
    String inner = text;
    if (inner.startsWith('/') && inner.endsWith('/') && inner.length > 2) {
      inner = inner.substring(1, inner.length - 1);
    } else if (inner.startsWith('[') && inner.endsWith(']') && inner.length > 2) {
      inner = inner.substring(1, inner.length - 1);
    }
    inner = inner.trim();
    if (inner.isEmpty || inner.length > 44) return '';
    if (!_ipaChars.hasMatch(inner)) return '';
    if (!RegExp('[A-Za-zæɑɒɔəɜɛɪʊʌθðʃʒŋɡ]').hasMatch(inner)) return '';
    return '/$inner/';
  }

  /// 释义清洗：折叠空白、去掉首尾多余标点、限制长度。
  static String cleanMeaning(String raw, {int maxLength = 200}) {
    String text = squeeze(raw);
    text = text.replaceAll(RegExp(r'^[\-–—:：,，、;；\s]+'), '');
    text = text.replaceAll(RegExp(r'[\s,，、;；]+$'), '');
    if (text.length > maxLength) {
      text = '${text.substring(0, maxLength)}…';
    }
    return text;
  }
}
