part of '../book_reader_page.dart';

class _ReaderBackgroundSheet extends StatefulWidget {
  const _ReaderBackgroundSheet({
    required this.visible,
    required this.bottomOffset,
    required this.settings,
    required this.appearanceOptions,
    required this.onClose,
    required this.onChanged,
  });

  final bool visible;
  final double bottomOffset;
  final ReaderSettings settings;
  final ReaderAppearanceOptions appearanceOptions;
  final VoidCallback onClose;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  State<_ReaderBackgroundSheet> createState() => _ReaderBackgroundSheetState();
}

class _ReaderBackgroundSheetState extends State<_ReaderBackgroundSheet>
    with _ReaderSheetDragMixin<_ReaderBackgroundSheet> {
  late ReaderSettings draft;

  @override
  bool get visible => widget.visible;

  @override
  VoidCallback get onClose => widget.onClose;

  @override
  bool get draggable => false; // Disable drag for background sheet

  @override
  void initState() {
    super.initState();
    draft = widget.settings;
  }

  @override
  void didUpdateWidget(covariant _ReaderBackgroundSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.visible && widget.visible) {
      draft = widget.settings;
    }
  }

  void _commit(ReaderSettings settings) {
    setState(() => draft = settings);
    widget.onChanged(settings);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.appearanceOptions.safeBackgroundColors;
    final backgroundImages = widget.appearanceOptions.safeBackgroundImages;
    return _ReaderBottomSheetFrame(
      visible: widget.visible,
      bottomOffset: widget.bottomOffset,
      height: _readerFixedSheetHeight(context),
      settings: draft,
      dragOffset: dragOffset,
      onVerticalDragUpdate: handleDragUpdate,
      onVerticalDragEnd: handleDragEnd,
      draggable: draggable,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ReaderSettingSlider(
                    value: draft.brightness,
                    min: .55,
                    max: 1.25,
                    divisions: 14,
                    leading: const Icon(LucideIcons.sunDim, size: 17),
                    trailing: const Icon(LucideIcons.sun, size: 23),
                    thumbText: '${(draft.brightness * 100).round()}',
                    onChanged: (value) => setState(
                      () => draft = draft.copyWith(brightness: value),
                    ),
                    onChangeEnd: (value) =>
                        _commit(draft.copyWith(brightness: value)),
                  ),
                  if (colors.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '颜色',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            for (final (index, color) in colors.indexed) ...[
                              Expanded(
                                child: _ReaderColorChoice(
                                  hex: color,
                                  selected:
                                      draft.backgroundImage.isEmpty &&
                                      draft.backgroundColor == color,
                                  onTap: () => _commit(
                                    draft.copyWith(
                                      backgroundColor: color,
                                      backgroundImage: '',
                                    ),
                                  ),
                                ),
                              ),
                              if (index != colors.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ],
                    ),
                  if (backgroundImages.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '背景',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            for (final (index, image)
                                in backgroundImages.indexed) ...[
                              Expanded(
                                child: _ReaderBackgroundImageChoice(
                                  image: image,
                                  backgroundColor: draft.backgroundColor,
                                  selected: draft.backgroundImage == image,
                                  onTap: () => _commit(
                                    draft.copyWith(backgroundImage: image),
                                  ),
                                ),
                              ),
                              if (index != backgroundImages.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderColorChoice extends StatelessWidget {
  const _ReaderColorChoice({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  Color get color {
    final value =
        int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0xfbfaf7;
    return Color(0xff000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: colors.primary, width: 2) : null,
        ),
        child: const SizedBox(height: 36),
      ),
    );
  }
}

class _ReaderBackgroundImageChoice extends StatelessWidget {
  const _ReaderBackgroundImageChoice({
    required this.image,
    required this.backgroundColor,
    required this.selected,
    required this.onTap,
  });

  final String image;
  final String backgroundColor;
  final bool selected;
  final VoidCallback onTap;

  Color get color {
    final value =
        int.tryParse(backgroundColor.replaceFirst('#', ''), radix: 16) ??
        0xfbfaf7;
    return Color(0xff000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(12);
    return InkWell(
      borderRadius: borderRadius,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            border: selected
                ? Border.all(color: colors.primary, width: 2)
                : null,
            image: DecorationImage(
              image: AssetImage(
                'assets/reader/$image',
                package: 'arkivio_reader',
              ),
              fit: BoxFit.cover,
            ),
          ),
          child: const SizedBox(height: 36),
        ),
      ),
    );
  }
}
