part of '../book_reader_page.dart';

Future<void> _setReaderSystemUiVisible(
  bool visible, {
  String? backgroundColor,
}) async {
  // Keep the reader laid out edge-to-edge. System bars are shown as overlays
  // so toggling the controls does not resize the WebView and reflow text.
  if (backgroundColor != null) {
    final navColor = _readerColorFromHex(backgroundColor);
    final iconBrightness = navColor.computeLuminance() > .48
        ? Brightness.dark
        : Brightness.light;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        systemNavigationBarColor: navColor,
        systemNavigationBarDividerColor: navColor,
        systemNavigationBarIconBrightness: iconBrightness,
      ),
    );
  }

  if (visible) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } else {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
}

class _ReaderTapZones extends StatefulWidget {
  const _ReaderTapZones({
    required this.onLongPress,
    required this.onLongPressMove,
    required this.onLongPressEnd,
  });

  final ValueChanged<Offset> onLongPress;
  final ValueChanged<Offset> onLongPressMove;
  final ValueChanged<Offset> onLongPressEnd;

  @override
  State<_ReaderTapZones> createState() => _ReaderTapZonesState();
}

class _ReaderTapZonesState extends State<_ReaderTapZones> {
  bool _isLongPress = false;

  void _handleLongPressStart(LongPressStartDetails details) {
    _isLongPress = true;
    widget.onLongPress(details.globalPosition);
  }

  void _handleLongPressMove(LongPressMoveUpdateDetails details) {
    if (!_isLongPress) {
      return;
    }
    widget.onLongPressMove(details.globalPosition);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_isLongPress) {
      widget.onLongPressEnd(details.globalPosition);
    }
    _isLongPress = false;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: _handleLongPressStart,
        onLongPressMoveUpdate: _handleLongPressMove,
        onLongPressEnd: _handleLongPressEnd,
      ),
    );
  }
}

class _ReaderTextSelection {
  const _ReaderTextSelection({
    required this.text,
    required this.menuAnchor,
    required this.fallbackMenuAnchor,
    required this.startHandle,
    required this.endHandle,
    required this.lineCount,
  });

  final String text;
  final _ReaderMenuAnchor menuAnchor;
  final _ReaderMenuAnchor fallbackMenuAnchor;
  final Offset startHandle;
  final Offset endHandle;
  final int lineCount;

  static _ReaderTextSelection? fromMessage(Map<dynamic, dynamic> message) {
    final menu = _ReaderMenuAnchor.fromMessage(message['menu']);
    final startHandle = _offsetFromMessage(message['startHandle']);
    final endHandle = _offsetFromMessage(message['endHandle']);
    if (menu == null || startHandle == null || endHandle == null) {
      return null;
    }
    final rawLineCount = message['lineCount'];
    return _ReaderTextSelection(
      text: message['text']?.toString() ?? '',
      menuAnchor: menu,
      fallbackMenuAnchor:
          _ReaderMenuAnchor.fromMessage(message['fallbackMenu']) ?? menu,
      startHandle: startHandle,
      endHandle: endHandle,
      lineCount: rawLineCount is num ? math.max(1, rawLineCount.round()) : 1,
    );
  }

  static Offset? _offsetFromMessage(Object? value) {
    if (value is! Map) {
      return null;
    }
    final x = value['x'];
    final y = value['y'];
    if (x is! num || y is! num) {
      return null;
    }
    return Offset(x.toDouble(), y.toDouble());
  }
}

class _ReaderMenuAnchor {
  const _ReaderMenuAnchor({
    required this.x,
    required this.top,
    required this.bottom,
  });

  final double x;
  final double top;
  final double bottom;

  static _ReaderMenuAnchor? fromMessage(Object? value) {
    if (value is! Map) {
      return null;
    }
    final x = value['x'];
    final y = value['y'];
    if (x is! num || y is! num) {
      return null;
    }
    final top = value['top'];
    final bottom = value['bottom'];
    final fallbackY = y.toDouble();
    return _ReaderMenuAnchor(
      x: x.toDouble(),
      top: top is num ? top.toDouble() : fallbackY,
      bottom: bottom is num ? bottom.toDouble() : fallbackY,
    );
  }
}

