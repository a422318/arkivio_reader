part of '../book_reader_page.dart';

class _ReaderAnnotationsSheet extends StatefulWidget {
  const _ReaderAnnotationsSheet({
    required this.visible,
    required this.bottomOffset,
    required this.settings,
    required this.annotations,
    required this.loading,
    required this.onClose,
    required this.onItemSelected,
  });

  final bool visible;
  final double bottomOffset;
  final ReaderSettings settings;
  final List<_ReaderAnnotationItem> annotations;
  final bool loading;
  final VoidCallback onClose;
  final ValueChanged<_ReaderAnnotationItem> onItemSelected;

  @override
  State<_ReaderAnnotationsSheet> createState() =>
      _ReaderAnnotationsSheetState();
}

class _ReaderAnnotationsSheetState extends State<_ReaderAnnotationsSheet>
    with _ReaderSheetDragMixin<_ReaderAnnotationsSheet> {
  @override
  bool get visible => widget.visible;

  @override
  VoidCallback get onClose => widget.onClose;

  @override
  Widget build(BuildContext context) {
    return _ReaderBottomSheetFrame(
      visible: widget.visible,
      bottomOffset: widget.bottomOffset,
      height: null,
      settings: widget.settings,
      dragOffset: dragOffset,
      onVerticalDragUpdate: handleDragUpdate,
      onVerticalDragEnd: handleDragEnd,
      child: _ReaderAnnotationsSheetContent(
        annotations: widget.annotations,
        loading: widget.loading,
        onItemSelected: widget.onItemSelected,
      ),
    );
  }
}

class _ReaderAnnotationsSheetContent extends StatefulWidget {
  const _ReaderAnnotationsSheetContent({
    required this.annotations,
    required this.loading,
    required this.onItemSelected,
  });

  final List<_ReaderAnnotationItem> annotations;
  final bool loading;
  final ValueChanged<_ReaderAnnotationItem> onItemSelected;

  @override
  State<_ReaderAnnotationsSheetContent> createState() =>
      _ReaderAnnotationsSheetContentState();
}

class _ReaderAnnotationsSheetContentState
    extends State<_ReaderAnnotationsSheetContent> {
  int _tabIndex = 0;

  bool get _showNotes => _tabIndex == 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items = widget.annotations
        .where((item) => _showNotes ? item.isNote : !item.isNote)
        .toList(growable: false);
    final rows = _ReaderAnnotationRow.rowsFor(items);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _ReaderAnnotationsTabs(
                index: _tabIndex,
                onChanged: (index) => setState(() => _tabIndex = index),
              ),
            ),
          ),
        ),
        Expanded(
          child: widget.loading
              ? Center(child: CircularProgressIndicator(color: colors.primary))
              : rows.isEmpty
              ? Center(
                  child: Text(
                    _showNotes ? '暂无笔记' : '暂无划线',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalPadding = constraints.maxWidth > 820
                        ? (constraints.maxWidth - 760) / 2 + 16
                        : 16.0;
                    return ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        24,
                      ),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final chapter = row.chapter;
                        if (chapter != null) {
                          return _ReaderAnnotationChapterHeader(label: chapter);
                        }
                        final item = row.item!;
                        return item.isNote
                            ? _ReaderNoteAnnotationCard(
                                item: item,
                                onTap: () => widget.onItemSelected(item),
                              )
                            : _ReaderHighlightAnnotationCard(
                                item: item,
                                onTap: () => widget.onItemSelected(item),
                              );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ReaderAnnotationsTabs extends StatelessWidget {
  const _ReaderAnnotationsTabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = Color.alphaBlend(
      colors.onSurface.withValues(alpha: .07),
      colors.surface,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            _ReaderAnnotationsTabButton(
              label: '笔记',
              selected: index == 0,
              onTap: () => onChanged(0),
            ),
            _ReaderAnnotationsTabButton(
              label: '划线',
              selected: index == 1,
              onTap: () => onChanged(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderAnnotationsTabButton extends StatelessWidget {
  const _ReaderAnnotationsTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedColor = Color.alphaBlend(
      colors.onSurface.withValues(alpha: .12),
      colors.surface,
    );
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? selectedColor : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderAnnotationChapterHeader extends StatelessWidget {
  const _ReaderAnnotationChapterHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ReaderNoteAnnotationCard extends StatelessWidget {
  const _ReaderNoteAnnotationCard({required this.item, required this.onTap});

  final _ReaderAnnotationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cardColor = Color.alphaBlend(
      colors.onSurface.withValues(alpha: .055),
      colors.surface,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.notebookPen,
                      size: 18,
                      color: colors.onSurface,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.note.trim().isEmpty ? item.text : item.note,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 2,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.outlineVariant,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.45,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderHighlightAnnotationCard extends StatelessWidget {
  const _ReaderHighlightAnnotationCard({
    required this.item,
    required this.onTap,
  });

  final _ReaderAnnotationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cardColor = Color.alphaBlend(
      colors.onSurface.withValues(alpha: .055),
      colors.surface,
    );
    final highlightColor = _readerHighlightColorByHex(item.colorHex).color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReaderHighlightAnnotationIcon(
                  style: item.style,
                  color: highlightColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderHighlightAnnotationIcon extends StatelessWidget {
  const _ReaderHighlightAnnotationIcon({
    required this.style,
    required this.color,
  });

  final String style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final normalized = _ReaderHighlightStyle.fromValue(style);
    final icon = switch (normalized) {
      _ReaderHighlightStyle.underline => LucideIcons.underline,
      _ReaderHighlightStyle.squiggle => LucideIcons.waves,
      _ReaderHighlightStyle.highlight => LucideIcons.highlighter,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .28),
        shape: BoxShape.circle,
      ),
      child: SizedBox.square(
        dimension: 28,
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

class _ReaderAnnotationRow {
  const _ReaderAnnotationRow.chapter(this.chapter) : item = null;

  const _ReaderAnnotationRow.item(this.item) : chapter = null;

  final String? chapter;
  final _ReaderAnnotationItem? item;

  static List<_ReaderAnnotationRow> rowsFor(List<_ReaderAnnotationItem> items) {
    final grouped = <String, List<_ReaderAnnotationItem>>{};
    for (final item in items) {
      final chapter = item.chapterLabel.trim().isEmpty
          ? '未知章节'
          : item.chapterLabel.trim();
      grouped.putIfAbsent(chapter, () => []).add(item);
    }
    return [
      for (final entry in grouped.entries) ...[
        _ReaderAnnotationRow.chapter(entry.key),
        for (final item in entry.value) _ReaderAnnotationRow.item(item),
      ],
    ];
  }
}
