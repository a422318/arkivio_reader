part of '../book_reader_page.dart';

class _ReaderNoteOverlay extends StatefulWidget {
  const _ReaderNoteOverlay({
    required this.settings,
    required this.referenceText,
    required this.initialText,
    required this.submitting,
    required this.onSubmit,
    required this.onClose,
  });

  final ReaderSettings settings;
  final String referenceText;
  final String initialText;
  final bool submitting;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClose;

  @override
  State<_ReaderNoteOverlay> createState() => _ReaderNoteOverlayState();
}

class _ReaderNoteOverlayState extends State<_ReaderNoteOverlay> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _text = widget.initialText;
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _readerSheetColorScheme(
      Theme.of(context).colorScheme,
      widget.settings,
    );
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final canSubmit = _text.trim().isNotEmpty && !widget.submitting;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth > 840
                    ? 760.0
                    : constraints.maxWidth;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onClose,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: .24),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Theme(
                          data: Theme.of(context).copyWith(colorScheme: colors),
                          child: _ReaderNotePanel(
                            colors: colors,
                            controller: _controller,
                            focusNode: _focusNode,
                            referenceText: widget.referenceText,
                            submitting: widget.submitting,
                            canSubmit: canSubmit,
                            onChanged: (value) => setState(() => _text = value),
                            onSubmit: () => widget.onSubmit(_text),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderNotePanel extends StatelessWidget {
  const _ReaderNotePanel({
    required this.colors,
    required this.controller,
    required this.focusNode,
    required this.referenceText,
    required this.submitting,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
  });

  final ColorScheme colors;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String referenceText;
  final bool submitting;
  final bool canSubmit;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final panelColor = Color.alphaBlend(
      colors.onSurface.withValues(alpha: .055),
      colors.surface,
    );
    return Material(
      color: panelColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Icon(
                    LucideIcons.notebookPen,
                    color: colors.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    onChanged: onChanged,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    cursorColor: colors.primary,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '写下这一刻的想法...',
                      hintStyle: TextStyle(color: colors.onSurfaceVariant),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: canSubmit ? onSubmit : null,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primary,
                    disabledForegroundColor: colors.onSurfaceVariant.withValues(
                      alpha: .48,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(48, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: submitting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.primary,
                          ),
                        )
                      : const Text(
                          '发表',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: '文字引用：'),
                  TextSpan(
                    text: referenceText,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
