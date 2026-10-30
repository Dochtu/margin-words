import 'package:flutter/material.dart';

import '../../core/app_date.dart';
import '../../core/app_theme.dart';
import '../../data/word.dart';

/// 单词列表行：单词加粗、音标次级色、释义常规色，固定行高，长释义可展开。
class WordTile extends StatefulWidget {
  const WordTile({
    super.key,
    required this.word,
    this.onEdit,
    this.onDelete,
    this.onLongPress,
    this.onSelect,
    this.selectionMode = false,
    this.selected = false,
    this.showMeta = true,
  });

  final Word word;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// 长按进入多选；多选状态下点击整行用于勾选/取消。
  final VoidCallback? onLongPress;
  final VoidCallback? onSelect;
  final bool selectionMode;
  final bool selected;
  final bool showMeta;

  @override
  State<WordTile> createState() => _WordTileState();
}

class _WordTileState extends State<WordTile> {
  bool _expanded = false;

  bool get _canExpand =>
      widget.word.meaning.length > 24 || widget.word.meaning.contains('\n');

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Word word = widget.word;

    final double scale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.35);
    final double collapsedHeight = 86 * scale;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: BoxConstraints(minHeight: collapsedHeight),
        decoration: BoxDecoration(
          color: widget.selected
              ? scheme.primary.withValues(alpha: 0.06)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: widget.selected
                ? scheme.primary.withValues(alpha: 0.55)
                : scheme.outlineVariant,
            width: widget.selected ? 1.2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.selectionMode
                ? widget.onSelect
                : (_canExpand
                    ? () => setState(() => _expanded = !_expanded)
                    : null),
            onLongPress: widget.onLongPress,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 6, 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (widget.selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(left: 2, right: 8, top: 1),
                      child: Icon(
                        widget.selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 22,
                        color: widget.selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                word.word,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 17,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            if (word.phonetic.isNotEmpty) ...<Widget>[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  word.phonetic,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.3,
                                    color: scheme.onSurfaceVariant
                                        .withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          word.meaning.isEmpty ? '（暂无释义）' : word.meaning,
                          maxLines: _expanded ? null : 1,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.55,
                            color: word.meaning.isEmpty
                                ? scheme.onSurfaceVariant
                                    .withValues(alpha: 0.6)
                                : scheme.onSurface.withValues(alpha: 0.86),
                          ),
                        ),
                        if (widget.showMeta) ...<Widget>[
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              Text(
                                AppDate.monthDay(word.studyDate),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant
                                      .withValues(alpha: 0.65),
                                ),
                              ),
                              if (word.reviewCount > 0) ...<Widget>[
                                const SizedBox(width: 8),
                                Text(
                                  '复习 ${word.reviewCount} 次',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant
                                        .withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (word.mastered)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 2),
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: scheme.primary.withValues(alpha: 0.85),
                          ),
                        ),
                      if (!widget.selectionMode) ...<Widget>[
                        if (widget.onEdit != null || widget.onDelete != null)
                          PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            splashRadius: 18,
                            tooltip: '更多',
                            color: Theme.of(context).cardColor,
                            icon: Icon(
                              Icons.more_vert_rounded,
                              size: 19,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.75),
                            ),
                            onSelected: (String value) {
                              if (value == 'edit') widget.onEdit?.call();
                              if (value == 'delete') widget.onDelete?.call();
                            },
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<String>>[
                              const PopupMenuItem<String>(
                                value: 'edit',
                                height: 44,
                                child: Text('编辑',
                                    style: TextStyle(fontSize: 14)),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                height: 44,
                                child: Text(
                                  '删除',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
