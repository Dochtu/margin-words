import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/word_draft.dart';
import 'llm_json.dart';
import 'llm_prompt.dart';
import 'recognition_failure.dart';

/// 大模型调用配置（OpenAI 兼容的 /chat/completions 接口）。
class LlmConfig {
  const LlmConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.timeoutSeconds = 25,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final int timeoutSeconds;

  bool get isReady =>
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  Uri? get endpoint {
    String url = baseUrl.trim();
    if (url.isEmpty) return null;
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/chat/completions')) {
      url = '$url/chat/completions';
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }
}

/// 调用大模型把 OCR 文本结构化成单词数组。
///
/// 注意：只发送 OCR 出来的文字，不发送图片。
class LlmService {
  LlmService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<WordDraft>> extract({
    required String ocrText,
    required LlmConfig config,
  }) async {
    if (!config.isReady) {
      throw const RecognitionFailure(FailureKind.noKey, '尚未配置大模型 API Key');
    }
    final Uri? uri = config.endpoint;
    if (uri == null) {
      throw const RecognitionFailure(FailureKind.badResponse, 'Base URL 格式不正确');
    }

    final String payload = jsonEncode(<String, Object?>{
      'model': config.model,
      'temperature': 0,
      'stream': false,
      ..._thinkingOff(uri),
      'messages': <Map<String, String>>[
        <String, String>{'role': 'system', 'content': LlmPrompt.system},
        <String, String>{'role': 'user', 'content': LlmPrompt.user(ocrText)},
      ],
    });

    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: payload,
          )
          .timeout(Duration(seconds: config.timeoutSeconds));
    } on TimeoutException {
      throw RecognitionFailure(
        FailureKind.timeout,
        '请求超时（${config.timeoutSeconds} 秒）',
      );
    } on SocketException catch (e) {
      throw RecognitionFailure(FailureKind.network, '无法连接网络', detail: e.message);
    } on http.ClientException catch (e) {
      throw RecognitionFailure(FailureKind.network, '网络请求失败', detail: e.message);
    } on HandshakeException catch (e) {
      throw RecognitionFailure(FailureKind.network, 'TLS 握手失败', detail: e.message);
    } catch (e) {
      throw RecognitionFailure(FailureKind.unknown, '调用大模型失败', detail: e.toString());
    }

    if (response.statusCode != 200) {
      throw _mapHttpError(response);
    }

    return LlmJsonParser.parse(_contentOf(response.body));
  }

  /// 设置页「测试连接」：发一条极短的请求，确认 Key / Base URL / 模型是否可用。
  Future<String> testConnection(LlmConfig config) async {
    if (!config.isReady) {
      throw const RecognitionFailure(FailureKind.noKey, '请先填写 Base URL、API Key 和模型名');
    }
    final Uri? uri = config.endpoint;
    if (uri == null) {
      throw const RecognitionFailure(FailureKind.badResponse, 'Base URL 格式不正确');
    }
    late http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer ${config.apiKey}',
        },
        body: jsonEncode(<String, Object?>{
          'model': config.model,
          'temperature': 0,
          'max_tokens': 16,
          ..._thinkingOff(uri),
          'messages': <Map<String, String>>[
            <String, String>{'role': 'user', 'content': '只回复两个字：正常'},
          ],
        }),
      ).timeout(Duration(seconds: config.timeoutSeconds));
    } on TimeoutException {
      throw const RecognitionFailure(FailureKind.timeout, '连接超时，请检查网络或代理');
    } on SocketException catch (e) {
      throw RecognitionFailure(FailureKind.network, '无法连接网络', detail: e.message);
    } catch (e) {
      throw RecognitionFailure(FailureKind.unknown, '连接失败', detail: e.toString());
    }

    if (response.statusCode != 200) throw _mapHttpError(response);
    final String content = _contentOf(response.body);
    return content.trim().isEmpty ? '连接成功' : '连接成功：${content.trim()}';
  }

  // ------------------------------------------------------------ 内部实现

  /// DeepSeek V4.1-Flash 默认开启 thinking：这套流程只要结构化 JSON，
  /// 必须显式关闭，否则推理过程会吃掉 token 预算，甚至让 content 为空。
  Map<String, Object?> _thinkingOff(Uri uri) {
    if (!uri.host.contains('deepseek')) return const <String, Object?>{};
    return <String, Object?>{
      'thinking': <String, String>{'type': 'disabled'},
    };
  }

  String _contentOf(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is List) return body;
      if (decoded is Map) {
        final dynamic choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final dynamic first = choices.first;
          if (first is Map) {
            final dynamic message = first['message'];
            if (message is Map) {
              final dynamic content = message['content'];
              if (content is String && content.trim().isNotEmpty) return content;
              if (content is List) {
                final StringBuffer buffer = StringBuffer();
                for (final dynamic part in content) {
                  if (part is Map && part['text'] is String) {
                    buffer.write(part['text']);
                  }
                }
                if (buffer.isNotEmpty) return buffer.toString();
              }
            }
            final dynamic text = first['text'];
            if (text is String && text.trim().isNotEmpty) return text;
          }
        }
      }
    } catch (_) {
      // 落到下面的统一报错
    }
    final String snippet = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    throw RecognitionFailure(
      FailureKind.badResponse,
      '服务返回内容无法解析',
      detail: snippet,
    );
  }

  RecognitionFailure _mapHttpError(http.Response response) {
    final int code = response.statusCode;
    final String body = response.body;
    final String lower = body.toLowerCase();
    final String snippet = body.length > 200 ? '${body.substring(0, 200)}…' : body;

    if (code == 401 || code == 403) {
      return RecognitionFailure(
        FailureKind.unauthorized,
        'API Key 无效或无权限（HTTP $code）',
        detail: snippet,
      );
    }
    if (code == 402 ||
        lower.contains('insufficient') ||
        lower.contains('quota') ||
        lower.contains('balance')) {
      return RecognitionFailure(
        FailureKind.quota,
        '账户额度不足（HTTP $code）',
        detail: snippet,
      );
    }
    if (code == 429) {
      return RecognitionFailure(
        FailureKind.rateLimit,
        '请求过于频繁（HTTP 429）',
        detail: snippet,
      );
    }
    if (code >= 500) {
      return RecognitionFailure(
        FailureKind.server,
        '服务端错误（HTTP $code）',
        detail: snippet,
      );
    }
    return RecognitionFailure(
      FailureKind.badResponse,
      '请求被拒绝（HTTP $code）',
      detail: snippet,
    );
  }
}
