part of '../book_reader_page.dart';

class _ReaderSettingsSheet extends StatefulWidget {
  const _ReaderSettingsSheet({
    required this.visible,
    required this.bottomOffset,
    required this.settings,
    required this.onClose,
    required this.onChanged,
  });

  final bool visible;
  final double bottomOffset;
  final ReaderSettings settings;
  final VoidCallback onClose;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  State<_ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<_ReaderSettingsSheet>
    with _ReaderSheetDragMixin<_ReaderSettingsSheet> {
  late ReaderSettings draft;
  OverlayEntry? _choiceEntry;

  @override
  bool get visible => widget.visible;

  @override
  VoidCallback get onClose => widget.onClose;

  @override
  bool get draggable => false; // Disable drag for settings sheet

  @override
  void initState() {
    super.initState();
    draft = widget.settings;
  }

  void _setDraft(ReaderSettings settings) {
    setState(() => draft = settings);
  }

  void _commit(ReaderSettings settings) {
    _setDraft(settings);
    widget.onChanged(settings);
  }

  void _openChoice(_ReaderSettingsChoice nextChoice) {
    _choiceEntry?.remove();
    _choiceEntry = OverlayEntry(
      builder: (context) => _ReaderSettingsChoiceOverlay(
        choice: nextChoice,
        settings: draft,
        bottomOffset: widget.bottomOffset,
        onClose: _closeChoice,
        onFontStyleSelected: _commitFontStyle,
        onTextIndentSelected: _commitTextIndent,
        onFlowSelected: _commitFlow,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_choiceEntry!);
  }

  void _removeChoiceOverlay() {
    _choiceEntry?.remove();
    _choiceEntry = null;
  }

  void _closeChoice() {
    _removeChoiceOverlay();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _commitFontStyle(ReaderFontStyle fontStyle) {
    final settings = draft.copyWith(fontStyle: fontStyle);
    _commit(settings);
    _closeChoice();
  }

  void _commitTextIndent(ReaderTextIndent textIndent) {
    final settings = draft.copyWith(textIndent: textIndent);
    _commit(settings);
    _closeChoice();
  }

  void _commitFlow(ReaderFlow flow) {
    final settings = draft.copyWith(flow: flow);
    _commit(settings);
    _closeChoice();
  }

  @override
  void didUpdateWidget(covariant _ReaderSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings && !widget.visible) {
      draft = widget.settings;
    }
    if (!oldWidget.visible && widget.visible) {
      draft = widget.settings;
      _removeChoiceOverlay();
    }
    if (oldWidget.visible && !widget.visible) {
      _removeChoiceOverlay();
    }
  }

  @override
  void dispose() {
    _removeChoiceOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ReaderBottomSheetFrame(
      visible: widget.visible,
      bottomOffset: widget.bottomOffset,
      height: _readerFixedSheetHeight(context),
      settings: draft,
      dragOffset: dragOffset,
      onVerticalDragUpdate: handleDragUpdate,
      onVerticalDragEnd: handleDragEnd,
      draggable: draggable,
      child: _ReaderSettingsSheetContent(
        settings: draft,
        onDraftChanged: _setDraft,
        onChanged: _commit,
        onFontStyleTap: () => _openChoice(_ReaderSettingsChoice.fontStyle),
        onTextIndentTap: () => _openChoice(_ReaderSettingsChoice.textIndent),
        onFlowTap: () => _openChoice(_ReaderSettingsChoice.flow),
      ),
    );
  }
}

enum _ReaderSettingsChoice { fontStyle, textIndent, flow }

class _ReaderSettingsSheetContent extends StatelessWidget {
  const _ReaderSettingsSheetContent({
    required this.settings,
    required this.onDraftChanged,
    required this.onChanged,
    required this.onFontStyleTap,
    required this.onTextIndentTap,
    required this.onFlowTap,
  });

  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onDraftChanged;
  final ValueChanged<ReaderSettings> onChanged;
  final VoidCallback onFontStyleTap;
  final VoidCallback onTextIndentTap;
  final VoidCallback onFlowTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ReaderSettingSlider(
                  value: settings.fontSize,
                  min: 12,
                  max: 32,
                  divisions: 20,
                  leading: const Text('A', style: TextStyle(fontSize: 13)),
                  trailing: const Text('A', style: TextStyle(fontSize: 19)),
                  thumbText: settings.fontSize.round().toString(),
                  onChanged: (value) =>
                      onDraftChanged(settings.copyWith(fontSize: value)),
                  onChangeEnd: (value) =>
                      onChanged(settings.copyWith(fontSize: value)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _ReaderSettingSlider(
                        value: settings.margin,
                        min: 0,
                        max: 64,
                        divisions: 32,
                        leading: const Text('小'),
                        trailing: const Text('大'),
                        thumbText: '边距',
                        onChanged: (value) =>
                            onDraftChanged(settings.copyWith(margin: value)),
                        onChangeEnd: (value) =>
                            onChanged(settings.copyWith(margin: value)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ReaderSettingSlider(
                        value: settings.lineHeight,
                        min: 1.1,
                        max: 2.4,
                        divisions: 26,
                        leading: const Text('紧'),
                        trailing: const Text('松'),
                        thumbText: '行距',
                        onChanged: (value) => onDraftChanged(
                          settings.copyWith(lineHeight: value),
                        ),
                        onChangeEnd: (value) =>
                            onChanged(settings.copyWith(lineHeight: value)),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _ReaderModeButton(
                        label: settings.fontStyle.label,
                        onPressed: onFontStyleTap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ReaderModeButton(
                        label: settings.textIndent.label,
                        onPressed: onTextIndentTap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ReaderModeButton(
                        label: settings.flow.label,
                        onPressed: onFlowTap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReaderModeButton extends StatelessWidget {
  const _ReaderModeButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderSettingsChoiceOverlay extends StatefulWidget {
  const _ReaderSettingsChoiceOverlay({
    required this.choice,
    required this.settings,
    required this.bottomOffset,
    required this.onClose,
    required this.onFontStyleSelected,
    required this.onTextIndentSelected,
    required this.onFlowSelected,
  });

  final _ReaderSettingsChoice choice;
  final ReaderSettings settings;
  final double bottomOffset;
  final VoidCallback onClose;
  final ValueChanged<ReaderFontStyle> onFontStyleSelected;
  final ValueChanged<ReaderTextIndent> onTextIndentSelected;
  final ValueChanged<ReaderFlow> onFlowSelected;

  @override
  State<_ReaderSettingsChoiceOverlay> createState() =>
      _ReaderSettingsChoiceOverlayState();
}

class _ReaderSettingsChoiceOverlayState
    extends State<_ReaderSettingsChoiceOverlay>
    with _ReaderSheetDragMixin<_ReaderSettingsChoiceOverlay> {
  @override
  bool get visible => true;

  @override
  VoidCallback get onClose => widget.onClose;

  @override
  Widget build(BuildContext context) {
    final height = _readerFixedSheetHeight(context) + widget.bottomOffset;
    return _ReaderBottomSheetFrame(
      visible: true,
      bottomOffset: 0,
      height: height,
      settings: widget.settings,
      dragOffset: dragOffset,
      onVerticalDragUpdate: handleDragUpdate,
      onVerticalDragEnd: handleDragEnd,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.paddingOf(context).bottom + 16,
              ),
              children: _choiceTiles(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _choiceTiles() {
    return switch (widget.choice) {
      _ReaderSettingsChoice.fontStyle => [
        for (final option in ReaderFontStyle.values)
          _ReaderChoiceTile(
            label: option.label,
            selected: option == widget.settings.fontStyle,
            onTap: () => widget.onFontStyleSelected(option),
          ),
      ],
      _ReaderSettingsChoice.textIndent => [
        for (final option in ReaderTextIndent.values)
          _ReaderChoiceTile(
            label: option.label,
            selected: option == widget.settings.textIndent,
            onTap: () => widget.onTextIndentSelected(option),
          ),
      ],
      _ReaderSettingsChoice.flow => [
        for (final option in ReaderFlow.values)
          _ReaderChoiceTile(
            label: option.label,
            selected: option == widget.settings.flow,
            onTap: () => widget.onFlowSelected(option),
          ),
      ],
    };
  }
}

class _ReaderChoiceTile extends StatelessWidget {
  const _ReaderChoiceTile({
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
    final foreground = selected ? colors.surface : colors.onSurface;
    final background = selected
        ? colors.onSurface
        : colors.surfaceContainerHighest.withValues(alpha: .72);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (selected)
                  Icon(LucideIcons.check, size: 18, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