class _ReaderTextAction {
  const _ReaderTextAction({
    required this.kind,
    required this.label,
    required this.icon,
  });

  final _ReaderTextActionKind kind;
  final String label;
  final IconData icon;
}

enum _ReaderTextActionKind { copy, highlight, note, search, translate, share }

const _readerTextActions = <_ReaderTextAction>[
  _ReaderTextAction(
    kind: _ReaderTextActionKind.copy,
    label: '复制',
    icon: LucideIcons.copy,
  ),
  _ReaderTextAction(
    kind: _ReaderTextActionKind.highlight,
    label: '划线',
    icon: LucideIcons.highlighter,
  ),
  _ReaderTextAction(
    kind: _ReaderTextActionKind.note,
    label: '写想法',
    icon: LucideIcons.notebookPen,
  ),
  _ReaderTextAction(
    kind: _ReaderTextActionKind.search,
    label: '查询',
    icon: LucideIcons.search,
  ),
  _ReaderTextAction(
    kind: _ReaderTextActionKind.translate,
    label: '翻译',
    icon: LucideIcons.languages,
  ),
  _ReaderTextAction(
    kind: _ReaderTextActionKind.share,
    label: '分享',
    icon: LucideIcons.share2,
  ),
];

class _ReaderTextActionMenu extends StatelessWidget {
  const _ReaderTextActionMenu({
    required this.anchor,
    required this.fallbackAnchor,
    required this.lineCount,
    required this.actions,
    required this.onSelected,
    required this.highlightMode,
    required this.highlightStyle,
    required this.highlightColor,
    required this.translationStatus,
    required this.translationText,
    required this.onHighlightStyleChanged,
    required this.onHighlightColorChanged,
    required this.onDeleteHighlight,
  });

  final _ReaderMenuAnchor anchor;
  final _ReaderMenuAnchor fallbackAnchor;
  final int lineCount;
  final List<_ReaderTextAction> actions;
  final ValueChanged<_ReaderTextActionKind> onSelected;
  final bool highlightMode;
  final _ReaderHighlightStyle highlightStyle;
  final _ReaderHighlightColorOption highlightColor;
  final _ReaderTranslationStatus translationStatus;
  final String translationText;
  final ValueChanged<_ReaderHighlightStyle> onHighlightStyleChanged;
  final ValueChanged<_ReaderHighlightColorOption> onHighlightColorChanged;
  final VoidCallback onDeleteHighlight;

