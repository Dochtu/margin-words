import 'dart:convert';

import '../core/word_text.dart';
import '../data/word_draft.dart';
import 'recognition_failure.dart';

/// 大模型返回内容的 JSON 容错解析。
///
/// 真实环境里模型经常：包一层 ```json、前后带解释、单引号、尾逗号、
/// 返回 `{"words": [...]}` 而不是纯数组、phonetic 混进 meaning……
/// 这里逐层兜底，保证「只要内容里有一个像样的数组，就能救回来」。
class LlmJsonParser {
  const LlmJsonParser._();

  static const int maxItems = 40;

  static List<WordDraft> parse(String raw) {
    final String cleaned = _stripFence(raw);
    if (cleaned.isEmpty) {
      throw const RecognitionFailure(
        FailureKind.badResponse,
        '模型返回了空内容',
      );
    }

    dynamic decoded;
    final String? arrayText = _extractBalanced(cleaned, '[', ']');
    if (arrayText != null) {
      decoded = _tryDecode(arrayText) ?? _tryDecode(_relax(arrayText));
    }

    if (decoded == null) {
      final String? objectText = _extractBalanced(cleaned, '{', '}');
      if (objectText != null) {
        final Object? object =
            _tryDecode(objectText) ?? _tryDecode(_relax(objectText));
        decoded = _unwrap(object);
      }
    }

    if (decoded is! List) {
      throw RecognitionFailure(
        FailureKind.badResponse,
        '模型输出不是可解析的 JSON 数组',
        detail: cleaned.length > 300 ? cleaned.substring(0, 300) : cleaned,
      );
    }

    final List<WordDraft> drafts = <WordDraft>[];
    final Set<String> seen = <String>{};

    for (final dynamic item in decoded) {
      if (drafts.length >= maxItems) break;
      final WordDraft? draft = _draftFromItem(item);
      if (draft == null) continue;
      if (!seen.add(draft.key)) continue;
      drafts.add(draft);
    }

    if (drafts.isEmpty) {
      throw const RecognitionFailure(
        FailureKind.noWords,
        '模型没有返回可用的英文单词',
      );
    }
    return drafts;
  }

  // ------------------------------------------------------------ 内部实现

  static String _stripFence(String raw) {
    String text = raw.trim();
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    // ```json ... ```
    final RegExp fence = RegExp(r'^```[a-zA-Z]*\s*|```\s*$');
    if (text.contains('```')) {
      text = text.replaceAll(RegExp(r'```[a-zA-Z]*'), '');
      text = text.replaceAll('```', '');
    }
    text = text.replaceAll(fence, '');
    return text.trim();
  }

  /// 从任意文本中截取第一个配对的 [open]…[close] 片段（正确处理字符串内的括号）。
  static String? _extractBalanced(String text, String open, String close) {
    final int start = text.indexOf(open);
    if (start < 0) return null;
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    String quote = '"';
    for (int i = start; i < text.length; i++) {
      final String ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == quote) {
          inString = false;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        inString = true;
        quote = ch;
      } else if (ch == open) {
        depth++;
      } else if (ch == close) {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// 修复常见非法 JSON：尾逗号、中文引号、BOM。
  static String _relax(String text) {
    String fixed = text;
    fixed = fixed.replaceAll('\uFEFF', '');
    fixed = fixed.replaceAll('“', '"').replaceAll('”', '"');
    fixed = fixed.replaceAll('，', ',').replaceAll('：', ':');
    // 去掉 ] } 前的多余逗号（Dart 的 replaceAll 不支持 $1，必须用 replaceAllMapped）
    fixed = fixed.replaceAllMapped(
      RegExp(r',(\s*[\]}])'),
      (Match m) => m.group(1) ?? '',
    );
    return fixed;
  }

  static Object? _unwrap(Object? object) {
    if (object is List) return object;
    if (object is Map) {
      const List<String> keys = <String>[
        'words',
        'items',
        'data',
        'list',
        'result',
        'results',
        'vocabulary',
        '单词',
      ];
      for (final String key in keys) {
        final Object? value = object[key];
        if (value is List) return value;
      }
      // 兜底：取第一个 List 值
      for (final Object? value in object.values) {
        if (value is List) return value;
      }
    }
    return null;
  }

  static WordDraft? _draftFromItem(dynamic item) {
    if (item is String) {
      return WordDraft.fromRaw(word: item);
    }
    if (item is! Map) return null;

    final Map<String, dynamic> lower = <String, dynamic>{};
    item.forEach((dynamic key, dynamic value) {
      lower[key.toString().toLowerCase().trim()] = value;
    });

    String pick(List<String> keys) {
      for (final String key in keys) {
        final dynamic value = lower[key];
        if (value is String && value.trim().isNotEmpty) return value;
        if (value is num) return value.toString();
      }
      return '';
    }

    final String word = pick(<String>[
      'word',
      'english',
      'term',
      'vocab',
      'en',
      'text',
      '单词',
      '英文',
    ]);
    String phonetic = pick(<String>[
      'phonetic',
      'phonetics',
      'ipa',
      'pronunciation',
      'pron',
      '音标',
    ]);
    String meaning = pick(<String>[
      'meaning',
      'translation',
      'chinese',
      'cn',
      'zh',
      'definition',
      'desc',
      '释义',
      '中文',
      '意思',
    ]);

    // 模型有时把音标塞进释义里："放弃 /əˈbændən/"
    if (WordText.cleanPhonetic(phonetic).isEmpty) {
      final RegExpMatch? inside =
          RegExp(r'(\[[^\[\]]{1,44}\]|/[^/]{1,44}/)').firstMatch(meaning);
      if (inside != null) {
        phonetic = inside.group(0) ?? '';
        meaning = meaning.replaceRange(inside.start, inside.end, ' ').trim();
      }
    }

    return WordDraft.fromRaw(
      word: word,
      phonetic: phonetic,
      meaning: meaning,
    );
  }
}
