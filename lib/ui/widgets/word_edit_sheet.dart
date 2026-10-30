import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/word_text.dart';
import '../../data/word.dart';
import '../../state/word_store.dart';

/// 编辑单词的底部弹层。返回 true 表示已保存。
Future<bool?> showWordEditSheet(BuildContext context, Word word) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext ctx) => _WordEditSheet(word: word),
  );
}

class _WordEditSheet extends StatefulWidget {
  const _WordEditSheet({required this.word});

  final Word word;

  @override
  State<_WordEditSheet> createState() => _WordEditSheetState();
}

class _WordEditSheetState extends State<_WordEditSheet> {
  late final TextEditingController _wordController;
  late final TextEditingController _phoneticController;
  late final TextEditingController _meaningController;
  late bool _mastered;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _wordController = TextEditingController(text: widget.word.word);
    _phoneticController = TextEditingController(text: widget.word.phonetic);
    _meaningController = TextEditingController(text: widget.word.meaning);
    _mastered = widget.word.mastered;
  }

  @override
  void dispose() {
    _wordController.dispose();
    _phoneticController.dispose();
    _meaningController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String rawWord = _wordController.text.trim();
    if (WordText.cleanWord(rawWord).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写有效的英文单词')),
      );
      return;
    }
    setState(() => _saving = true);
    await context.read<WordStore>().editWord(
          widget.word,
          text: rawWord,
          phonetic: _phoneticController.text,
          meaning: _meaningController.text,
          mastered: _mastered,
        );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '编辑单词',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            _Label('单词'),
            TextField(
              controller: _wordController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: '例如 abandon'),
            ),
            const SizedBox(height: 14),
            _Label('音标（可留空）'),
            TextField(
              controller: _phoneticController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: '例如 /əˈbændən/'),
            ),
            const SizedBox(height: 14),
            _Label('中文释义'),
            TextField(
              controller: _meaningController,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(hintText: '例如 v. 放弃；抛弃'),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              value: _mastered,
              onChanged: (bool v) => setState(() => _mastered = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('标记为已掌握', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                '已掌握的单词在列表里会显示对勾',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final bool? ok = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext ctx) => AlertDialog(
                            title: const Text('删除这个单词？'),
                            content: Text(
                              '「${widget.word.word}」及其复习记录会一并删除，无法恢复。',
                              style: const TextStyle(fontSize: 14, height: 1.6),
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                style: TextButton.styleFrom(
                                  foregroundColor: scheme.error,
                                ),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await context.read<WordStore>().deleteWord(widget.word.id);
                          if (context.mounted) Navigator.of(context).pop(true);
                        }
                      },
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: const Text('删除单词'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
