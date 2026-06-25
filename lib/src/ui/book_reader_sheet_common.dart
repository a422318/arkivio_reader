part of '../book_reader_page.dart';

mixin _ReaderSheetDragMixin<T extends StatefulWidget> on State<T> {
  double dragOffset = 0;

  bool get visible;

  VoidCallback get onClose;

  // Subclasses can override this to disable drag functionality
  bool get draggable => true;

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!visible) {
      dragOffset = 0;
    }
  }

  void handleDragUpdate(DragUpdateDetails details) {
    if (!draggable) {
      return;
    }
    if (details.delta.dy <= 0 && dragOffset == 0) {
      return;
    }
    setState(() => dragOffset = (dragOffset + details.delta.dy).clamp(0, 240));
  }

  void handleDragEnd(DragEndDetails details) {
    if (!draggable) {
      return;
    }
    if (dragOffset > 72 ||
        details.primaryVelocity != null && details.primaryVelocity! > 500) {
      onClose();
    }
    if (!mounted) {
      return;
    }
    setState(() => dragOffset = 0);
  }
}

class _ReaderBottomSheetFrame extends StatelessWidget {
  const _ReaderBottomSheetFrame({
    required this.visible,
    required this.bottomOffset,
    required this.height,
    required this.settings,
    required this.dragOffset,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.child,
    this.draggable = true,
  });

  final bool visible;
  final double bottomOffset;
  final double? height;
  final ReaderSettings settings;
  final double dragOffset;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;
  final Widget child;
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sheetColors = _readerSheetColorScheme(colors, settings);
    final sheetHeight =
        height ?? MediaQuery.sizeOf(context).height - bottomOffset;

    Widget content = SizedBox(
      height: sheetHeight,
      child: Theme(
        data: theme.copyWith(colorScheme: sheetColors),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: sheetColors.surface.withValues(alpha: .98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: .18),
                blurRadius: 28,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                _ReaderSheetHeader(showHandle: draggable),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );

    // Only wrap with GestureDetector if draggable
    if (draggable) {
      content = GestureDetector(
        onVerticalDragUpdate: onVerticalDragUpdate,
        onVerticalDragEnd: onVerticalDragEnd,
        child: content,
      );
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomOffset,
      child: AnimatedSlide(
        offset: visible
            ? Offset(0, dragOffset / sheetHeight)
            : const Offset(0, 1),
        duration: visible && dragOffset > 0
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: content,
        ),
      ),
    );
  }
}

class _ReaderSheetHeader extends StatelessWidget {
  const _ReaderSheetHeader({this.showHandle = true});

  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: showHandle ? 32 : 12,
      child: showHandle ? const Center(child: _ReaderSheetHandle()) : null,
    );
  }
}

class _ReaderSheetHandle extends StatelessWidget {
  const _ReaderSheetHandle();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.outlineVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const SizedBox(width: 42, height: 4),
      ),
    );
  }
}

double _readerFixedSheetHeight(BuildContext context) {
  return (MediaQuery.sizeOf(context).height * .25).clamp(180.0, 240.0);
}

Color _readerColorFromHex(String hex) {
  final normalized = hex.trim().replaceFirst('#', '');
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) {
    return const Color(0xFFFBFAF7);
  }
  return Color(0xFF000000 | value);
}

Color _readerOnColor(Color background) {
  return background.computeLuminance() > .48
      ? const Color(0xFF24211D)
      : const Color(0xFFF7F3EA);
}

Color _readerSelectionAccentColor(String backgroundHex) {
  final background = _readerColorFromHex(backgroundHex);
  final hsl = HSLColor.fromColor(background);
  final lightBackground = background.computeLuminance() > .48;
  final saturation = math.max(hsl.saturation, .24);
  final lightness = lightBackground
      ? (hsl.lightness * .42).clamp(.18, .38)
      : (.78 + hsl.lightness * .08).clamp(.72, .86);
  return hsl.withSaturation(saturation).withLightness(lightness).toColor();
}

ColorScheme _readerSheetColorScheme(ColorScheme base, ReaderSettings settings) {
  final surface = _readerColorFromHex(settings.backgroundColor);
  final onSurface = _readerOnColor(surface);
  return base.copyWith(
    surface: surface,
    onSurface: onSurface,
    surfaceContainerHighest: Color.alphaBlend(
      onSurface.withValues(alpha: .08),
      surface,
    ),
    onSurfaceVariant: onSurface.withValues(alpha: .68),
    outlineVariant: onSurface.withValues(alpha: .18),
    primary: onSurface,
    onPrimary: surface,
  );
}

