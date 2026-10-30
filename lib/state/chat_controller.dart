import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_config.dart';
import '../data/word_draft.dart';
import '../services/agent_service.dart';
import '../services/chat_service.dart';
import '../services/image_store.dart';
import '../services/ocr_service.dart';
import '../services/permission_service.dart';
import '../services/phonetic_lookup.dart';
import '../services/recognition_failure.dart';
import 'settings_store.dart';
import 'word_store.dart';

enum ChatRole { user, agent }

/// 一条聊天记录。图片消息只保留本地路径，发给服务端时再临时编码。
class ChatMessage {
  ChatMessage({
    required this.role,
    this.text = '',
    this.imagePath,
    this.note,
    this.local = false,
  });

  final ChatRole role;
  final String text;
  final String? imagePath;

  /// 写入单词本的结果（"已写入：新增 8，合并 2"），仅展示用
  final String? note;

  /// 本机提示（权限被拒等），不进入发给模型的历史
  final bool local;
}

/// 对话式识别的状态：聊天记录 + 上一轮候选词。
///
/// "单次上下文记忆"= 这个 controller 的生命周期。退出页面即清空，
/// 下次进来是全新对话（服务端不存任何会话）。
class ChatController extends ChangeNotifier {
  ChatController({
    required OcrService ocr,
    required WordStore words,
    required SettingsStore settings,
    required ImageStore imageStore,
    required PhoneticLookup phonetic,
    ChatService? service,
    PermissionService permission = const PermissionService(),
  })  : _ocr = ocr,
        _words = words,
        _settings = settings,
        _imageStore = imageStore,
        _phonetic = phonetic,
        _service = service ?? ChatService(),
        _permission = permission;

  final OcrService _ocr;
  final WordStore _words;
  final SettingsStore _settings;
  final ImageStore _imageStore;
  final PhoneticLookup _phonetic;
  final ChatService _service;
  final PermissionService _permission;

  final List<ChatMessage> _messages = <ChatMessage>[];
  List<WordDraft> _candidates = const <WordDraft>[];
  bool _busy = false;
  bool _disposed = false;
  String? _error;

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
  bool get busy => _busy;
  String? get error => _error;
  bool get isEmpty => _messages.isEmpty;

  /// 上一轮从照片里读到的全部候选词（供"只留名词"这类追问继续筛）
  int get candidateCount => _candidates.length;

  void reset() {
    if (_busy) return;
    _messages.clear();
    _candidates = const <WordDraft>[];
    _error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> sendText(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty || _busy) return;
    await _send(text: trimmed);
  }

  Future<bool> sendImage(ImageSource source, {String? instruction}) async {
    if (_busy) return false;

    final PermissionOutcome outcome = source == ImageSource.camera
        ? await _permission.ensureCamera()
        : await _permission.ensureGallery();
    if (outcome != PermissionOutcome.granted) {
      _error = outcome == PermissionOutcome.permanentlyDenied
          ? '权限已被拒绝，请在系统设置里开启'
          : '没有拿到权限，暂时打不开';
      _messages.add(ChatMessage(role: ChatRole.agent, text: _error!, local: true));
      _notify();
      return false;
    }

    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 88,
        preferredCameraDevice: CameraDevice.rear,
      );
    } catch (_) {
      _error = source == ImageSource.camera ? '无法打开相机' : '无法打开相册';
      _messages.add(ChatMessage(role: ChatRole.agent, text: _error!, local: true));
      _notify();
      return false;
    }
    if (file == null) return false;

    // 本地 OCR 只作为读图的兜底提示，失败不影响主流程
    String? ocrText;
    try {
      ocrText = await _ocr.recognize(file.path);
    } catch (_) {
      ocrText = null;
    }

    await _send(
      text: (instruction ?? '').trim(),
      imagePath: file.path,
      ocrText: ocrText,
    );
    return true;
  }

  Future<void> _send({
    required String text,
    String? imagePath,
    String? ocrText,
  }) async {
    _messages.add(ChatMessage(
      role: ChatRole.user,
      text: text,
      imagePath: imagePath,
    ));
    _busy = true;
    _error = null;
    _notify();

    try {
      final List<String> known = await _words.masteredWordList();
      final ChatReply reply = await _service.send(
        config: AgentConfig(baseUrl: AppConfig.agentBaseUrl),
        history: _historyForApi(),
        // 隐私开关在代码里：关掉后只发本地 OCR 文本，照片不出手机
        imagePath: AppConfig.agentAllowVision ? imagePath : null,
        ocrText: ocrText,
        candidates: _candidates,
        knownWords: known,
      );

      _candidates = reply.candidates;
      final String? note =
          await _applyImports(reply.imports, imagePath: imagePath);
      _messages.add(ChatMessage(
        role: ChatRole.agent,
        text: reply.reply.isEmpty ? '完成了。' : reply.reply,
        note: note,
      ));
    } on RecognitionFailure catch (f) {
      _error = f.message;
      _messages.add(ChatMessage(
        role: ChatRole.agent,
        text: '没连上智能体：${f.message}',
      ));
    } catch (e) {
      _error = '$e';
      _messages.add(ChatMessage(
        role: ChatRole.agent,
        text: '出错了：$e',
      ));
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 只发文字历史；图片用占位符，避免每轮都重传 base64
  List<ChatTurn> _historyForApi() {
    return _messages
        .where((ChatMessage m) => !m.local)
        .map((ChatMessage m) => ChatTurn(
              role: m.role == ChatRole.user ? 'user' : 'assistant',
              content: m.text.isNotEmpty
                  ? m.text
                  : (m.imagePath != null ? '[发送了一张照片]' : ''),
            ))
        .where((ChatTurn t) => t.content.trim().isNotEmpty)
        .toList(growable: false);
  }

  /// 执行服务端要求的写库动作，返回给用户看的一行结果
  Future<String?> _applyImports(
    List<List<WordDraft>> groups, {
    String? imagePath,
  }) async {
    if (groups.isEmpty) return null;

    String? storedImage;
    if (_settings.saveSourceImage && imagePath != null) {
      try {
        storedImage = await _imageStore.persist(imagePath);
      } catch (_) {
        storedImage = null;
      }
    }

    final List<String> parts = <String>[];
    for (final List<WordDraft> group in groups) {
      final List<WordDraft> drafts =
          group.where((WordDraft d) => d.isValid).toList();
      if (drafts.isEmpty) continue;
      try {
        await _phonetic.fillMissing(
          drafts,
          allowNetwork: _settings.validatePhoneticOnline,
        );
        final SaveReport report =
            await _words.saveDrafts(drafts, imagePath: storedImage);
        parts.add(report.summary);
      } catch (e) {
        parts.add('写入失败：$e');
      }
    }
    if (parts.isEmpty) return null;
    return '已写入单词本：${parts.join('；')}';
  }
}
