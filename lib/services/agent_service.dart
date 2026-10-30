import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/word_text.dart';
import '../data/word_draft.dart';
import 'recognition_failure.dart';

/// 智能体服务配置（自建的 LangGraph 服务地址）。
class AgentConfig {
  const AgentConfig({
    required this.baseUrl,
    this.timeoutSeconds = 45,
  });

  final String baseUrl;
  final int timeoutSeconds;

  bool get isReady => baseUrl.trim().isNotEmpty;

  Uri? endpoint(String path) {
    String base = baseUrl.trim();
    if (base.isEmpty) return null;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    // 允许用户直接填 .../extract
    if (base.endsWith(path)) base = base.substring(0, base.length - path.length);
    final Uri? uri = Uri.tryParse('$base$path');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }
}

/// 智能体返回结果。
class AgentResult {
  const AgentResult({
    required this.words,
    required this.notes,
    required this.rawCount,
    required this.needsImage,
  });

  final List<WordDraft> words;
  final List<String> notes;
  final int rawCount;
  final bool needsImage;

  bool get isEmpty => words.isEmpty;
}

/// 调用后端的 LangGraph 智能体：把 OCR 文本 + 一句筛选要求，变成单词列表。
///
/// 请求体：`{ocr_text, instruction, image_base64?, allow_vision, max_words}`
/// 响应体：`{words:[{word,phonetic,meaning,reason}], notes:[], needs_image, raw_count}`
class AgentService {
  AgentService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AgentResult> extract({
    required String ocrText,
    required String instruction,
    required AgentConfig config,
    bool allowVision = false,
    String? imagePath,
    int maxWords = 80,
    List<String> knownWords = const <String>[],
  }) async {
    if (!config.isReady) {
      throw const RecognitionFailure(FailureKind.noKey, '尚未配置智能体服务地址');
    }
    final Uri? uri = config.endpoint('/extract');
    if (uri == null) {
      throw const RecognitionFailure(FailureKind.badResponse, '智能体地址格式不正确');
    }

    // 只有用户显式允许时才读取并上传图片（用于识别圈选/划线）
    String? imageBase64;
    if (allowVision && imagePath != null && imagePath.isNotEmpty) {
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
      'ocr_text': ocrText,
      'instruction': instruction,
      'allow_vision': allowVision && imageBase64 != null,
      'max_words': maxWords,
      // 已掌握单词：智能体据此理解「只保留我不认识的」，而不是自己猜难度
      if (knownWords.isNotEmpty) 'known_words': knownWords,
      if (imageBase64 != null) 'image_base64': imageBase64,
    };

    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: config.timeoutSeconds));
    } on TimeoutException {
      throw RecognitionFailure(
        FailureKind.timeout,
        '智能体响应超时（${config.timeoutSeconds} 秒）',
      );
    } on SocketException catch (e) {
      throw RecognitionFailure(
        FailureKind.network,
        '连不上智能体服务',
        detail: e.message,
      );
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

    final List<WordDraft> words = <WordDraft>[];
    final Set<String> seen = <String>{};
    for (final dynamic item in (decoded['words'] as List<dynamic>? ?? <dynamic>[])) {
      if (item is! Map) continue;
      final WordDraft? draft = WordDraft.fromRaw(
        word: '${item['word'] ?? ''}',
        phonetic: '${item['phonetic'] ?? ''}',
        meaning: '${item['meaning'] ?? ''}',
      );
      if (draft == null) continue;
      if (!seen.add(draft.key)) continue;
      draft.reason = (item['reason'] as String?)?.trim();
      words.add(draft);
    }

    if (words.isEmpty) {
      throw const RecognitionFailure(
        FailureKind.noWords,
        '智能体没有返回可用的单词',
      );
    }

    return AgentResult(
      words: words,
      notes: (decoded['notes'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => '$e')
          .where((String e) => e.trim().isNotEmpty)
          .toList(growable: false),
      rawCount: (decoded['raw_count'] as num?)?.toInt() ?? words.length,
      needsImage: decoded['needs_image'] == true,
    );
  }

  /// 设置页「测试连接」。
  Future<String> testConnection(AgentConfig config) async {
    final Uri? uri = config.endpoint('/health');
    if (uri == null) {
      throw const RecognitionFailure(FailureKind.badResponse, '智能体地址格式不正确');
    }
    try {
      final http.Response response = await _client
          .get(uri)
          .timeout(Duration(seconds: config.timeoutSeconds));
      if (response.statusCode != 200) {
        throw RecognitionFailure(
          FailureKind.badResponse,
          '健康检查返回 HTTP ${response.statusCode}',
        );
      }
      final dynamic data = _decode(response.body);
      if (data is Map && data['mock'] == true) {
        return '服务正常，但当前是离线模拟模式（未配置模型 Key）';
      }
      final String model = data is Map ? '${data['model'] ?? ''}' : '';
      return model.isEmpty ? '服务正常' : '服务正常 · 模型 $model';
    } on TimeoutException {
      throw const RecognitionFailure(FailureKind.timeout, '连接超时，检查手机与电脑是否同一 Wi-Fi');
    } on SocketException catch (e) {
      throw RecognitionFailure(FailureKind.network, '连不上智能体服务', detail: e.message);
    }
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

/// 便于 UI 组装的极简工具：判断某句话是否在要求"识别圈选/划线"。
bool instructionNeedsVision(String instruction) {
  final String text = instruction.trim();
  if (text.isEmpty) return false;
  return RegExp(r'圈|画线|划线|标注|勾').hasMatch(text) ||
      text.contains('circle');
}

/// 让本地规则也能粗略过滤一次（没有智能体时的兜底）。
List<WordDraft> localInstructionFilter(
  List<WordDraft> drafts,
  String instruction,
) {
  final String text = instruction.trim();
  if (text.isEmpty) return drafts;

  List<WordDraft> result = drafts;
  if (RegExp(r'名词').hasMatch(text)) {
    result = result.where((WordDraft d) => d.meaning.trim().startsWith('n')).toList();
  } else if (RegExp(r'动词').hasMatch(text)) {
    result = result.where((WordDraft d) => RegExp(r'^v').hasMatch(d.meaning.trim())).toList();
  } else if (RegExp(r'形容词').hasMatch(text)) {
    result = result.where((WordDraft d) => d.meaning.trim().startsWith('adj')).toList();
  }
  if (RegExp(r'带(中文)?释义|有释义').hasMatch(text)) {
    result = result.where((WordDraft d) => d.meaning.trim().isNotEmpty).toList();
  }
  final RegExpMatch? n = RegExp(r'前\s*(\d+)\s*个').firstMatch(text);
  if (n != null) {
    final int k = int.tryParse(n.group(1) ?? '') ?? result.length;
    result = result.take(k).toList();
  }
  // 其余语义型要求（如"只保留生词"）本地无法可靠判断，交给智能体
  return result.map((WordDraft d) {
    d.phonetic = WordText.cleanPhonetic(d.phonetic);
    return d;
  }).toList();
}
