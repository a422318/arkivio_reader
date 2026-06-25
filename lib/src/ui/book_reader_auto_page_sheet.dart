part of '../book_reader_page.dart';

class _AutoPageSettingsSheet extends StatefulWidget {
  const _AutoPageSettingsSheet({
    required this.visible,
    required this.settings,
    required this.onClose,
    required this.onSpeedChanged,
  });

  final bool visible;
  final ReaderSettings settings;
  final VoidCallback onClose;
  final ValueChanged<double> onSpeedChanged;

  @override
  State<_AutoPageSettingsSheet> createState() => _AutoPageSettingsSheetState();
}

class _AutoPageSettingsSheetState extends State<_AutoPageSettingsSheet>
    with _ReaderSheetDragMixin<_AutoPageSettingsSheet> {
  late double draftSpeed;

  @override
  bool get visible => widget.visible;

  @override
  VoidCallback get onClose => widget.onClose;

  @override
  void initState() {
    super.initState();
    draftSpeed = widget.settings.autoPageSpeed;
  }

  @override
  void didUpdateWidget(covariant _AutoPageSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible ||
        oldWidget.settings.autoPageSpeed != widget.settings.autoPageSpeed) {
      draftSpeed = widget.settings.autoPageSpeed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Wrap-content height: sheet handle + title + slider + paddings, plus the
    // bottom safe-area inset so it isn't a full-screen sheet.
    final sheetHeight = 150 + MediaQuery.paddingOf(context).bottom;
    return _ReaderBottomSheetFrame(
      visible: widget.visible,
      bottomOffset: 0,
      height: sheetHeight,
      settings: widget.settings,
      dragOffset: dragOffset,
      onVerticalDragUpdate: handleDragUpdate,
      onVerticalDragEnd: handleDragEnd,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '自动翻页速度',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _ReaderSettingSlider(
              value: draftSpeed,
              min: readerAutoPageSpeedMin,
              max: readerAutoPageSpeedMax,
              divisions: 25,
              leading: Text(
                '慢',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Text(
                '快',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              thumbText: draftSpeed.toStringAsFixed(1),
              onChanged: (value) => setState(() => draftSpeed = value),
              onChangeEnd: widget.onSpeedChanged,
            ),
          ],
        ),
      ),
    );
  }
}
