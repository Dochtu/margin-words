import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../services/image_store.dart';
import '../../services/ocr_service.dart';
import '../../services/phonetic_lookup.dart';
import '../../state/chat_controller.dart';
import '../../state/settings_store.dart';
import '../../state/word_store.dart';

/// 对话式提取：发照片 / 说要求 → 智能体筛词 → 直接写进单词本。
///
/// 聊天记录只在本页面存活，退出即清空（"单次上下文记忆"）。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _chat;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _chat = ChatController(
      ocr: context.read<OcrService>(),
      words: context.read<WordStore>(),
      settings: context.read<SettingsStore>(),
      imageStore: const ImageStore(),
      phonetic: context.read<PhoneticLookup>(),
    );
    _chat.addListener(_scrollToBottom);
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _chat
      ..removeListener(_scrollToBottom)
      ..dispose();
    _input
      ..removeListener(_onInputChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onInputChanged() => setState(() {});

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendText() async {
    final String text = _input.text;
    _input.clear();
    await _chat.sendText(text);
  }

  /// 拍照/选图时把输入框里还没发出的要求一起带上，避免“先写要求再拍照”时被丢掉。
  Future<void> _sendImage(ImageSource source) async {
    final String text = _input.text.trim();
    _input.clear();
    final bool sent = await _chat.sendImage(
      source,
      instruction: text.isEmpty ? null : text,
    );
    // 取消拍照/没拿到权限时把文字放回去，别让用户白打一遍。
    if (!sent && text.isNotEmpty && mounted) {
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('对话提取'),
        actions: <Widget>[
          AnimatedBuilder(
            animation: _chat,
            builder: (BuildContext context, _) {
              if (_chat.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: '新对话',
                onPressed: _chat.busy ? null : _chat.reset,
                icon: const Icon(Icons.add_comment_outlined, size: 20),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _chat,
        builder: (BuildContext context, _) {
          return Column(
            children: <Widget>[
              Expanded(
                child: _chat.isEmpty ? const _EmptyView() : _buildList(),
              ),
              if (_chat.busy)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              _InputBar(
                controller: _input,
                enabled: !_chat.busy,
                canSend: _input.text.trim().isNotEmpty && !_chat.busy,
                onSend: _sendText,
                onCamera: () => _sendImage(ImageSource.camera),
                onGallery: () => _sendImage(ImageSource.gallery),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList() {
    final List<ChatMessage> messages = _chat.messages;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      itemCount: messages.length,
      itemBuilder: (BuildContext context, int index) {
        return _Bubble(message: messages[index]);
      },
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.photo_camera_outlined,
            size: 34,
            color: scheme.primary.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 12),
          Text(
            '发一张照片开始',
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool mine = message.role == ChatRole.user;

    final Widget content = Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: <Widget>[
        if (message.imagePath != null) ...<Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Image.file(
              File(message.imagePath!),
              height: 168,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          if (message.text.isNotEmpty) const SizedBox(height: 8),
        ],
        if (message.text.isNotEmpty)
          Text(
            message.text,
            style: const TextStyle(fontSize: 14, height: 1.55),
          ),
        if (message.note != null) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.check_circle_outline, size: 13, color: scheme.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  message.note!,
                  style: TextStyle(fontSize: 11.5, color: scheme.primary),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? scheme.primary.withValues(alpha: 0.09)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: mine
                ? scheme.primary.withValues(alpha: 0.16)
                : scheme.outlineVariant,
            width: 1,
          ),
        ),
        child: content,
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.canSend,
    required this.onSend,
    required this.onCamera,
    required this.onGallery,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool canSend;
  final VoidCallback onSend;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            IconButton(
              onPressed: enabled ? onCamera : null,
              tooltip: '拍照',
              icon: const Icon(Icons.photo_camera_outlined, size: 21),
            ),
            IconButton(
              onPressed: enabled ? onGallery : null,
              tooltip: '相册',
              icon: const Icon(Icons.photo_library_outlined, size: 21),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (canSend) onSend();
                },
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '说要求，例如：只要名词',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: canSend ? onSend : null,
              tooltip: '发送',
              icon: const Icon(Icons.arrow_upward_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
