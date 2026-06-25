part of '../book_reader_page.dart';

class _ReaderSearchOverlay extends StatefulWidget {
  const _ReaderSearchOverlay({
    required this.settings,
    required this.query,
    required this.loading,
    required this.chapters,
    required this.onQueryChanged,
    required this.onClear,
    required this.onResultSelected,
    required this.onClose,
  });

  final ReaderSettings settings;
  final String query;
  final bool loading;
  final List<_ReaderSearchChapter> chapters;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final ValueChanged<_ReaderSearchItem> onResultSelected;
  final VoidCallback onClose;

  @override
  State<_ReaderSearchOverlay> createState() => _ReaderSearchOverlayState();
}

class _ReaderSearchOverlayState extends State<_ReaderSearchOverlay> {
  late final TextEditingController _controller;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _ReaderSearchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _readerSheetColorScheme(
      Theme.of(context).colorScheme,
      widget.settings,
    );
    return Positioned.fill(
      child: Theme(
        data: Theme.of(context).copyWith(colorScheme: colors),
        child: ColoredBox(
          color: colors.surface,
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Transform.translate(
                  offset: Offset(0, _dragOffset),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth > 840
                            ? 760
                            : constraints.maxWidth,
                      ),
                      child: Column(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragUpdate: (details) {
                              final nextOffset = _dragOffset + details.delta.dy;
                              setState(() {
                                _dragOffset = nextOffset.clamp(0, 180);
                              });
                            },
                            onVerticalDragEnd: (details) {
                              final shouldClose =
                                  _dragOffset > 72 ||
                                  details.primaryVelocity != null &&
                                      details.primaryVelocity! > 520;
                              if (shouldClose) {
                                widget.onClose();
                                return;
                              }
                              setState(() {
                                _dragOffset = 0;
                              });
                            },
                            onVerticalDragCancel: () {
                              setState(() {
                                _dragOffset = 0;
                              });
                            },
                            child: const SizedBox(
                              height: 36,
                              child: Center(child: _ReaderSheetHandle()),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                            child: _ReaderSearchField(
                              controller: _controller,
                              onChanged: widget.onQueryChanged,
                              onClear: () {
                                _controller.clear();
                                widget.onClear();
                              },
                            ),
                          ),
                          Expanded(
                            child: _ReaderSearchResults(
                              query: widget.query,
                              loading: widget.loading,
                              chapters: widget.chapters,
                              onResultSelected: widget.onResultSelected,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderSearchField extends StatelessWidget {
  const _ReaderSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fieldColor = Color.alphaBlend(
      colors.onSurface.withValues(alpha: .06),
      colors.surface,
    );
    return Material(
      color: fieldColor,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 42,
        child: TextField(
          controller: controller,
          autofocus: true,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: TextStyle(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
          cursorColor: colors.primary,
          decoration: InputDecoration(
            isDense: true,
            hintText: '搜索',
            hintStyle: TextStyle(color: colors.onSurfaceVariant),
            prefixIcon: Icon(
              LucideIcons.search,
              color: colors.onSurfaceVariant,
              size: 18,
            ),
            prefixIconConstraints: const BoxConstraints.tightFor(
              width: 40,
              height: 40,
            ),
            suffixIcon: IconButton(
              tooltip: '清空',
              onPressed: onClear,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              padding: EdgeInsets.zero,
              icon: Icon(
                LucideIcons.x,
                color: colors.onSurfaceVariant,
                size: 18,
              ),
            ),
            suffixIconConstraints: const BoxConstraints.tightFor(
              width: 40,
              height: 40,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
    );
  }
}

class _ReaderSearchResults extends StatelessWidget {
  const _ReaderSearchResults({
    required this.query,
    required this.loading,
    required this.chapters,
    required this.onResultSelected,
  });

  final String query;
  final bool loading;
  final List<_ReaderSearchChapter> chapters;
  final ValueChanged<_ReaderSearchItem> onResultSelected;

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = query.trim();
    final entries = _ReaderSearchListEntry.fromChapters(chapters);
    if (trimmedQuery.isEmpty) {
      return const _ReaderSearchEmptyState(text: '输入关键词');
    }
    if (loading && chapters.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (chapters.isEmpty) {
      return const _ReaderSearchEmptyState(text: '无匹配结果');
    }
    return Stack(
      children: [
        ListView.builder(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: loading ? 12 : 4,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final chapterLabel = entry.chapterLabel;
            if (chapterLabel != null) {
              return _ReaderSearchChapterHeader(label: chapterLabel);
            }
            final item = entry.item!;
            return _ReaderSearchResultCard(
              item: item,
              onTap: () => onResultSelected(item),
            );
          },
        ),
        if (loading)
          const Positioned(
            left: 16,
            right: 16,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _ReaderSearchEmptyState extends StatelessWidget {
  const _ReaderSearchEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ReaderSearchChapterHeader extends StatelessWidget {
  const _ReaderSearchChapterHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Text(
        label.isEmpty ? '当前章节' : label,
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

class _ReaderSearchResultCard extends StatelessWidget {
  const _ReaderSearchResultCard({required this.item, required this.onTap});

  final _ReaderSearchItem item;
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
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: _ReaderSearchResultText(item: item),
          ),
        ),
      ),
    );
  }
}

class _ReaderSearchResultText extends StatelessWidget {
  const _ReaderSearchResultText({required this.item});

  final _ReaderSearchItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: colors.onSurface, height: 1.45);
    final matchStyle = baseStyle?.copyWith(
      color: colors.primary,
      fontWeight: FontWeight.w800,
    );
    return RichText(
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: item.pre),
          TextSpan(text: item.match, style: matchStyle),
          TextSpan(text: item.post),
        ],
      ),
    );
  }
}

class _ReaderSearchListEntry {
  const _ReaderSearchListEntry.chapter(this.chapterLabel) : item = null;

  const _ReaderSearchListEntry.item(this.item) : chapterLabel = null;

  final String? chapterLabel;
  final _ReaderSearchItem? item;

  static List<_ReaderSearchListEntry> fromChapters(
    List<_ReaderSearchChapter> chapters,
  ) {
    return [
      for (final chapter in chapters) ...[
        _ReaderSearchListEntry.chapter(chapter.label),
        for (final item in chapter.items) _ReaderSearchListEntry.item(item),
      ],
    ];
  }
}