  static const double _horizontalPadding = 12;
  static const double _verticalPadding = 10;
  static const double _itemWidth = 58;
  static const double _height = 76;
  static const double _screenGap = 12;
  static const double _textGap = 32;
  static const double _arrowWidth = 18;
  static const double _arrowHeight = 9;
  static const double _arrowSideInset = 28;
  static const double _maxWidth = 420;
  static const double _toolsGap = 14;
  static const double _toolsHeight = 44;
  static const double _translationGap = 12;
  static const double _translationMaxWidth = 340;
  static const double _translationMaxHeight = 180;
  static const Color _menuColor = Colors.black;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final availableHeight = constraints.maxHeight;
          const totalHeight = _height + _arrowHeight;
          const highlightTotalHeight =
              _height + _arrowHeight + _toolsGap + _toolsHeight;
          final groupHeight = highlightMode
              ? highlightTotalHeight
              : totalHeight;
          final toolsWidth = math
              .min(360, math.max<double>(0, availableWidth - _screenGap * 2))
              .toDouble();
          final menuWidth = math.min(
            _maxWidth,
            math.max<double>(0, availableWidth - _screenGap * 2),
          );
          final minTop = padding.top + _screenGap;
          final maxTop = math.max(
            minTop,
            availableHeight - padding.bottom - groupHeight - _screenGap,
          );
          var effectiveAnchor = anchor;
          final preferBelow = lineCount > 1;
          final aboveAnchor = preferBelow ? fallbackAnchor : anchor;
          final belowTop = anchor.bottom + _textGap;
          final aboveTop = aboveAnchor.top - _textGap - groupHeight;
          final belowFits = belowTop <= maxTop;
          final aboveFits = aboveTop >= minTop;
          final placeBelow = preferBelow
              ? belowFits || !aboveFits
              : belowFits && !aboveFits;
          final placeCentered = !belowFits && !aboveFits;
          double preferredTop;
          if (placeCentered) {
            preferredTop = (availableHeight - groupHeight) / 2;
            effectiveAnchor = fallbackAnchor;
          } else if (placeBelow) {
            preferredTop = belowTop;
          } else {
            effectiveAnchor = aboveAnchor;
            preferredTop = aboveTop;
          }
          final left = (effectiveAnchor.x - menuWidth / 2)
              .clamp(
                _screenGap,
                math.max(_screenGap, availableWidth - menuWidth - _screenGap),
              )
              .toDouble();
          final top = preferredTop.clamp(minTop, maxTop);
          final arrowCenter = (effectiveAnchor.x - left)
              .clamp(
                _arrowSideInset,
                math.max(_arrowSideInset, menuWidth - _arrowSideInset),
              )
              .toDouble();
          final arrowLeft = arrowCenter - _arrowWidth / 2;
          final arrowOnTop = placeBelow && !placeCentered;
          final menuTop = arrowOnTop
              ? top + _arrowHeight
              : highlightMode
              ? top + _toolsHeight + _toolsGap
              : top;
          final arrowTop = arrowOnTop ? top : menuTop + _height;
          final toolsLeft = (effectiveAnchor.x - toolsWidth / 2)
              .clamp(
                _screenGap,
                math.max(_screenGap, availableWidth - toolsWidth - _screenGap),
              )
              .toDouble();
          final toolsTop = arrowOnTop ? menuTop + _height + _toolsGap : top;
          final translationVisible =
              translationStatus != _ReaderTranslationStatus.idle;
          final translationWidth = math.min(
            _translationMaxWidth,
            math.max<double>(0, availableWidth - _screenGap * 2),
          );
          final translationLeft = (effectiveAnchor.x - translationWidth / 2)
              .clamp(
                _screenGap,
                math.max(
                  _screenGap,
                  availableWidth - translationWidth - _screenGap,
                ),
              )
              .toDouble();
          final translationAnchorTop = highlightMode
              ? math.min(menuTop, toolsTop)
              : menuTop;
          final translationAnchorBottom = highlightMode
              ? math.max(menuTop + _height, toolsTop + _toolsHeight)
              : menuTop + _height;
          final preferredTranslationTop = arrowOnTop
              ? translationAnchorBottom + _translationGap
              : translationAnchorTop - _translationMaxHeight - _translationGap;
          final translationTop = preferredTranslationTop
              .clamp(
                minTop,
                math.max(
                  minTop,
                  availableHeight -
                      padding.bottom -
                      _translationMaxHeight -
                      _screenGap,
                ),
              )
              .toDouble();