class _ReaderSettingSlider extends StatelessWidget {
  const _ReaderSettingSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    required this.leading,
    required this.trailing,
    required this.thumbText,
    this.onLeadingTap,
    this.onTrailingTap,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Widget leading;
  final Widget trailing;
  final String thumbText;
  final VoidCallback? onLeadingTap;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return _ReaderPillSlider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
      leading: leading,
      trailing: trailing,
      thumbText: thumbText,
      onLeadingTap: onLeadingTap,
      onTrailingTap: onTrailingTap,
    );
  }
}

class _ReaderPillSlider extends StatefulWidget {
  const _ReaderPillSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    required this.leading,
    required this.trailing,
    required this.thumbText,
    this.onLeadingTap,
    this.onTrailingTap,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Widget leading;
  final Widget trailing;
  final String thumbText;
  final VoidCallback? onLeadingTap;
  final VoidCallback? onTrailingTap;

  static const double _height = 48;
  static const double _thumbSize = 44;

  @override
  State<_ReaderPillSlider> createState() => _ReaderPillSliderState();
}

class _ReaderPillSliderState extends State<_ReaderPillSlider> {
  double? _lastInteractionValue;

  double _normalize(double raw) {
    final clamped = raw.clamp(widget.min, widget.max);
    if (widget.divisions <= 0 || widget.max <= widget.min) {
      return clamped;
    }
    final step = (widget.max - widget.min) / widget.divisions;
    return widget.min + ((clamped - widget.min) / step).round() * step;
  }

  double _valueForDx(double dx, double width) {
    final travel = (width - _ReaderPillSlider._thumbSize).clamp(
      1.0,
      double.infinity,
    );
    final fraction = ((dx - _ReaderPillSlider._thumbSize / 2) / travel).clamp(
      0.0,
      1.0,
    );
    return _normalize(widget.min + (widget.max - widget.min) * fraction);
  }

  void _updateFromPosition(Offset position, double width) {
    final next = _valueForDx(position.dx, width);
    _lastInteractionValue = next;
    widget.onChanged(next);
  }

  void _commitLastValue() {
    widget.onChangeEnd(_lastInteractionValue ?? _normalize(widget.value));
    _lastInteractionValue = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final current = _normalize(widget.value);
    final fraction = widget.max <= widget.min
        ? 0.0
        : ((current - widget.min) / (widget.max - widget.min));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final travel = (width - _ReaderPillSlider._thumbSize).clamp(
          0.0,
          double.infinity,
        );
        final thumbLeft = travel * fraction.clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) =>
              _updateFromPosition(details.localPosition, width),
          onHorizontalDragUpdate: (details) =>
              _updateFromPosition(details.localPosition, width),
          onHorizontalDragEnd: (_) => _commitLastValue(),
          child: SizedBox(
            height: _ReaderPillSlider._height,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: .78,
                      ),
                      borderRadius: BorderRadius.circular(
                        _ReaderPillSlider._height / 2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          _ReaderSliderSideAction(
                            onTap: widget.onLeadingTap,
                            child: IconTheme.merge(
                              data: IconThemeData(
                                color: colors.onSurfaceVariant,
                                size: 18,
                              ),
                              child: DefaultTextStyle.merge(
                                style: Theme.of(context).textTheme.labelLarge!
                                    .copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                                child: widget.leading,
                              ),
                            ),
                          ),
                          const Spacer(),
                          _ReaderSliderSideAction(
                            onTap: widget.onTrailingTap,
                            child: IconTheme.merge(
                              data: IconThemeData(
                                color: colors.onSurfaceVariant,
                                size: 22,
                              ),
                              child: DefaultTextStyle.merge(
                                style: Theme.of(context).textTheme.labelLarge!
                                    .copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.w800,
                                    ),
                                child: widget.trailing,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: thumbLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.surface,
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: .18),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SizedBox.square(
                      dimension: _ReaderPillSlider._thumbSize,
                      child: Center(
                        child: Text(
                          widget.thumbText,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReaderSliderSideAction extends StatelessWidget {
  const _ReaderSliderSideAction({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(dimension: 34, child: Center(child: child)),
    );
  }
}
