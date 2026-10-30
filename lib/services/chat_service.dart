import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/word_draft.dart';
import 'agent_service.dart';
import 'recognition_failure.dart';

/// 一条对话消息（只发文字，图片单独用 image_base64 传，避免历史越滚越大）。
class ChatTurn {
  const ChatTurn({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, Object?> toJson() => <String, Object?>{
        'role': role,
        'content': content,
      };
}

/// 智能体的一轮回复：说的话 + 要写入单词本的单词 + 最新候选词（供下一轮继续筛）。
class ChatReply {
  const ChatReply({
    required this.reply,
    required this.imports,
    required this.candidates,
    required this.notes,
  });

  final String reply;
  final List<List<WordDraft>> imports;
  final List<WordDraft> candidates;
  final List<String> notes;

  int get importCount =>
      imports.fold(0, (int sum, List<WordDraft> w) => sum + w.length);
}

/// 调用对话式智能体 `POST /chat`。
///
/// 服务端不存会话：上下文由这里每轮带上（messages + 上一轮 candidates），
/// 所以"单次会话记忆"就是本页面的聊天记录，关掉页面即清空。
class ChatService {
  ChatService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<ChatReply> send({
    required AgentConfig config,
    required List<ChatTurn> history,
    String? imagePath,
    String? ocrText,
    List<WordDraft> candidates = const <WordDraft>[],
    List<String> knownWords = const <String>[],
    int maxWords = 80,
  }) async {
    if (!config.isReady) {
      throw const RecognitionFailure(FailureKind.noKey, '智能体地址为空');
    }
    final Uri? uri = config.endpoint('/chat');
    if (uri == null) {
      throw const RecognitionFailure(FailureKind.badResponse, '智能体地址格式不正确');
    }

    String? imageBase64;
    if (imagePath != null && imagePath.isNotEmpty) {
      try {
        final File file = File(imagePath);
        if (await file.exists()) {
          imageBase64 = base64Encode(await file.readAsBytes());
        }
      } catch (_) {
        imageBase64 = null;
      }
    }

    final Map<String, Object?> payload = <String, Object?>{
      'messages': history.map((ChatTurn t) => t.toJson()).toList(),
      'max_words': maxWords,
      if (imageBase64 != null) 'image_base64': imageBase64,
      if (ocrText != null && ocrText.trim().isNotEmpty) 'ocr_text': ocrText,
      if (candidates.isNotEmpty)
        'candidates': candidates
            .map((WordDraft d) => <String, Object?>{
                  'word': d.word,
                  'phonetic': d.phonetic,
                  'meaning': d.meaning,
                })
            .toList(),
      if (knownWords.isNotEmpty) 'known_words': knownWords,
    };

    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: config.timeoutSeconds));
    } on TimeoutException {
      throw RecognitionFailure(
        FailureKind.timeout,
        '智能体响应超时（${config.timeoutSeconds} 秒）',
      );
    } on SocketException catch (e) {
      throw RecognitionFailure(FailureKind.network, '连不上智能体服务', detail: e.message);
    } on http.ClientException catch (e) {
      throw RecognitionFailure(FailureKind.network, '智能体请求失败', detail: e.message);
    }

    if (response.statusCode != 200) {
      throw RecognitionFailure(
        FailureKind.badResponse,
        '智能体返回 HTTP ${response.statusCode}',
        detail: _snippet(response.body),
      );
    }

    final dynamic decoded = _decode(response.body);
    if (decoded is! Map) {
      throw RecognitionFailure(
        FailureKind.badResponse,
        '智能体返回格式不是 JSON 对象',
        detail: _snippet(response.body),
      );
    }

    return ChatReply(
      reply: '${decoded['reply'] ?? ''}'.trim(),
      imports: _parseActions(decoded['actions']),
      candidates: _parseWords(decoded['candidates']),
      notes: (decoded['notes'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => '$e'.trim())
          .where((String e) => e.isNotEmpty)
          .toList(growable: false),
    );
  }

  List<List<WordDraft>> _parseActions(dynamic raw) {
    final List<List<WordDraft>> out = <List<WordDraft>>[];
    if (raw is! List) return out;
    for (final dynamic item in raw) {
      if (item is! Map) continue;
      if ('${item['type']}' != 'import_words') continue;
      final List<WordDraft> words = _parseWords(item['words']);
      if (words.isNotEmpty) out.add(words);
    }
    return out;
  }

  List<WordDraft> _parseWords(dynamic raw) {
    final List<WordDraft> out = <WordDraft>[];
    final Set<String> seen = <String>{};
    if (raw is! List) return out;
    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final WordDraft? draft = WordDraft.fromRaw(
        word: '${item['word'] ?? ''}',
        phonetic: '${item['phonetic'] ?? ''}',
        meaning: '${item['meaning'] ?? ''}',
      );
      if (draft == null || !seen.add(draft.key)) continue;
      out.add(draft);
    }
    return out;
  }

  dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String _snippet(String body) =>
      body.length > 200 ? '${body.substring(0, 200)}…' : body;
}