          return Stack(
            children: [
              Positioned(
                left: left,
                top: menuTop,
                width: menuWidth,
                height: _height,
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _menuColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: _horizontalPadding,
                          vertical: _verticalPadding,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final action in actions)
                              SizedBox(
                                width: _itemWidth,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap:
                                      action.kind ==
                                              _ReaderTextActionKind.highlight &&
                                          highlightMode
                                      ? onDeleteHighlight
                                      : () => onSelected(action.kind),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          action.kind ==
                                                      _ReaderTextActionKind
                                                          .highlight &&
                                                  highlightMode
                                              ? LucideIcons.eraser
                                              : action.icon,
                                          color: Colors.white,
                                          size: 21,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          action.kind ==
                                                      _ReaderTextActionKind
                                                          .highlight &&
                                                  highlightMode
                                              ? '删除划线'
                                              : action.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (highlightMode)
                Positioned(
                  left: toolsLeft,
                  top: toolsTop,
                  width: toolsWidth,
                  height: _toolsHeight,
                  child: _ReaderHighlightTools(
                    selectedStyle: highlightStyle,
                    selectedColor: highlightColor,
                    onStyleChanged: onHighlightStyleChanged,
                    onColorChanged: onHighlightColorChanged,
                  ),
                ),
              if (translationVisible)
                Positioned(
                  left: translationLeft,
                  top: translationTop,
                  width: translationWidth,
                  child: _ReaderTranslationBubble(
                    status: translationStatus,
                    text: translationText,
                    maxHeight: _translationMaxHeight,
                  ),
                ),
              Positioned(
                left: left + arrowLeft,
                top: arrowTop,
                width: _arrowWidth,
                height: _arrowHeight,
                child: CustomPaint(
                  painter: _ReaderMenuArrowPainter(
                    color: _menuColor,
                    pointsUp: arrowOnTop,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReaderTranslationBubble extends StatefulWidget {
  const _ReaderTranslationBubble({
    required this.status,
    required this.text,
    required this.maxHeight,
  });

  final _ReaderTranslationStatus status;
  final String text;
  final double maxHeight;

  @override
  State<_ReaderTranslationBubble> createState() =>
      _ReaderTranslationBubbleState();
}

class _ReaderTranslationBubbleState extends State<_ReaderTranslationBubble> {
  Timer? _timer;
  int _dotCount = 1;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(_ReaderTranslationBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status != oldWidget.status) {
      _dotCount = 1;
      _syncTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    if (widget.status != _ReaderTranslationStatus.loading) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) {
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 360), (_) {
      if (mounted) {
        setState(() => _dotCount = _dotCount % 3 + 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loading = widget.status == _ReaderTranslationStatus.loading;
    final text = loading
        ? List.filled(_dotCount, '.').join()
        : widget.text.trim().isEmpty
        ? '翻译失败'
        : widget.text.trim();
    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      shadowColor: const Color(0x55000000),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: loading ? 44 : 0,
          maxHeight: widget.maxHeight,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: loading ? 10 : 12,
          ),
          child: Align(
            alignment: loading ? Alignment.center : Alignment.centerLeft,
            child: Text(
              text,
              textAlign: loading ? TextAlign.center : TextAlign.start,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderHighlightTools extends StatelessWidget {
  const _ReaderHighlightTools({
    required this.selectedStyle,
    required this.selectedColor,
    required this.onStyleChanged,
    required this.onColorChanged,
  });

  final _ReaderHighlightStyle selectedStyle;
  final _ReaderHighlightColorOption selectedColor;
  final ValueChanged<_ReaderHighlightStyle> onStyleChanged;
  final ValueChanged<_ReaderHighlightColorOption> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ReaderHighlightStyleButton(
              selected: selectedStyle == _ReaderHighlightStyle.highlight,
              selectedColor: selectedColor.color,
              tooltip: '高亮',
              onTap: () => onStyleChanged(_ReaderHighlightStyle.highlight),
              child: _ReaderHighlightMarkIcon(
                color: _styleColor(
                  selectedStyle == _ReaderHighlightStyle.highlight,
                  selectedColor.color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ReaderHighlightStyleButton(
              selected: selectedStyle == _ReaderHighlightStyle.underline,
              selectedColor: selectedColor.color,
              tooltip: '下划线',
              onTap: () => onStyleChanged(_ReaderHighlightStyle.underline),
              child: Icon(
                LucideIcons.underline,
                size: 18,
                color: _styleColor(
                  selectedStyle == _ReaderHighlightStyle.underline,
                  selectedColor.color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ReaderHighlightStyleButton(
              selected: selectedStyle == _ReaderHighlightStyle.squiggle,
              selectedColor: selectedColor.color,
              tooltip: '波浪线',
              onTap: () => onStyleChanged(_ReaderHighlightStyle.squiggle),
              child: Icon(
                LucideIcons.waves,
                size: 18,
                color: _styleColor(
                  selectedStyle == _ReaderHighlightStyle.squiggle,
                  selectedColor.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in _readerHighlightColors) ...[
                  _ReaderHighlightColorDot(
                    option: option,
                    selected: option.hex == selectedColor.hex,
                    onTap: () => onColorChanged(option),
                  ),
                  if (option != _readerHighlightColors.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Color _styleColor(bool selected, Color selectedColor) {
    return selected ? selectedColor : Colors.white.withValues(alpha: .74);
  }
}

class _ReaderHighlightStyleButton extends StatelessWidget {
  const _ReaderHighlightStyleButton({
    required this.selected,
    required this.selectedColor,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final Color selectedColor;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black,
        elevation: 6,
        shadowColor: const Color(0x33000000),
        shape: CircleBorder(
          side: selected
              ? BorderSide(color: selectedColor, width: 1.4)
              : BorderSide.none,
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(dimension: 36, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _ReaderHighlightMarkIcon extends StatelessWidget {
  const _ReaderHighlightMarkIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 1,
            bottom: 3,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
          Positioned(
            right: 1,
            top: 0,
            child: Text(
              'A',
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderHighlightColorDot extends StatelessWidget {
  const _ReaderHighlightColorDot({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ReaderHighlightColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final checkColor = option.color.computeLuminance() > .55
        ? Colors.black
        : Colors.white;
    return Tooltip(
      message: option.hex,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: option.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: .16),
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: selected
                  ? Icon(LucideIcons.check, size: 16, color: checkColor)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderMenuArrowPainter extends CustomPainter {
  const _ReaderMenuArrowPainter({required this.color, required this.pointsUp});

  final Color color;
  final bool pointsUp;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (pointsUp) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ReaderMenuArrowPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointsUp != pointsUp;
  }
}

class _ReaderSelectionHandle extends StatefulWidget {
  const _ReaderSelectionHandle({
    required this.position,
    required this.color,
    required this.borderColor,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Offset position;
  final Color color;
  final Color borderColor;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final ValueChanged<Offset> onDragEnd;

  @override
  State<_ReaderSelectionHandle> createState() => _ReaderSelectionHandleState();
}

class _ReaderSelectionHandleState extends State<_ReaderSelectionHandle> {
  Offset? _lastDragPosition;

  static const double _touchSize = 44;
  static const double _baseTopOffset = 4;
  static const double _handleLift = 10;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.position.dx - _touchSize / 2,
      top: widget.position.dy - _baseTopOffset - _handleLift,
      width: _touchSize,
      height: _touchSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          _lastDragPosition = details.globalPosition;
          widget.onDragStart(details.globalPosition);
        },
        onPanUpdate: (details) {
          _lastDragPosition = details.globalPosition;
          widget.onDragUpdate(details.globalPosition);
        },
        onPanEnd: (_) => widget.onDragEnd(_lastDragPosition ?? widget.position),
        onPanCancel: () =>
            widget.onDragEnd(_lastDragPosition ?? widget.position),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 2,
                height: 14,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: widget.borderColor, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderErrorOverlay extends StatelessWidget {
  const _ReaderErrorOverlay({
    required this.error,
    required this.onCopyDiagnostics,
  });

  final String error;
  final VoidCallback onCopyDiagnostics;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onCopyDiagnostics,
                icon: const Icon(LucideIcons.copy, size: 16),
                label: const Text('复制诊断日志'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderControlsOverlay extends StatelessWidget {
  const _ReaderControlsOverlay({
    required this.visible,
    required this.tocVisible,
    required this.annotationsVisible,
    required this.progressVisible,
    required this.backgroundVisible,
    required this.settingsVisible,
    required this.selectedPanel,
    required this.enabledPanels,
    required this.settings,
    required this.appearanceOptions,
    required this.progress,
    required this.readingDuration,
    required this.noteCount,
    required this.tocItems,
    required this.annotations,
    required this.annotationsLoading,
    required this.chapterTranslationStatus,
    required this.selectedTocIndex,
    required this.readerContext,
    required this.chromeBuilders,
    required this.onBack,
    required this.chapterTranslationEnabled,
    required this.onToggleChapterTranslation,
    required this.onSelectPanel,
    required this.onDismiss,
    required this.onCloseToc,
    required this.onCloseAnnotations,
    required this.onCloseProgress,
    required this.onCloseBackground,
    required this.onCloseSettings,
    required this.onTocItemSelected,
    required this.onAnnotationSelected,
    required this.onProgressChanged,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.autoPaging,
    required this.onToggleAutoPaging,
    required this.onShowReadingDetails,
    required this.onSettingsChanged,
  });

  final bool visible;
  final bool tocVisible;
  final bool annotationsVisible;
  final bool progressVisible;
  final bool backgroundVisible;
  final bool settingsVisible;
  final _ReaderPanel selectedPanel;
  final List<_ReaderPanel> enabledPanels;
  final ReaderSettings settings;
  final ReaderAppearanceOptions appearanceOptions;
  final double progress;
  final Duration readingDuration;
  final int noteCount;
  final List<_ReaderTocItem> tocItems;
  final List<_ReaderAnnotationItem> annotations;
  final bool annotationsLoading;
  final _ReaderTranslationStatus chapterTranslationStatus;
  final int selectedTocIndex;
  final ReaderChromeContext readerContext;
  final ReaderChromeBuilders chromeBuilders;
  final VoidCallback onBack;
  final bool chapterTranslationEnabled;
  final VoidCallback onToggleChapterTranslation;
  final ValueChanged<_ReaderPanel> onSelectPanel;
  final VoidCallback onDismiss;
  final VoidCallback onCloseToc;
  final VoidCallback onCloseAnnotations;
  final VoidCallback onCloseProgress;
  final VoidCallback onCloseBackground;
  final VoidCallback onCloseSettings;
  final ValueChanged<_ReaderTocItem> onTocItemSelected;
  final ValueChanged<_ReaderAnnotationItem> onAnnotationSelected;
  final ValueChanged<double> onProgressChanged;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final bool autoPaging;
  final VoidCallback? onToggleAutoPaging;
  final VoidCallback onShowReadingDetails;
  final ValueChanged<ReaderSettings> onSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final readerColors = _readerSheetColorScheme(colors, settings);
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final bottomBarHeight = 72 + bottomPadding;
    final fixedSheetOpen =
        progressVisible || backgroundVisible || settingsVisible;
    final sheetOpen =
        tocVisible ||
        annotationsVisible ||
        progressVisible ||
        backgroundVisible ||
        settingsVisible;
    final topBarVisible = visible && !sheetOpen;
    final listenButtonBottom =
        bottomBarHeight +
        (fixedSheetOpen ? _readerFixedSheetHeight(context) : 0) +
        10;
    return IgnorePointer(
      ignoring: !visible,
      child: Stack(
        children: [
          // Full-screen barrier under the bars/sheets: while controls are open,
          // tapping or dragging the content area only dismisses the overlay and
          // never reaches the WebView (no page turn / scroll passthrough).
          if (visible)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                onVerticalDragStart: (_) => onDismiss(),
                onHorizontalDragStart: (_) => onDismiss(),
              ),
            ),
          if (visible && tocVisible)
            chromeBuilders.panelBuilder?.call(
                  context,
                  readerContext,
                  ReaderPanel.toc,
                ) ??
                _ReaderTocSheet(
                  visible: true,
                  bottomOffset: bottomBarHeight,
                  settings: settings,
                  items: tocItems,
                  selectedIndex: selectedTocIndex,
                  onClose: onCloseToc,
                  onItemSelected: onTocItemSelected,
                ),
          if (visible && annotationsVisible)
            chromeBuilders.panelBuilder?.call(
                  context,
                  readerContext,
                  ReaderPanel.annotations,
                ) ??
                _ReaderAnnotationsSheet(
                  visible: true,
                  bottomOffset: bottomBarHeight,
                  settings: settings,
                  annotations: annotations,
                  loading: annotationsLoading,
                  onClose: onCloseAnnotations,
                  onItemSelected: onAnnotationSelected,
                ),
          if (visible && progressVisible)
            chromeBuilders.panelBuilder?.call(
                  context,
                  readerContext,
                  ReaderPanel.progress,
                ) ??
                _ReaderProgressSheet(
                  visible: true,
                  bottomOffset: bottomBarHeight,
                  settings: settings,
                  progress: progress,
                  readingDuration: readingDuration,
                  noteCount: noteCount,
                  onClose: onCloseProgress,
                  onProgressChanged: onProgressChanged,
                  onPreviousChapter: onPreviousChapter,
                  onNextChapter: onNextChapter,
                  autoPaging: autoPaging,
                  onToggleAutoPaging: onToggleAutoPaging,
                  onShowReadingDetails: onShowReadingDetails,
                ),
          if (visible && backgroundVisible)
            chromeBuilders.panelBuilder?.call(
                  context,
                  readerContext,
                  ReaderPanel.background,
                ) ??
                _ReaderBackgroundSheet(
                  visible: true,
                  bottomOffset: bottomBarHeight,
                  settings: settings,
                  appearanceOptions: appearanceOptions,
                  onClose: onCloseBackground,
                  onChanged: onSettingsChanged,
                ),
          if (visible && settingsVisible)
            chromeBuilders.panelBuilder?.call(
                  context,
                  readerContext,
                  ReaderPanel.font,
                ) ??
                _ReaderSettingsSheet(
                  visible: true,
                  bottomOffset: bottomBarHeight,
                  settings: settings,
                  onClose: onCloseSettings,
                  onChanged: onSettingsChanged,
                ),
          if (visible && !tocVisible && !annotationsVisible)
            _ReaderListenButton(
              bottom: listenButtonBottom,
              colors: readerColors,
              onPressed: () {},
            ),
          if (topBarVisible)
            chromeBuilders.topBarBuilder?.call(context, readerContext) ??
                _ReaderTopBar(
                  visible: true,
                  topPadding: topPadding,
                  colors: readerColors,
                  onBack: onBack,
                  chapterTranslationStatus: chapterTranslationStatus,
                  translationEnabled: chapterTranslationEnabled,
                  onToggleChapterTranslation: onToggleChapterTranslation,
                )
          else
            _ReaderTopBar(
              visible: false,
              topPadding: topPadding,
              colors: readerColors,
              onBack: onBack,
              chapterTranslationStatus: chapterTranslationStatus,
              translationEnabled: chapterTranslationEnabled,
              onToggleChapterTranslation: onToggleChapterTranslation,
            ),
          if (visible)
            chromeBuilders.bottomBarBuilder?.call(context, readerContext) ??
                _ReaderBottomBar(
                  visible: true,
                  bottomPadding: bottomPadding,
                  colors: readerColors,
                  settings: settings,
                  selectedPanel: selectedPanel,
                  enabledPanels: enabledPanels,
                  onSelectPanel: onSelectPanel,
                )
          else
            _ReaderBottomBar(
              visible: false,
              bottomPadding: bottomPadding,
              colors: readerColors,
              settings: settings,
              selectedPanel: selectedPanel,
              enabledPanels: enabledPanels,
              onSelectPanel: onSelectPanel,
            ),
        ],
      ),
    );
  }
}

class _ReaderListenButton extends StatelessWidget {
  const _ReaderListenButton({
    required this.bottom,
    required this.colors,
    required this.onPressed,
  });

  final double bottom;
  final ColorScheme colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      right: 16,
      bottom: bottom,
      child: Theme(
        data: Theme.of(context).copyWith(colorScheme: colors),
        child: Material(
          color: colors.surface.withValues(alpha: .96),
          shape: const CircleBorder(),
          elevation: 8,
          shadowColor: colors.shadow.withValues(alpha: .18),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 42,
              child: Icon(
                LucideIcons.audioLines,
                size: 20,
                color: colors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoPageSettingsButton extends StatelessWidget {
  const _AutoPageSettingsButton({
    required this.visible,
    required this.leftInset,
    required this.colors,
    required this.onPressed,
  });

  final bool visible;
  final double leftInset;
  final ColorScheme colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: leftInset,
      bottom: 16 + safeBottom,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: IgnorePointer(
          ignoring: !visible,
          child: Theme(
            data: Theme.of(context).copyWith(colorScheme: colors),
            child: Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onPressed,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.timer,
                          size: 14,
                          color: colors.onSurface,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '自动翻页',
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoPageProgressBar extends StatelessWidget {
  const _AutoPageProgressBar({
    required this.visible,
    required this.progress,
    required this.colors,
  });

  final bool visible;
  final double progress;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: safeBottom,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: IgnorePointer(
          child: SizedBox(
            height: 4,
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: colors.onSurface.withValues(alpha: .12),
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.visible,
    required this.topPadding,
    required this.colors,
    required this.onBack,
    required this.chapterTranslationStatus,
    required this.translationEnabled,
    required this.onToggleChapterTranslation,
  });

  final bool visible;
  final double topPadding;
  final ColorScheme colors;
  final VoidCallback onBack;
  final _ReaderTranslationStatus chapterTranslationStatus;
  final bool translationEnabled;
  final VoidCallback onToggleChapterTranslation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Theme(
            data: theme.copyWith(colorScheme: colors),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: .94),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: .12),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.only(top: topPadding),
                child: SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: '返回',
                          onPressed: onBack,
                          icon: const Icon(LucideIcons.arrowLeft),
                        ),
                        const Spacer(),
                        if (translationEnabled)
                          _ReaderChapterTranslationButton(
                            status: chapterTranslationStatus,
                            onPressed: onToggleChapterTranslation,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderChapterTranslationButton extends StatelessWidget {
  const _ReaderChapterTranslationButton({
    required this.status,
    required this.onPressed,
  });

  final _ReaderTranslationStatus status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final loading = status == _ReaderTranslationStatus.loading;
    final translated = status == _ReaderTranslationStatus.success;
    final label = loading
        ? '翻译中'
        : translated
        ? '恢复原文'
        : '本章翻译';
    final icon = translated ? LucideIcons.refreshCcw : LucideIcons.languages;
    return TextButton.icon(
      onPressed: loading ? null : onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      icon: loading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.visible,
    required this.bottomPadding,
    required this.colors,
    required this.settings,
    required this.selectedPanel,
    required this.enabledPanels,
    required this.onSelectPanel,
  });

  final bool visible;
  final double bottomPadding;
  final ColorScheme colors;
  final ReaderSettings settings;
  final _ReaderPanel selectedPanel;
  final List<_ReaderPanel> enabledPanels;
  final ValueChanged<_ReaderPanel> onSelectPanel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Theme(
            data: theme.copyWith(colorScheme: colors),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: .94),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: .14),
                    blurRadius: 24,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: SizedBox(
                  height: 72,
                  child: Row(
                    children: [
                      for (final panel in enabledPanels)
                        Expanded(
                          child: _ReaderPanelButton(
                            panel: panel,
                            selected: panel == selectedPanel,
                            backgroundColor: settings.backgroundColor,
                            onPressed: () => onSelectPanel(panel),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderPanelButton extends StatelessWidget {
  const _ReaderPanelButton({
    required this.panel,
    required this.selected,
    required this.backgroundColor,
    required this.onPressed,
  });

  final _ReaderPanel panel;
  final bool selected;
  final String backgroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Use darkened background when selected, onSurfaceVariant when unselected.
    final Color color;
    if (selected) {
      final bgColor = _readerColorFromHex(backgroundColor);
      // Darken the background color by reducing luminance
      final hsl = HSLColor.fromColor(bgColor);
      final darkenedHsl = hsl.withLightness(
        (hsl.lightness * 0.5).clamp(0.0, 1.0),
      );
      color = darkenedHsl.toColor();
    } else {
      color = colors.onSurfaceVariant;
    }

    return InkWell(
      onTap: onPressed,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 160),
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: color,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(panel.icon, color: color, size: 22),
            const SizedBox(height: 5),
            Text(panel.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
