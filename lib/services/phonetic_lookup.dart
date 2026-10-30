import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/word_text.dart';
import '../data/word_dao.dart';
import '../data/word_draft.dart';

/// 音标校验 / 补全。
///
/// 顺序：
///   1. 本地格式校验（不合法直接清空，绝不留下大模型编的音标）
///   2. 本地缓存表 phonetic_cache 命中
///   3. 免费词典 API（dictionaryapi.dev）兜底，仅联网、仅单词、最多 12 个/次
///
/// 任何一步失败都静默跳过，不影响主流程。
class PhoneticLookup {
  PhoneticLookup(this._dao, {http.Client? client})
      : _client = client ?? http.Client();

  final WordDao _dao;
  final http.Client _client;

  static const int _maxNetworkLookups = 12;
  static const Duration _timeout = Duration(seconds: 4);

  /// 返回补全成功的数量。
  Future<int> fillMissing(
    List<WordDraft> drafts, {
    required bool allowNetwork,
    void Function(int done, int total)? onProgress,
  }) async {
    int filled = 0;

    // 1. 先做本地格式校验 + 缓存命中
    final List<WordDraft> needNetwork = <WordDraft>[];
    for (final WordDraft draft in drafts) {
      final String sanitized = WordText.cleanPhonetic(draft.phonetic);
      draft.phonetic = sanitized;
      if (sanitized.isNotEmpty) continue;

      final String key = draft.key;
      if (key.isEmpty) continue;
      final String? cached = await _dao.cachedPhonetic(key);
      if (cached != null && cached.isNotEmpty) {
        draft.phonetic = cached;
        filled++;
        continue;
      }
      // 只有单个英文单词才去查词典（短语命中率极低）
      if (RegExp(r"^[A-Za-z][A-Za-z\-'’]*$").hasMatch(draft.word)) {
        needNetwork.add(draft);
      }
    }

    if (!allowNetwork || needNetwork.isEmpty) {
      onProgress?.call(filled, filled);
      return filled;
    }

    // 2. 词典 API 并发查询（最多 12 个）
    final List<WordDraft> batch =
        needNetwork.take(_maxNetworkLookups).toList(growable: false);
    int done = 0;
    await Future.wait(batch.map((WordDraft draft) async {
      final String? phonetic = await _lookupOnline(draft.word);
      if (phonetic != null && phonetic.isNotEmpty) {
        draft.phonetic = phonetic;
        filled++;
        await _dao.cachePhonetic(draft.key, phonetic);
      }
      done++;
      onProgress?.call(done, batch.length);
    }));

    return filled;
  }

  Future<String?> _lookupOnline(String word) async {
    final Uri uri = Uri.parse(
      'https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(word.toLowerCase())}',
    );
    try {
      final http.Response response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) return null;
      for (final dynamic entry in decoded) {
        if (entry is! Map) continue;
        final dynamic phonetic = entry['phonetic'];
        if (phonetic is String) {
          final String cleaned = WordText.cleanPhonetic(phonetic);
          if (cleaned.isNotEmpty) return cleaned;
        }
        final dynamic phonetics = entry['phonetics'];
        if (phonetics is List) {
          for (final dynamic item in phonetics) {
            if (item is Map && item['text'] is String) {
              final String cleaned =
                  WordText.cleanPhonetic(item['text'] as String);
              if (cleaned.isNotEmpty) return cleaned;
            }
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
