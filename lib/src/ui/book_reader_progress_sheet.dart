part of '../book_reader_page.dart';

List<_ReaderMetricValuePart> _readerDurationParts(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return [
      _ReaderMetricValuePart(hours.toString()),
      const _ReaderMetricValuePart('小时 ', compact: true),
      _ReaderMetricValuePart(minutes.toString()),
      const _ReaderMetricValuePart('分钟', compact: true),
    ];
  }
  return [
    _ReaderMetricValuePart(minutes.toString()),
    const _ReaderMetricValuePart('分钟', compact: true),
  ];
}

String _remainingTimeText(double progress, Duration elapsed) {
  if (progress <= .01 || elapsed.inSeconds < 30) {
    return '约 -- 小时后读完';
  }
  final totalSeconds = elapsed.inSeconds / progress;
  final remaining = Duration(
    seconds: (totalSeconds - elapsed.inSeconds).round(),
  );
  if (remaining.inHours > 0) {
    return '约 ${remaining.inHours} 小时后读完';
  }
  return '约 ${remaining.inMinutes.clamp(1, 59)} 分钟后读完';
}

class _ReaderProgressSheet extends StatefulWidget {
  const _ReaderProgressSheet({
    required this.visible,
    required this.bottomOffset,
    required this.settings,
    required this.progress,
    required this.readingDuration,
    required this.noteCount,
    required this.onClose,
    required this.onProgressChanged,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.autoPaging,
    required this.onToggleAutoPaging,
    required this.onShowReadingDetails,
  });

  final bool visible;
  final double bottomOffset;
  final ReaderSettings settings;
  final double progress;
  final Duration readingDuration;
  final int noteCount;
  final VoidCallback onClose;
  final ValueChanged<double> onProgressChanged;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final bool autoPaging;
  final VoidCallback? onToggleAutoPaging;
  final VoidCallback onShowReadingDetails;

  @override
  State<_ReaderProgressSheet> createState() => _ReaderProgressSheetState();
}

class _ReaderProgressSheetState extends State<_ReaderProgressSheet>
    with _ReaderSheetDragMixin<_ReaderProgressSheet> {
  late double draftProgress;

  @override
  bool get visible => widget.visible;

  @override
  VoidCallback get onClose => widget.onClose;

  @override
  bool get draggable => false; // Disable drag for progress sheet

  @override
  void initState() {
    super.initState();
    draftProgress = widget.progress;
  }

  @override
  void didUpdateWidget(covariant _ReaderProgressSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible || oldWidget.progress != widget.progress) {
      draftProgress = widget.progress;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ReaderBottomSheetFrame(
      visible: widget.visible,
      bottomOffset: widget.bottomOffset,
      height: _readerFixedSheetHeight(context),
      settings: widget.settings,
      dragOffset: dragOffset,
      onVerticalDragUpdate: handleDragUpdate,
      onVerticalDragEnd: handleDragEnd,
      draggable: draggable,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _ReaderProgressMetric(
                          value: _ReaderMetricValue(
                            parts: [
                              _ReaderMetricValuePart(
                                (widget.progress * 100).round().toString(),
                              ),
                              const _ReaderMetricValuePart('%', compact: true),
                            ],
                          ),
                          label: _remainingTimeText(
                            widget.progress,
                            widget.readingDuration,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _ReaderProgressMetric(
                          value: _ReaderMetricValue(
                            parts: _readerDurationParts(widget.readingDuration),
                          ),
                          label: '阅读时长',
                        ),
                      ),
                      Expanded(
                        child: _ReaderProgressMetric(
                          value: _ReaderMetricValue(
                            parts: [
                              _ReaderMetricValuePart(
                                widget.noteCount.toString(),
                              ),
                              const _ReaderMetricValuePart('条', compact: true),
                            ],
                          ),
                          label: '笔记数量',
                        ),
                      ),
                    ],
                  ),
                  _ReaderSettingSlider(
                    value: draftProgress,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    leading: Icon(
                      LucideIcons.chevronLeft,
                      color: widget.onPreviousChapter == null
                          ? Theme.of(context).disabledColor
                          : null,
                      size: 30,
                    ),
                    trailing: Icon(
                      LucideIcons.chevronRight,
                      color: widget.onNextChapter == null
                          ? Theme.of(context).disabledColor
                          : null,
                      size: 30,
                    ),
                    thumbText: '${(draftProgress * 100).round()}%',
                    onLeadingTap: widget.onPreviousChapter,
                    onTrailingTap: widget.onNextChapter,
                    onChanged: (value) => setState(() => draftProgress = value),
                    onChangeEnd: widget.onProgressChanged,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _ReaderModeButton(
                          label: '阅读明细',
                          onPressed: widget.onShowReadingDetails,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (widget.onToggleAutoPaging != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ReaderModeButton(
                            label: widget.autoPaging ? '关闭自动翻页' : '开启自动翻页',
                            onPressed: widget.onToggleAutoPaging!,
                          ),
                        ),
                      ],
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

class _ReaderProgressMetric extends StatelessWidget {
  const _ReaderProgressMetric({required this.value, required this.label});

  final Widget value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 54,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          value,
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderMetricValuePart {
  const _ReaderMetricValuePart(this.text, {this.compact = false});

  final String text;
  final bool compact;
}

class _ReaderMetricValue extends StatelessWidget {
  const _ReaderMetricValue({required this.parts});

  final List<_ReaderMetricValuePart> parts;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: colors.onSurface,
      fontSize: 22,
      fontWeight: FontWeight.w800,
      height: 1,
    );
    final compactStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      height: 1,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (final part in parts)
            TextSpan(
              text: part.text,
              style: part.compact ? compactStyle : baseStyle,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
  }
}

class _ReaderDetailsOverlay extends StatelessWidget {
  const _ReaderDetailsOverlay({required this.settings, required this.onClose});

  final ReaderSettings settings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _readerSheetColorScheme(theme.colorScheme, settings);
    return Positioned.fill(
      child: Theme(
        data: theme.copyWith(colorScheme: colors),
        child: Material(
          color: colors.surface,
          child: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        '阅读明细',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Positioned(
                        right: 8,
                        child: IconButton(
                          tooltip: '关闭',
                          onPressed: onClose,
                          icon: const Icon(LucideIcons.x),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '阅读明细',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
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
