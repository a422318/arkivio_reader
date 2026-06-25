part of '../book_reader_page.dart';

class _ReaderTocSheet extends StatefulWidget {
  const _ReaderTocSheet({
    required this.visible,
    required this.bottomOffset,
    required this.settings,
    required this.items,
    required this.selectedIndex,
    required this.onClose,
    required this.onItemSelected,
  });

  final bool visible;
  final double bottomOffset;
  final ReaderSettings settings;
  final List<_ReaderTocItem> items;
  final int selectedIndex;
  final VoidCallback onClose;
  final ValueChanged<_ReaderTocItem> onItemSelected;

  @override
  State<_ReaderTocSheet> createState() => _ReaderTocSheetState();
}

class _ReaderTocSheetState extends State<_ReaderTocSheet>
    with _ReaderSheetDragMixin<_ReaderTocSheet> {
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
      child: _ReaderTocSheetContent(
        visible: widget.visible,
        items: widget.items,
        selectedIndex: widget.selectedIndex,
        onItemSelected: widget.onItemSelected,
      ),
    );
  }
}

class _ReaderTocSheetContent extends StatefulWidget {
  const _ReaderTocSheetContent({
    required this.visible,
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  final bool visible;
  final List<_ReaderTocItem> items;
  final int selectedIndex;
  final ValueChanged<_ReaderTocItem> onItemSelected;

  @override
  State<_ReaderTocSheetContent> createState() => _ReaderTocSheetContentState();
}

class _ReaderTocSheetContentState extends State<_ReaderTocSheetContent> {
  static const double _itemExtent = 48;
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(_ReaderTocSheetContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameVisible = widget.visible && !oldWidget.visible;
    final selectionChanged = widget.selectedIndex != oldWidget.selectedIndex;
    if (widget.visible && (becameVisible || selectionChanged)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  void _revealSelected() {
    if (!_controller.hasClients || widget.selectedIndex < 0) {
      return;
    }
    final viewport = _controller.position.viewportDimension;
    final target =
        widget.selectedIndex * _itemExtent - (viewport - _itemExtent) / 2;
    final clamped = target.clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      clamped,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: widget.items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text('暂无目录'),
                  ),
                )
              : ListView.builder(
                  controller: _controller,
                  padding: EdgeInsets.zero,
                  itemExtent: _itemExtent,
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    final selected = index == widget.selectedIndex;
                    final depth = item.depth.clamp(0, 4);
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor: colors.primary.withValues(
                          alpha: 0.1,
                        ),
                        contentPadding: EdgeInsets.only(
                          left: 20 + depth * 16,
                          right: 20,
                        ),
                        title: Text(
                          item.label.isEmpty ? item.href : item.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? colors.primary : null,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        onTap: () => widget.onItemSelected(item),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
