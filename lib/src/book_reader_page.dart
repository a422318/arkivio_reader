import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_all/webview_all.dart';

import 'book_file_utils.dart';
import 'book_reader_asset_server.dart';
import 'reader_api.dart';

part 'ui/book_reader_auto_page_sheet.dart';
part 'ui/book_reader_annotations_sheet.dart';
part 'ui/book_reader_background_sheet.dart';
part 'ui/book_reader_controls.dart';
part 'book_reader_models.dart';
part 'ui/book_reader_note_overlay.dart';
part 'ui/book_reader_progress_sheet.dart';
part 'ui/book_reader_search_overlay.dart';
part 'ui/book_reader_settings_sheet.dart';
part 'ui/book_reader_sheet_common.dart';
part 'ui/book_reader_toc_sheet.dart';

class _TranslationBatch {
  const _TranslationBatch({required this.paragraphs, required this.startIndex});

  final List<_ReaderParagraph> paragraphs;
  final int startIndex;
}

class _ParagraphTranslation {
  const _ParagraphTranslation({
    required this.original,
    required this.translation,
    required this.index,
  });

  final String original;
  final String translation;
  final int index;

  Map<String, dynamic> toJson() => {
    'original': original,
    'translation': translation,
    'index': index,
  };
}

/// A full-screen ebook reader widget backed by a local WebView renderer.
///
/// [options.settings.initial] are applied before persisted settings are loaded.
/// When [options.settings.store] returns saved settings, those saved settings
/// replace the initial values.
class BookReaderPage extends StatefulWidget {
  const BookReaderPage({
    super.key,
    required this.book,
    this.progressDelegate = const ReaderProgressDelegate.none(),
    this.annotationDelegate = const ReaderAnnotationDelegate.none(),
    this.controller,
    this.options = const ReaderOptions(),
    this.bookBytesLoader,
    this.translationDelegate,
    this.onBack,
  });

  final ReaderBookItem book;

  /// Optional bridge for reading progress persistence.
  ///
  /// Defaults to a no-op delegate, so simple integrations can open books
  /// without implementing storage.
  final ReaderProgressDelegate progressDelegate;

  /// Optional bridge for highlights and notes.
  ///
  /// Defaults to a no-op delegate. Disable annotation UI with
  /// [ReaderFeatureOptions.annotations] and [ReaderFeatureOptions.notes] when
  /// the app does not expose these features.
  final ReaderAnnotationDelegate annotationDelegate;

  /// Optional controller for driving reader navigation and settings externally.
  final ReaderController? controller;

  /// Grouped reader configuration for settings, chrome, behavior, and diagnostics.
  final ReaderOptions options;

  /// Optional byte loader for applications that do not expose books as files.
  ///
  /// When omitted, the reader loads bytes from [book.filePath].
  final ReaderBookBytesLoader? bookBytesLoader;

  /// Optional translation provider for selected text and chapter translation.
  final ReaderTranslationDelegate? translationDelegate;

  /// Called when the built-in back button is pressed.
  final VoidCallback? onBack;

  @override
  State<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends State<BookReaderPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final WebViewController _controller;
  late ReaderController _readerController;
  late bool _ownsReaderController;
  bool _loading = true;
  String? _error;
  String? _pendingLocatorJson;
  bool _bookSent = false;
  int _loadToken = 0;
  Timer? _readyTimer;
  Timer? _bookOpenTimer;
  BookReaderAssetServer? _assetServer;
  Ticker? _autoPageTicker;
  Duration _autoPageElapsed = Duration.zero;
  Duration _autoPageLastTick = Duration.zero;
  double _autoPageProgress = 0;
  bool _autoPageTurning = false;
  bool _autoPagePaused = false;
  bool _autoPageSettingsVisible = false;
  OverlayEntry? _readingDetailsEntry;
  bool _controlsVisible = false;
  bool _tocVisible = false;
  bool _progressVisible = false;
  bool _backgroundVisible = false;
  bool _settingsVisible = false;
  bool _autoPaging = false;
  _ReaderPanel _selectedPanel = _ReaderPanel.toc;
  ReaderSettings _readerSettings = const ReaderSettings();
  final DateTime _readingStartedAt = DateTime.now();
  ReaderBookMetadata? _bookMetadata;
  List<_ReaderTocItem> _tocItems = const [];
  String? _chapterHref;
  double _readingProgress = 0;
  _ReaderTextSelection? _textSelection;
  bool _textSelectionDragging = false;
  bool _textSelectionLongPressMoved = false;
  Offset? _textSelectionLongPressStart;
  int _textSelectionRequestToken = 0;
  _ReaderActiveHighlight? _activeHighlight;
  _ReaderHighlightStyle _highlightStyle = _ReaderHighlightStyle.highlight;
  _ReaderHighlightColorOption _highlightColor = _readerHighlightColors.first;
  bool _searchVisible = false;
  bool _searchLoading = false;
  String _searchQuery = '';
  List<_ReaderSearchChapter> _searchChapters = const [];
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  bool _webSearchActive = false;
  bool _noteComposerVisible = false;
  bool _noteSubmitting = false;
  _ReaderSelectionAnnotation? _noteSelection;
  bool _noteEditingExisting = false;
  bool _annotationsVisible = false;
  bool _annotationsLoading = false;
  List<_ReaderAnnotationItem> _readerAnnotations = const [];
  int _annotationsLoadToken = 0;
  int _translationRequestToken = 0;
  _ReaderTranslationStatus _translationStatus = _ReaderTranslationStatus.idle;
  String _translationText = '';
  int _chapterTranslationRequestToken = 0;
  _ReaderTranslationStatus _chapterTranslationStatus =
      _ReaderTranslationStatus.idle;
  String? _chapterTranslationKey;

  String get _contentId => widget.book.id;
  String get _annotationPageUrl => 'book:$_contentId';
  String get _annotationPageTitle =>
      widget.book.title ?? widget.book.fileName ?? '书籍划线';
  ReaderFeatureOptions get _features => widget.options.features;
  bool get _hasAnnotationDelegate =>
      widget.annotationDelegate is! NoopReaderAnnotationDelegate;
  bool get _searchEnabled => _features.search;
  bool get _annotationsEnabled =>
      _features.annotations && _hasAnnotationDelegate;
  bool get _notesEnabled => _features.notes && _hasAnnotationDelegate;
  bool get _annotationPanelEnabled => _annotationsEnabled || _notesEnabled;
  bool get _translationEnabled =>
      _features.translation && widget.translationDelegate != null;
  bool get _autoPagingEnabled => _features.autoPaging;
  bool get _backgroundImagesEnabled => _features.backgroundImages;

  ReaderAppearanceOptions get _effectiveAppearanceOptions {
    final appearance = widget.options.settings.appearance;
    if (_backgroundImagesEnabled) {
      return appearance;
    }
    return ReaderAppearanceOptions(
      backgroundColors: appearance.backgroundColors,
      backgroundImages: const [],
      backgroundImageFit: appearance.backgroundImageFit,
    );
  }

  ReaderSettings _settingsForEnabledFeatures(ReaderSettings settings) {
    if (_backgroundImagesEnabled || settings.backgroundImage.isEmpty) {
      return settings;
    }
    return settings.copyWith(backgroundImage: readerDefaultBackgroundImage);
  }

  bool _panelEnabled(_ReaderPanel panel) {
    return switch (panel) {
      _ReaderPanel.toc => true,
      _ReaderPanel.annotations => _annotationPanelEnabled,
      _ReaderPanel.progress => true,
      _ReaderPanel.background => true,
      _ReaderPanel.font => true,
    };
  }

  List<_ReaderPanel> get _enabledPanels => [
    for (final panel in _ReaderPanel.values)
      if (_panelEnabled(panel)) panel,
  ];

  List<_ReaderTextAction> get _enabledTextActions => [
    for (final action in _readerTextActions)
      if (switch (action.kind) {
        _ReaderTextActionKind.highlight => _annotationsEnabled,
        _ReaderTextActionKind.note => _notesEnabled,
        _ReaderTextActionKind.search => _searchEnabled,
        _ReaderTextActionKind.translate => _translationEnabled,
        _ReaderTextActionKind.copy || _ReaderTextActionKind.share => true,
      })
        action,
  ];

  ReaderPanel? get _openReaderPanel {
    if (_tocVisible) {
      return ReaderPanel.toc;
    }
    if (_annotationsVisible && _annotationPanelEnabled) {
      return ReaderPanel.annotations;
    }
    if (_progressVisible) {
      return ReaderPanel.progress;
    }
    if (_backgroundVisible) {
      return ReaderPanel.background;
    }
    if (_settingsVisible) {
      return ReaderPanel.font;
    }
    return null;
  }

  void _bindReaderController() {
    _readerController.bind(
      nextPage: () => _turnPage('next'),
      previousPage: () => _turnPage('prev'),
      goToHref: (href) =>
          _goToTocItem(_ReaderTocItem(label: href, href: href, depth: 0)),
      goToFraction: _goToFraction,
      search: (query) async => _openReaderSearch(query),
      clearSearch: _clearReaderSearchResults,
      applySettings: _applyReaderSettings,
      toggleControls: _toggleControls,
      dismissControls: _dismissControls,
      selectPanel: (panel) => _selectPanel(_ReaderPanel.fromPublic(panel)),
      toggleAutoPaging: () async => _toggleAutoPaging(),
      toggleChapterTranslation: _toggleChapterTranslation,
    );
  }

  void _attachReaderController(ReaderController? controller) {
    _readerController = controller ?? ReaderController();
    _ownsReaderController = controller == null;
    _bindReaderController();
  }

  void _publishReaderState() {
    _readerController.setValue(
      ReaderState(
        loading: _loading,
        error: _error,
        controlsVisible: _controlsVisible,
        selectedPanel: _selectedPanel.toPublic(),
        openPanel: _openReaderPanel,
        progress: _readingProgress,
        chapterHref: _chapterHref,
        bookMetadata: _bookMetadata,
        tocItems: [
          for (final item in _tocItems)
            ReaderTocEntry(
              label: item.label,
              href: item.href,
              depth: item.depth,
            ),
        ],
        selectedTocIndex: _currentTocIndex(),
        annotations: [
          for (final item in _readerAnnotations)
            if ((item.isNote && _notesEnabled) ||
                (!item.isNote && _annotationsEnabled))
              ReaderAnnotationEntry(
                locatorValue: item.locatorValue,
                text: item.text,
                note: item.note,
                style: item.style,
                colorHex: item.colorHex,
                chapterLabel: item.chapterLabel,
                updatedAt: item.updatedAt,
              ),
        ],
        annotationsLoading: _annotationsLoading,
        autoPaging: _autoPaging,
        autoPageProgress: _autoPageProgress,
        chapterTranslationStatus: _chapterTranslationStatus.toPublic(),
        readingDuration: _readingDuration,
        noteCount: _readerNoteCount,
        settings: _readerSettings,
      ),
    );
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _publishReaderState();
  }

  Widget _defaultChrome(BuildContext context, ReaderChromeContext reader) {
    final builders = widget.options.chrome.builders;
    return _defaultChromeBody(context, reader, builders);
  }

  Widget _defaultChromeBody(
    BuildContext context,
    ReaderChromeContext reader,
    ReaderChromeBuilders builders,
  ) {
    final state = reader.state;
    final readerColors = _readerSheetColorScheme(
      Theme.of(context).colorScheme,
      state.settings,
    );
    final selectionHandleColor = _readerSelectionAccentColor(
      state.settings.backgroundColor,
    );
    final selectionHandleBorderColor = readerColors.surface;
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        _ReaderTapZones(
          onLongPress: _showTextActionMenu,
          onLongPressMove: _extendTextSelection,
          onLongPressEnd: _finishLongPressTextSelection,
        ),
        _AutoPageProgressBar(
          visible: state.autoPaging && !_autoScrollMode,
          progress: state.autoPageProgress,
          colors: readerColors,
        ),
        _AutoPageSettingsButton(
          visible: state.autoPaging && !_autoPageSettingsVisible,
          leftInset: state.settings.margin,
          colors: readerColors,
          onPressed: _openAutoPageSettings,
        ),
        builders.chromeBuilder?.call(context, reader) ??
            _ReaderControlsOverlay(
              visible: state.controlsVisible,
              tocVisible: state.openPanel == ReaderPanel.toc,
              annotationsVisible: state.openPanel == ReaderPanel.annotations,
              progressVisible: state.openPanel == ReaderPanel.progress,
              backgroundVisible: state.openPanel == ReaderPanel.background,
              settingsVisible: state.openPanel == ReaderPanel.font,
              selectedPanel: _selectedPanel,
              enabledPanels: _enabledPanels,
              settings: state.settings,
              appearanceOptions: _effectiveAppearanceOptions,
              progress: state.progress,
              readingDuration: state.readingDuration,
              noteCount: state.noteCount,
              tocItems: _tocItems,
              annotations: _readerAnnotations,
              annotationsLoading: _annotationsLoading,
              chapterTranslationStatus: _chapterTranslationStatus,
              selectedTocIndex: _currentTocIndex(),
              readerContext: reader,
              chromeBuilders: builders,
              onBack: _goBack,
              chapterTranslationEnabled: _translationEnabled,
              onToggleChapterTranslation: () =>
                  unawaited(_toggleChapterTranslation()),
              onSelectPanel: _selectPanel,
              onDismiss: _dismissControls,
              onCloseToc: () => setState(() => _tocVisible = false),
              onCloseAnnotations: _closeReaderAnnotations,
              onCloseProgress: () => setState(() => _progressVisible = false),
              onCloseBackground: () =>
                  setState(() => _backgroundVisible = false),
              onCloseSettings: () => setState(() => _settingsVisible = false),
              onTocItemSelected: (item) => unawaited(_goToTocItem(item)),
              onAnnotationSelected: (item) =>
                  unawaited(_goToReaderAnnotation(item)),
              onProgressChanged: (fraction) =>
                  unawaited(_goToFraction(fraction)),
              onPreviousChapter: _adjacentChapter(-1) == null
                  ? null
                  : () => _goToAdjacentChapter(-1),
              onNextChapter: _adjacentChapter(1) == null
                  ? null
                  : () => _goToAdjacentChapter(1),
              autoPaging: state.autoPaging,
              onToggleAutoPaging: _autoPagingEnabled ? _toggleAutoPaging : null,
              onShowReadingDetails: _showReadingDetails,
              onSettingsChanged: (settings) =>
                  unawaited(_applyReaderSettings(settings)),
            ),
        _AutoPageSettingsSheet(
          visible: _autoPagingEnabled && _autoPageSettingsVisible,
          settings: state.settings,
          onClose: _closeAutoPageSettings,
          onSpeedChanged: _onAutoPageSpeedChanged,
        ),
        if (_textSelection != null) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _noteComposerVisible
                  ? _closeReaderNoteComposer
                  : _hideTextActionMenu,
              onVerticalDragStart: (_) => _noteComposerVisible
                  ? _closeReaderNoteComposer()
                  : _hideTextActionMenu(),
              onHorizontalDragStart: (_) => _noteComposerVisible
                  ? _closeReaderNoteComposer()
                  : _hideTextActionMenu(),
            ),
          ),
          _ReaderSelectionHandle(
            position: _textSelection!.startHandle,
            color: selectionHandleColor,
            borderColor: selectionHandleBorderColor,
            onDragStart: (_) => _beginTextSelectionDrag('start'),
            onDragUpdate: (position) =>
                unawaited(_updateTextSelectionHandle('start', position)),
            onDragEnd: (position) =>
                unawaited(_finishTextSelectionDrag('start', position)),
          ),
          _ReaderSelectionHandle(
            position: _textSelection!.endHandle,
            color: selectionHandleColor,
            borderColor: selectionHandleBorderColor,
            onDragStart: (_) => _beginTextSelectionDrag('end'),
            onDragUpdate: (position) =>
                unawaited(_updateTextSelectionHandle('end', position)),
            onDragEnd: (position) =>
                unawaited(_finishTextSelectionDrag('end', position)),
          ),
          if (!_textSelectionDragging && !_noteComposerVisible)
            _ReaderTextActionMenu(
              anchor: _textSelection!.menuAnchor,
              fallbackAnchor: _textSelection!.fallbackMenuAnchor,
              lineCount: _textSelection!.lineCount,
              actions: _enabledTextActions,
              onSelected: _handleTextActionSelected,
              highlightMode: _activeHighlight != null,
              highlightStyle: _highlightStyle,
              highlightColor: _highlightColor,
              translationStatus: _translationStatus,
              translationText: _translationText,
              onHighlightStyleChanged: (style) =>
                  unawaited(_updateTextHighlight(style: style)),
              onHighlightColorChanged: (color) =>
                  unawaited(_updateTextHighlight(color: color)),
              onDeleteHighlight: () => unawaited(_deleteTextHighlight()),
            ),
        ],
        if (_searchVisible)
          _ReaderSearchOverlay(
            settings: state.settings,
            query: _searchQuery,
            loading: _searchLoading,
            chapters: _searchChapters,
            onQueryChanged: _handleSearchQueryChanged,
            onClear: () => _handleSearchQueryChanged(''),
            onResultSelected: (item) => unawaited(_goToSearchResult(item)),
            onClose: _closeReaderSearch,
          ),
        if (_noteComposerVisible && _noteSelection != null)
          _ReaderNoteOverlay(
            settings: state.settings,
            referenceText: _noteSelection!.text,
            initialText: _noteSelection!.note,
            submitting: _noteSubmitting,
            onSubmit: (note) => unawaited(_submitReaderNote(note)),
            onClose: _closeReaderNoteComposer,
          ),
        if (_loading) _buildLoadingOverlay(context),
        if (_error != null) _buildErrorOverlay(context, _error!),
      ],
    );
  }

  Widget _buildLoadingOverlay(BuildContext context) {
    return widget.options.chrome.loadingBuilder?.call(context) ??
        const Center(child: CircularProgressIndicator());
  }

  Widget _buildErrorOverlay(BuildContext context, String error) {
    final data = ReaderErrorViewData(
      message: error,
      copyDiagnostics: _copyDiagnostics,
    );
    return widget.options.chrome.errorBuilder?.call(context, data) ??
        _ReaderErrorOverlay(error: error, onCopyDiagnostics: _copyDiagnostics);
  }

  @override
  void initState() {
    super.initState();
    _attachReaderController(widget.controller);
    _readerSettings = _settingsForEnabledFeatures(
      widget.options.settings.initial,
    );
    _publishReaderState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_applyReaderSystemUi(false));
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setOnConsoleMessage((message) {
        if (widget.options.diagnostics.enableWebViewConsoleLog) {
          debugPrint('[WebView ${message.level.name}] ${message.message}');
        }
        if (message.level == JavaScriptLogLevel.error && mounted) {
          unawaited(
            _reportReaderError(
              message.message,
              source: 'bookReader.console',
              extra: {'level': message.level.name, 'message': message.message},
            ),
          );
        }
      })
      ..addJavaScriptChannel(
        'MistdeerReader',
        onMessageReceived: (message) =>
            unawaited(_handleReaderMessage(message.message)),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              unawaited(
                _reportReaderError(
                  error.description,
                  source: 'bookReader.webResourceError',
                  extra: {
                    'errorCode': error.errorCode,
                    'errorType': error.errorType?.name,
                    'isForMainFrame': error.isForMainFrame,
                    'url': error.url,
                  },
                ),
              );
              setState(() => _error = error.description);
            }
          },
        ),
      );
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant BookReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _readerController.unbind();
      if (_ownsReaderController) {
        _readerController.dispose();
      }
      _attachReaderController(widget.controller);
      _publishReaderState();
    } else {
      _bindReaderController();
    }

    final bookChanged =
        oldWidget.book.id != widget.book.id ||
        oldWidget.book.filePath != widget.book.filePath ||
        oldWidget.book.format != widget.book.format ||
        oldWidget.book.fileName != widget.book.fileName ||
        oldWidget.book.title != widget.book.title;
    final sourceChanged =
        !identical(oldWidget.progressDelegate, widget.progressDelegate) ||
        !identical(oldWidget.annotationDelegate, widget.annotationDelegate) ||
        !identical(oldWidget.bookBytesLoader, widget.bookBytesLoader) ||
        !identical(
          oldWidget.options.settings.store,
          widget.options.settings.store,
        ) ||
        oldWidget.options.settings.initial != widget.options.settings.initial;
    if (bookChanged || sourceChanged) {
      unawaited(_reloadReader());
      return;
    }

    _enforceFeatureAvailability();
    if (!identical(
      oldWidget.options.settings.appearance,
      widget.options.settings.appearance,
    )) {
      unawaited(_sendReaderSettingsToWebView(_readerSettings));
    }
  }

  Future<void> _reloadReader() async {
    _loadToken += 1;
    _readyTimer?.cancel();
    _bookOpenTimer?.cancel();
    _searchDebounce?.cancel();
    _autoPageTicker?.dispose();
    _autoPageTicker = null;
    if (_autoScrollMode) {
      _stopAutoScroll();
    }
    final server = _assetServer;
    _assetServer = null;
    unawaited(server?.close());
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _pendingLocatorJson = null;
        _bookSent = false;
        _autoPageElapsed = Duration.zero;
        _autoPageLastTick = Duration.zero;
        _autoPageProgress = 0;
        _autoPageTurning = false;
        _autoPagePaused = false;
        _autoPageSettingsVisible = false;
        _controlsVisible = false;
        _tocVisible = false;
        _annotationsVisible = false;
        _progressVisible = false;
        _backgroundVisible = false;
        _settingsVisible = false;
        _autoPaging = false;
        _bookMetadata = null;
        _tocItems = const [];
        _chapterHref = null;
        _readingProgress = 0;
        _textSelection = null;
        _textSelectionDragging = false;
        _textSelectionLongPressMoved = false;
        _textSelectionLongPressStart = null;
        _activeHighlight = null;
        _searchVisible = false;
        _searchLoading = false;
        _searchQuery = '';
        _searchChapters = const [];
        _webSearchActive = false;
        _noteComposerVisible = false;
        _noteSubmitting = false;
        _noteSelection = null;
        _noteEditingExisting = false;
        _annotationsLoading = false;
        _readerAnnotations = const [];
        _translationStatus = _ReaderTranslationStatus.idle;
        _translationText = '';
        _chapterTranslationStatus = _ReaderTranslationStatus.idle;
        _chapterTranslationKey = null;
        _readerSettings = _settingsForEnabledFeatures(
          widget.options.settings.initial,
        );
      });
    } else {
      _loading = true;
      _error = null;
      _pendingLocatorJson = null;
      _bookSent = false;
      _bookMetadata = null;
      _readerSettings = _settingsForEnabledFeatures(
        widget.options.settings.initial,
      );
    }
    await _applyReaderSystemUi(false);
    await _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readyTimer?.cancel();
    _bookOpenTimer?.cancel();
    _searchDebounce?.cancel();
    _autoPageTicker?.dispose();
    if (_autoPaging && _autoScrollMode) {
      _stopAutoScroll();
    }
    _readingDetailsEntry?.remove();
    _readerController.unbind();
    if (_ownsReaderController) {
      _readerController.dispose();
    }
    unawaited(_assetServer?.close());
    // Restore system bars to visible when exiting reader
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      ),
    );
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // When the user swipes from the edge to reveal system bars temporarily,
    // re-hide them after a delay if controls are still hidden
    if (!_controlsVisible && mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_controlsVisible && mounted) {
          unawaited(_applyReaderSystemUi(false));
        }
      });
    }
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    try {
      await _restoreReaderSettings();
      if (!mounted || token != _loadToken) {
        return;
      }
      final progress = await widget.progressDelegate.loadReadingProgress(
        _contentId,
      );
      if (!mounted || token != _loadToken) {
        return;
      }
      _pendingLocatorJson = progress?.locatorJson;
      final server = await BookReaderAssetServer.start();
      if (!mounted || token != _loadToken) {
        unawaited(server.close());
        return;
      }
      _assetServer = server;
      await _controller.loadRequest(server.readerUri);
      if (!mounted || token != _loadToken) {
        return;
      }
      _startReadyTimer();
    } on Object catch (error, stackTrace) {
      await _reportReaderError(
        error,
        stackTrace: stackTrace,
        source: 'bookReader.load',
      );
      if (mounted && token == _loadToken) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && token == _loadToken) {
        setState(() => _loading = false);
      }
    }
  }

  void _startReadyTimer() {
    _readyTimer?.cancel();
    final timeout = widget.options.behavior.readyTimeout;
    _readyTimer = Timer(widget.options.behavior.readyTimeout, () {
      if (mounted && !_bookSent) {
        unawaited(
          _reportReaderError(
            'Reader bridge did not become ready within '
            '${timeout.inSeconds} seconds.',
            source: 'bookReader.readyTimeout',
          ),
        );
        setState(() {
          _loading = false;
          _error = '阅读器加载失败，请检查 foliate-js 资源是否已打包。';
        });
      }
    });
  }

  void _startBookOpenTimer() {
    _bookOpenTimer?.cancel();
    final token = _loadToken;
    final timeout = widget.options.behavior.bookOpenTimeout;
    _bookOpenTimer = Timer(timeout, () {
      if (!mounted || token != _loadToken || !_bookSent) {
        return;
      }
      final title = widget.book.title ?? widget.book.fileName ?? widget.book.id;
      unawaited(
        _reportReaderError(
          'Book did not finish opening within ${timeout.inSeconds} seconds.',
          source: 'bookReader.openTimeout',
          extra: {'bookTitle': title},
        ),
      );
      setState(() {
        _loading = false;
        _error = '打开书籍超时，请重试。MOBI、AZW3 和 PDF 首次解析可能需要更长时间。';
      });
    });
  }

  Future<void> _openBookInReader() async {
    if (_bookSent) {
      return;
    }
    _bookSent = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final payload = jsonEncode({
      'id': _contentId,
      'title': widget.book.title ?? widget.book.fileName,
      'format': widget.book.format,
      'fileName': widget.book.fileName,
      'mimeType': readerBookMimeType(
        widget.book.format,
        fileName: widget.book.fileName,
        filePath: widget.book.filePath,
      ),
      'locatorJson': _pendingLocatorJson,
    });
    final base64Content = base64Encode(await _loadBookBytes());
    await _controller.runJavaScript(
      'window.MistdeerReaderBridge?.beginBook($payload);',
    );
    final chunkSize = math.max(
      64 * 1024,
      widget.options.behavior.bookTransferChunkSize,
    );
    for (var offset = 0; offset < base64Content.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, base64Content.length);
      final chunk = jsonEncode(base64Content.substring(offset, end));
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.appendBookChunk($chunk);',
      );
    }
    _startBookOpenTimer();
    await _controller.runJavaScript(
      'window.MistdeerReaderBridge?.finishBook();',
    );
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<List<int>> _loadBookBytes() async {
    final loader = widget.bookBytesLoader;
    if (loader != null) {
      return loader(widget.book);
    }
    final filePath = widget.book.filePath;
    if (filePath == null || filePath.isEmpty) {
      throw StateError('此设备缺少本地书籍文件，请重新导入同一本书。');
    }
    final file = File(filePath);
    if (!file.existsSync()) {
      throw StateError('本地书籍文件不存在，请重新导入同一本书。');
    }
    return file.readAsBytes();
  }

  ReaderBookMetadata? _bookMetadataFromMessage(Object? value) {
    if (value is! Map) {
      return null;
    }
    return ReaderBookMetadata.fromMap({
      for (final entry in value.entries) entry.key.toString(): entry.value,
    });
  }

  Future<void> _handleReaderMessage(String message) async {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return;
      }
      final type = decoded['type']?.toString();
      if (type == 'ready') {
        _readyTimer?.cancel();
        await _openBookInReader();
        return;
      }
      if (type == 'loaded') {
        _bookOpenTimer?.cancel();
        final toc = decoded['toc'];
        final metadata = _bookMetadataFromMessage(decoded['metadata']);
        if (mounted) {
          setState(() {
            _loading = false;
            _error = null;
            _bookMetadata = metadata;
            _tocItems = _ReaderTocItem.parseList(toc);
            _textSelection = null;
            _textSelectionDragging = false;
            _textSelectionLongPressMoved = false;
            _textSelectionLongPressStart = null;
            _activeHighlight = null;
            _noteComposerVisible = false;
            _noteSubmitting = false;
            _noteSelection = null;
            _noteEditingExisting = false;
            _annotationsVisible = false;
            _annotationsLoading = false;
            _readerAnnotations = const [];
            _translationStatus = _ReaderTranslationStatus.idle;
            _translationText = '';
            _chapterTranslationRequestToken += 1;
            _chapterTranslationStatus = _ReaderTranslationStatus.idle;
            _chapterTranslationKey = null;
            _webSearchActive = false;
          });
        }
        unawaited(_sendReaderSettingsToWebView(_readerSettings));
        unawaited(_restoreTextHighlights());
        return;
      }
      if (type == 'selectionChanged') {
        final selectionToken = decoded['token'];
        if (selectionToken is num &&
            selectionToken.toInt() != _textSelectionRequestToken) {
          return;
        }
        final selection = _ReaderTextSelection.fromMessage(decoded);
        if (selection != null && mounted) {
          _translationRequestToken += 1;
          setState(() {
            _textSelection = selection;
            _activeHighlight = null;
            _translationStatus = _ReaderTranslationStatus.idle;
            _translationText = '';
          });
        }
        return;
      }
      if (type == 'annotationSelected') {
        final annotation = _ReaderSelectedAnnotation.fromMessage(decoded);
        if (annotation != null && mounted) {
          _handleReaderAnnotationSelected(annotation);
        }
        return;
      }
      if (type == 'readerTap') {
        _handleReaderTap(decoded);
        return;
      }
      if (type == 'selectionCleared') {
        if (mounted) {
          _translationRequestToken += 1;
          setState(() {
            _textSelection = null;
            _textSelectionDragging = false;
            _textSelectionLongPressMoved = false;
            _textSelectionLongPressStart = null;
            _activeHighlight = null;
            _noteComposerVisible = false;
            _noteSubmitting = false;
            _noteSelection = null;
            _noteEditingExisting = false;
            _translationStatus = _ReaderTranslationStatus.idle;
            _translationText = '';
          });
        }
        return;
      }
      if (type == 'searchChapter') {
        final requestId = (decoded['requestId'] as num?)?.toInt();
        if (requestId != _searchRequestId || !_searchVisible) {
          return;
        }
        final chapter = _ReaderSearchChapter.fromMessage(decoded['chapter']);
        if (chapter == null) {
          return;
        }
        if (mounted) {
          setState(() {
            _searchLoading = true;
            _searchChapters = [..._searchChapters, chapter];
          });
        }
        return;
      }
      if (type == 'searchDone' || type == 'searchResults') {
        final requestId = (decoded['requestId'] as num?)?.toInt();
        if (requestId != _searchRequestId || !_searchVisible) {
          return;
        }
        if (mounted) {
          setState(() {
            _searchLoading = false;
            _webSearchActive = false;
            if (type == 'searchResults') {
              _searchChapters = _ReaderSearchChapter.parseList(
                decoded['chapters'],
              );
            }
          });
        }
        return;
      }
      if (type == 'searchError') {
        final requestId = (decoded['requestId'] as num?)?.toInt();
        if (requestId != _searchRequestId || !_searchVisible) {
          return;
        }
        if (mounted) {
          setState(() {
            _searchLoading = false;
            _webSearchActive = false;
          });
        }
        unawaited(
          _reportReaderError(
            decoded['message']?.toString() ?? '搜索失败',
            source: 'bookReader.search',
            extra: {'rawMessage': decoded},
          ),
        );
        return;
      }
      if (type == 'error') {
        _bookOpenTimer?.cancel();
        if (mounted) {
          final message = decoded['message']?.toString() ?? '打开书籍失败';
          unawaited(
            _reportReaderError(
              message,
              source: 'bookReader.bridge',
              extra: {'rawMessage': decoded},
            ),
          );
          setState(() {
            _loading = false;
            _error = message;
          });
        }
        return;
      }
      if (type != 'relocate') {
        return;
      }
      final progress = (decoded['progress'] as num?)?.toDouble() ?? 0;
      final locator = decoded['locator'];
      final nextChapterHref = decoded['chapterHref']?.toString();
      final chapterChanged = _chapterHref != nextChapterHref;
      final translatedChapterKey = _chapterTranslationKey;
      if (chapterChanged && translatedChapterKey != null) {
        unawaited(_restoreChapterOriginalInWebView(translatedChapterKey));
      }
      if (mounted) {
        setState(() {
          if (chapterChanged) {
            _chapterTranslationRequestToken += 1;
            _chapterTranslationStatus = _ReaderTranslationStatus.idle;
            _chapterTranslationKey = null;
          }
          _chapterHref = nextChapterHref;
          _readingProgress = progress.clamp(0, 1);
        });
      }
      await widget.progressDelegate.saveBookLocator(
        contentId: _contentId,
        progress: progress,
        locatorJson: jsonEncode(locator ?? decoded),
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.message',
          extra: {'rawMessage': message},
        ),
      );
      if (mounted) {
        setState(() => _error = error.toString());
      }
      return;
    }
  }

  Future<void> _reportReaderError(
    Object error, {
    StackTrace? stackTrace,
    required String source,
    Map<String, Object?> extra = const {},
  }) {
    final reporter = widget.options.diagnostics.errorReporter;
    if (reporter != null) {
      return reporter(
        ReaderErrorReport(
          error: error,
          stackTrace: stackTrace,
          source: source,
          extra: {
            'bookId': _contentId,
            'title': widget.book.title,
            'format': widget.book.format,
            'fileName': widget.book.fileName,
            'filePath': widget.book.filePath,
            ...extra,
          },
          book: widget.book,
        ),
      );
    }
    debugPrint('[$source] $error');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
    return Future.value();
  }

  Future<void> _copyDiagnostics() async {
    final provider = widget.options.diagnostics.textProvider;
    final text = provider != null
        ? await provider()
        : 'Diagnostics are not available.';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('诊断日志已复制')));
    }
  }

  Future<void> _applyReaderSystemUi(bool visible) async {
    await _setReaderSystemUiVisible(
      visible,
      backgroundColor: _readerSettings.backgroundColor,
    );
  }

  Future<void> _toggleControls() async {
    _hideTextActionMenu();
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (!_controlsVisible) {
        _tocVisible = false;
        _annotationsVisible = false;
        _progressVisible = false;
        _backgroundVisible = false;
        _settingsVisible = false;
      }
    });
    await _applyReaderSystemUi(_controlsVisible);
    // While auto-paging, opening the panels pauses; closing resumes.
    if (_autoPaging) {
      if (_controlsVisible) {
        _pauseAutoPaging();
      } else {
        _resumeAutoPaging();
      }
    }
  }

  Future<void> _dismissControls() async {
    _hideTextActionMenu();
    if (!_controlsVisible) {
      return;
    }
    setState(() {
      _controlsVisible = false;
      _tocVisible = false;
      _annotationsVisible = false;
      _progressVisible = false;
      _backgroundVisible = false;
      _settingsVisible = false;
    });
    await _applyReaderSystemUi(false);
    if (_autoPaging) {
      _resumeAutoPaging();
    }
  }

  void _enforceFeatureAvailability() {
    var shouldApplySystemUi = false;
    if (!_autoPagingEnabled && _autoPaging) {
      _stopAutoPaging();
      shouldApplySystemUi = true;
    }
    if (!_searchEnabled && _searchVisible) {
      _closeReaderSearch();
      shouldApplySystemUi = true;
    }
    if (!_translationEnabled) {
      _clearReaderTranslation();
      if (_chapterTranslationStatus != _ReaderTranslationStatus.idle) {
        _chapterTranslationRequestToken += 1;
        setState(() {
          _chapterTranslationStatus = _ReaderTranslationStatus.idle;
          _chapterTranslationKey = null;
        });
      }
    }
    if (!_notesEnabled && _noteComposerVisible) {
      _closeReaderNoteComposer();
    }
    if (!_annotationPanelEnabled && _annotationsVisible) {
      _closeReaderAnnotations();
    }
    if (!_backgroundImagesEnabled &&
        _readerSettings.backgroundImage.isNotEmpty) {
      unawaited(_applyReaderSettings(_readerSettings));
    }
    if (!_panelEnabled(_selectedPanel)) {
      _selectedPanel = _ReaderPanel.toc;
    }
    if (shouldApplySystemUi) {
      unawaited(_applyReaderSystemUi(_controlsVisible));
    }
  }

  void _handleReaderTap(Map<dynamic, dynamic> message) {
    if (!mounted || _noteComposerVisible || _searchVisible) {
      return;
    }
    final rawX = message['x'];
    if (rawX is! num) {
      return;
    }
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) {
      return;
    }
    final third = width / 3;
    final x = rawX.toDouble().clamp(0, width);
    if (_readerSettings.flow != ReaderFlow.paginated) {
      final isPdf =
          readerBookMimeType(
            widget.book.format,
            fileName: widget.book.fileName,
            filePath: widget.book.filePath,
          ) ==
          'application/pdf';
      if (isPdf && x < third) {
        unawaited(_turnPage('prev'));
      } else if (isPdf && x > third * 2) {
        unawaited(_turnPage('next'));
      } else if (x >= third && x <= third * 2) {
        unawaited(_toggleControls());
      }
      return;
    }
    if (x < third) {
      unawaited(_turnPage('prev'));
    } else if (x > third * 2) {
      unawaited(_turnPage('next'));
    } else {
      unawaited(_toggleControls());
    }
  }

  Future<void> _selectPanel(_ReaderPanel panel) async {
    if (!_panelEnabled(panel)) {
      return;
    }
    _hideTextActionMenu();
    setState(() {
      _selectedPanel = panel;
      _controlsVisible = true;
      _tocVisible = panel == _ReaderPanel.toc && !_tocVisible;
      _annotationsVisible =
          panel == _ReaderPanel.annotations && !_annotationsVisible;
      _progressVisible = panel == _ReaderPanel.progress && !_progressVisible;
      _backgroundVisible =
          panel == _ReaderPanel.background && !_backgroundVisible;
      _settingsVisible = panel == _ReaderPanel.font && !_settingsVisible;
      if (panel != _ReaderPanel.toc) {
        _tocVisible = false;
      }
      if (panel != _ReaderPanel.annotations) {
        _annotationsVisible = false;
      }
      if (panel != _ReaderPanel.progress) {
        _progressVisible = false;
      }
      if (panel != _ReaderPanel.background) {
        _backgroundVisible = false;
      }
      if (panel != _ReaderPanel.font) {
        _settingsVisible = false;
      }
    });
    if (_annotationsVisible) {
      unawaited(_loadReaderAnnotations());
    }
    await _applyReaderSystemUi(true);
    if (_autoPaging) {
      _pauseAutoPaging();
    }
  }

  Future<void> _turnPage(String direction, {bool manual = true}) async {
    _hideTextActionMenu();
    final method = direction == 'prev' ? 'prev' : 'next';
    if (manual && _autoPaging) {
      _resetAutoPageProgress();
    }
    try {
      final smooth = manual ? 'false' : 'true';
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.$method?.($smooth);',
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.turnPage',
          extra: {'direction': direction},
        ),
      );
    }
  }

  void _toggleAutoPaging() {
    if (!_autoPagingEnabled) {
      return;
    }
    if (_autoPaging) {
      _stopAutoPaging();
    } else {
      _startAutoPaging();
    }
  }

  void _startAutoPaging() {
    if (!_autoPagingEnabled) {
      return;
    }
    _autoPageElapsed = Duration.zero;
    _autoPageLastTick = Duration.zero;
    _autoPageProgress = 0;
    _autoPagePaused = false;
    _autoPageTicker?.dispose();
    _autoPageTicker = createTicker(_onAutoPageTick)..start();
    setState(() {
      _autoPaging = true;
      // Starting auto-paging closes the top/bottom control panels.
      _controlsVisible = false;
      _tocVisible = false;
      _annotationsVisible = false;
      _progressVisible = false;
      _backgroundVisible = false;
      _settingsVisible = false;
    });
    if (_readerSettings.flow == ReaderFlow.scrolled) {
      _startAutoScroll();
    }
    _applyReaderSystemUi(false);
  }

  void _stopAutoPaging() {
    _autoPageTicker?.dispose();
    _autoPageTicker = null;
    _autoPageElapsed = Duration.zero;
    _autoPageProgress = 0;
    _autoPagePaused = false;
    _stopAutoScroll();
    setState(() {
      _autoPaging = false;
      _autoPageSettingsVisible = false;
    });
    _applyReaderSystemUi(_controlsVisible);
  }

  void _onAutoPageTick(Duration now) {
    // Scrolled mode auto-advances via continuous JS scrolling, not the
    // page-flip timer, so the progress bar/ticker logic is skipped.
    if (_autoScrollMode) {
      return;
    }
    if (_autoPagePaused) {
      _autoPageLastTick = now;
      return;
    }
    final delta = now - _autoPageLastTick;
    _autoPageLastTick = now;
    if (delta <= Duration.zero) {
      return;
    }
    _autoPageElapsed += delta;
    final intervalMs = autoPageInterval(
      _readerSettings.autoPageSpeed,
    ).inMilliseconds.clamp(1, 1 << 30);
    final progress = _autoPageElapsed.inMilliseconds / intervalMs;
    if (progress >= 1) {
      if (!_autoPageTurning) {
        _autoPageTurning = true;
        unawaited(
          _turnPage('next', manual: false).whenComplete(() {
            _autoPageTurning = false;
          }),
        );
      }
      _autoPageElapsed = Duration.zero;
      setState(() => _autoPageProgress = 0);
      return;
    }
    setState(() => _autoPageProgress = progress);
  }

  void _resetAutoPageProgress() {
    _autoPageElapsed = Duration.zero;
    if (mounted) {
      setState(() => _autoPageProgress = 0);
    } else {
      _autoPageProgress = 0;
    }
  }

  bool get _autoScrollMode => _readerSettings.flow == ReaderFlow.scrolled;

  double get _autoScrollPxPerSecond =>
      kAutoScrollBasePxPerSecond * _readerSettings.autoPageSpeed;

  void _startAutoScroll() {
    unawaited(
      _controller.runJavaScript(
        'window.MistdeerReaderBridge?.startAutoScroll?.'
        '($_autoScrollPxPerSecond);',
      ),
    );
  }

  void _stopAutoScroll() {
    unawaited(
      _controller.runJavaScript(
        'window.MistdeerReaderBridge?.stopAutoScroll?.();',
      ),
    );
  }

  void _pauseAutoPaging() {
    if (!_autoPaging) {
      return;
    }
    _autoPagePaused = true;
    if (_autoScrollMode) {
      _stopAutoScroll();
    }
  }

  void _resumeAutoPaging() {
    if (!_autoPaging) {
      return;
    }
    _autoPagePaused = false;
    if (_autoScrollMode) {
      _startAutoScroll();
    }
  }

  void _openAutoPageSettings() {
    if (!_autoPaging) {
      return;
    }
    _pauseAutoPaging();
    setState(() => _autoPageSettingsVisible = true);
  }

  void _closeAutoPageSettings() {
    setState(() => _autoPageSettingsVisible = false);
    _resumeAutoPaging();
  }

  void _onAutoPageSpeedChanged(double speed) {
    final next = _readerSettings.copyWith(autoPageSpeed: speed);
    setState(() => _readerSettings = next);
    unawaited(_saveReaderSettings(next));
    // Apply new speed live to an in-flight scroll (settings sheet is open, so
    // paused; restart happens on resume, but if running, refresh now).
    if (_autoPaging && _autoScrollMode && !_autoPagePaused) {
      _startAutoScroll();
    }
  }

  void _showReadingDetails() {
    _readingDetailsEntry?.remove();
    _readingDetailsEntry = OverlayEntry(
      builder: (context) => _ReaderDetailsOverlay(
        settings: _readerSettings,
        onClose: _closeReadingDetails,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_readingDetailsEntry!);
  }

  void _closeReadingDetails() {
    _readingDetailsEntry?.remove();
    _readingDetailsEntry = null;
  }

  String _baseHref(String href) => href.split('#').first;

  int _currentTocIndex() {
    final currentHref = _chapterHref;
    if (currentHref == null || currentHref.isEmpty || _tocItems.isEmpty) {
      return -1;
    }
    final exactIndex = _tocItems.indexWhere((item) => item.href == currentHref);
    if (exactIndex >= 0) {
      return exactIndex;
    }
    final currentBase = _baseHref(currentHref);
    return _tocItems.indexWhere(
      (item) => item.href.isNotEmpty && _baseHref(item.href) == currentBase,
    );
  }

  _ReaderTocItem? _adjacentChapter(int delta) {
    final currentIndex = _currentTocIndex();
    if (currentIndex < 0) {
      return null;
    }
    final nextIndex = currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= _tocItems.length) {
      return null;
    }
    final item = _tocItems[nextIndex];
    return item.href.isEmpty ? null : item;
  }

  Future<void> _goToTocItem(
    _ReaderTocItem item, {
    bool closeControls = true,
  }) async {
    _hideTextActionMenu();
    if (item.href.isEmpty) {
      return;
    }
    try {
      await _restoreChapterTranslation(showFailure: false);
      final href = jsonEncode(item.href);
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.goTo?.($href);',
      );
      if (mounted) {
        setState(() {
          _tocVisible = false;
          if (closeControls) {
            _controlsVisible = false;
            _applyReaderSystemUi(false);
          }
        });
      }
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.goToToc',
          extra: {'href': item.href, 'label': item.label},
        ),
      );
    }
  }

  void _goToAdjacentChapter(int delta) {
    final item = _adjacentChapter(delta);
    if (item == null) {
      return;
    }
    unawaited(_goToTocItem(item, closeControls: false));
  }

  Future<void> _goToFraction(double fraction) async {
    _hideTextActionMenu();
    try {
      await _restoreChapterTranslation(showFailure: false);
      final clamped = fraction.clamp(0, 1).toStringAsFixed(6);
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.goToFraction?.($clamped);',
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.goToFraction',
          extra: {'fraction': fraction},
        ),
      );
    }
  }

  Future<void> _restoreReaderSettings() async {
    try {
      final store = widget.options.settings.store;
      if (store == null) {
        return;
      }
      final settings = await store.load();
      if (settings == null) {
        return;
      }
      final effectiveSettings = _settingsForEnabledFeatures(settings);
      if (!mounted) {
        _readerSettings = effectiveSettings;
        _publishReaderState();
        return;
      }
      setState(() => _readerSettings = effectiveSettings);
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.restoreSettings',
        ),
      );
    }
  }

  Future<void> _saveReaderSettings(ReaderSettings settings) async {
    try {
      await widget.options.settings.store?.save(settings);
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.saveSettings',
          extra: settings.toJson(),
        ),
      );
    }
  }

  Future<void> _sendReaderSettingsToWebView(ReaderSettings settings) async {
    final effectiveSettings = _settingsForEnabledFeatures(settings);
    try {
      final payload = jsonEncode({
        ...effectiveSettings.toJson(),
        'backgroundImageFit':
            _effectiveAppearanceOptions.backgroundImageFit.value,
      });
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.applySettings?.($payload);',
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.applySettings',
          extra: effectiveSettings.toJson(),
        ),
      );
    }
  }

  int get _readerNoteCount => _notesEnabled
      ? _readerAnnotations.where((item) => item.isNote).length
      : 0;

  void _closeReaderAnnotations() {
    setState(() => _annotationsVisible = false);
  }

  void _refreshReaderAnnotationsIfVisible() {
    if (_annotationsVisible) {
      unawaited(_loadReaderAnnotations());
    }
  }

  Future<void> _loadReaderAnnotations() async {
    if (!_annotationPanelEnabled) {
      return;
    }
    final token = ++_annotationsLoadToken;
    if (mounted) {
      setState(() => _annotationsLoading = true);
    }
    try {
      final rawAnnotations = await widget.annotationDelegate
          .loadAnnotationsForPage(_annotationPageUrl);
      final parsed = [
        for (final annotation in rawAnnotations)
          if ((annotation.style == 'note' && _notesEnabled) ||
              (annotation.style != 'note' && _annotationsEnabled))
            ?_ReaderAnnotationItem.fromAnnotation(annotation),
      ];
      final resolved = <_ReaderAnnotationItem>[];
      for (final item in parsed) {
        final chapter = await _readerAnnotationChapterLabel(item.locatorValue);
        resolved.add(item.copyWith(chapterLabel: chapter));
      }
      if (!mounted || token != _annotationsLoadToken) {
        return;
      }
      setState(() {
        _readerAnnotations = resolved;
        _annotationsLoading = false;
      });
    } on Object catch (error, stackTrace) {
      if (mounted && token == _annotationsLoadToken) {
        setState(() => _annotationsLoading = false);
      }
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.annotations.load',
        ),
      );
    }
  }

  Future<String> _readerAnnotationChapterLabel(String locatorValue) async {
    try {
      final encoded = jsonEncode(locatorValue);
      final result = await _controller.runJavaScriptReturningResult(
        'window.MistdeerReaderBridge?.annotationInfo?.($encoded) ?? "";',
      );
      final data = _decodeReaderJsonResult(result);
      final label = data?['chapter']?.toString().trim() ?? '';
      return label.isEmpty ? '未知章节' : label;
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.annotations.chapter',
          extra: {'locatorValue': locatorValue},
        ),
      );
      return '未知章节';
    }
  }

  Future<void> _goToReaderAnnotation(_ReaderAnnotationItem item) async {
    if (!_annotationPanelEnabled) {
      return;
    }
    _hideTextActionMenu();
    try {
      final encoded = jsonEncode(item.locatorValue);
      await _controller.runJavaScriptReturningResult(
        'window.MistdeerReaderBridge?.goToAnnotation?.($encoded) ?? false;',
      );
      if (mounted) {
        setState(() {
          _annotationsVisible = false;
          _controlsVisible = false;
        });
        await _applyReaderSystemUi(false);
      }
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.annotations.goTo',
          extra: {'locatorValue': item.locatorValue},
        ),
      );
    }
  }

  void _clearReaderTranslation({bool incrementToken = true}) {
    if (incrementToken) {
      _translationRequestToken += 1;
    }
    if (_translationStatus == _ReaderTranslationStatus.idle &&
        _translationText.isEmpty) {
      return;
    }
    if (!mounted) {
      _translationStatus = _ReaderTranslationStatus.idle;
      _translationText = '';
      return;
    }
    setState(() {
      _translationStatus = _ReaderTranslationStatus.idle;
      _translationText = '';
    });
  }

  Future<void> _translateTextSelection() async {
    if (!_translationEnabled) {
      return;
    }
    final text = _textSelection?.text.trim() ?? '';
    final token = ++_translationRequestToken;
    if (text.isEmpty) {
      setState(() {
        _translationStatus = _ReaderTranslationStatus.error;
        _translationText = '选中文字为空';
      });
      unawaited(_applyReaderSystemUi(false));
      return;
    }
    setState(() {
      _translationStatus = _ReaderTranslationStatus.loading;
      _translationText = '';
    });
    try {
      final delegate = widget.translationDelegate;
      if (delegate == null) {
        throw StateError('Translation delegate is not configured');
      }
      final translated = await delegate.translate(text);
      if (!mounted || token != _translationRequestToken) {
        return;
      }
      setState(() {
        _translationStatus = _ReaderTranslationStatus.success;
        _translationText = translated;
      });
    } on Object catch (error, stackTrace) {
      if (mounted && token == _translationRequestToken) {
        setState(() {
          _translationStatus = _ReaderTranslationStatus.error;
          _translationText = _readerTranslationErrorText(error);
        });
      }
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.translate',
          extra: {'textLength': text.length},
        ),
      );
    }
  }

  String _readerTranslationErrorText(Object error) {
    final text = error.toString().trim();
    if (text.startsWith('Bad state: ')) {
      return text.substring('Bad state: '.length);
    }
    if (text.isEmpty) {
      return '翻译失败';
    }
    return text;
  }

  bool _readerBridgeBool(Object? result) {
    if (result is bool) {
      return result;
    }
    if (result is String) {
      return result.trim().toLowerCase() == 'true';
    }
    return false;
  }

  void _showReaderSnackBar(String message) {
    if (!mounted || message.trim().isEmpty) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<_TranslationBatch> _createTranslationBatches(
    List<_ReaderParagraph> paragraphs,
  ) {
    const maxChars = 3500;
    final batches = <_TranslationBatch>[];
    final currentBatch = <_ReaderParagraph>[];
    var currentChars = 0;
    var batchStartIndex = 0;

    for (var i = 0; i < paragraphs.length; i++) {
      final para = paragraphs[i];

      // 单个段落超长：单独成批
      if (para.text.length > maxChars) {
        if (currentBatch.isNotEmpty) {
          batches.add(
            _TranslationBatch(
              paragraphs: List.from(currentBatch),
              startIndex: batchStartIndex,
            ),
          );
          currentBatch.clear();
          currentChars = 0;
        }

        batches.add(_TranslationBatch(paragraphs: [para], startIndex: i));
        batchStartIndex = i + 1;
        continue;
      }

      // 检查是否会超出批次限制
      if (currentChars + para.text.length > maxChars &&
          currentBatch.isNotEmpty) {
        batches.add(
          _TranslationBatch(
            paragraphs: List.from(currentBatch),
            startIndex: batchStartIndex,
          ),
        );
        currentBatch.clear();
        currentChars = 0;
        batchStartIndex = i;
      }

      currentBatch.add(para);
      currentChars += para.text.length;
    }

    if (currentBatch.isNotEmpty) {
      batches.add(
        _TranslationBatch(
          paragraphs: List.from(currentBatch),
          startIndex: batchStartIndex,
        ),
      );
    }

    return batches;
  }

  Future<_ReaderChapterText?> _loadCurrentChapterText() async {
    final result = await _controller.runJavaScriptReturningResult(
      'window.MistdeerReaderBridge?.getCurrentChapterText?.() ?? "";',
    );
    return _ReaderChapterText.fromReaderResult(result);
  }

  Future<bool> _showChapterTranslationInWebView(
    _ReaderChapterText chapter,
    List<_ParagraphTranslation> translations, {
    bool append = false,
  }) async {
    final key = jsonEncode(chapter.key);
    final dataJson = jsonEncode(translations.map((t) => t.toJson()).toList());
    final method = append
        ? 'appendChapterTranslation'
        : 'showChapterTranslation';

    // 使用立即执行函数表达式 (IIFE) 在 JavaScript 中解析 JSON
    final jsCode =
        '''
      (function() {
        try {
          const key = $key;
          const data = $dataJson;
          return window.MistdeerReaderBridge?.$method?.(key, data) ?? false;
        } catch (e) {
          console.error('[Translation] Error:', e);
          return false;
        }
      })()
    ''';

    final result = await _controller.runJavaScriptReturningResult(jsCode);
    return _readerBridgeBool(result);
  }

  Future<bool> _restoreChapterOriginalInWebView(String key) async {
    final encodedKey = jsonEncode(key);
    final result = await _controller.runJavaScriptReturningResult(
      'window.MistdeerReaderBridge?.restoreChapterOriginal?.($encodedKey) '
      '?? false;',
    );
    return _readerBridgeBool(result);
  }

  Future<void> _toggleChapterTranslation() async {
    if (!_translationEnabled) {
      return;
    }
    if (_chapterTranslationStatus == _ReaderTranslationStatus.loading) {
      return;
    }
    if (_chapterTranslationStatus == _ReaderTranslationStatus.success &&
        _chapterTranslationKey != null) {
      await _restoreChapterTranslation();
      return;
    }
    await _translateCurrentChapter();
  }

  Future<void> _restoreChapterTranslation({bool showFailure = true}) async {
    final key = _chapterTranslationKey;
    if (key == null || key.isEmpty) {
      setState(() {
        _chapterTranslationStatus = _ReaderTranslationStatus.idle;
        _chapterTranslationKey = null;
      });
      return;
    }
    final token = ++_chapterTranslationRequestToken;
    try {
      final restored = await _restoreChapterOriginalInWebView(key);
      if (!mounted || token != _chapterTranslationRequestToken) {
        return;
      }
      setState(() {
        _chapterTranslationStatus = _ReaderTranslationStatus.idle;
        _chapterTranslationKey = null;
      });
      if (!restored && showFailure) {
        _showReaderSnackBar('原文已失效，请重新打开章节');
      }
    } on Object catch (error, stackTrace) {
      if (mounted && token == _chapterTranslationRequestToken) {
        setState(
          () => _chapterTranslationStatus = _ReaderTranslationStatus.error,
        );
        if (showFailure) {
          _showReaderSnackBar(_readerTranslationErrorText(error));
        }
      }
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.chapterTranslation.restore',
          extra: {'chapterKey': key},
        ),
      );
    }
  }

  Future<void> _translateCurrentChapter() async {
    if (!_translationEnabled) {
      return;
    }
    _hideTextActionMenu();
    final token = ++_chapterTranslationRequestToken;
    setState(() {
      _chapterTranslationStatus = _ReaderTranslationStatus.loading;
      _chapterTranslationKey = null;
    });
    _ReaderChapterText? chapter;
    try {
      chapter = await _loadCurrentChapterText();
      if (chapter == null) {
        throw StateError('当前章节内容为空，无法翻译');
      }

      // 优先使用结构化段落数据
      if (chapter.paragraphs.isEmpty) {
        throw StateError('无法提取章节段落');
      }

      final batches = _createTranslationBatches(chapter.paragraphs);
      if (batches.isEmpty) {
        throw StateError('章节内容为空，无法翻译');
      }

      final delegate = widget.translationDelegate;
      if (delegate == null) {
        throw StateError('Translation delegate is not configured');
      }
      final allTranslations = <_ParagraphTranslation>[];
      Object? partialError;
      StackTrace? partialStackTrace;

      // 翻译所有批次
      for (final batch in batches) {
        if (!mounted || token != _chapterTranslationRequestToken) {
          return;
        }

        final paragraphTexts = batch.paragraphs.map((p) => p.text).toList();

        try {
          final translations = await delegate.translateBatch(paragraphTexts);

          if (translations.length != batch.paragraphs.length) {
            throw StateError('翻译段落数量不匹配，请重试');
          }

          final batchTranslations = <_ParagraphTranslation>[];
          // 组装结果
          for (var i = 0; i < batch.paragraphs.length; i++) {
            batchTranslations.add(
              _ParagraphTranslation(
                original: batch.paragraphs[i].text,
                translation: translations[i],
                index: batch.paragraphs[i].index,
              ),
            );
          }

          if (!mounted || token != _chapterTranslationRequestToken) {
            return;
          }

          final shown = await _showChapterTranslationInWebView(
            chapter,
            batchTranslations,
            append: allTranslations.isNotEmpty,
          );
          if (!shown) {
            throw StateError('翻译内容显示失败');
          }

          allTranslations.addAll(batchTranslations);
        } on Object catch (error, stackTrace) {
          partialError = error;
          partialStackTrace = stackTrace;
          break;
        }
      }

      if (!mounted || token != _chapterTranslationRequestToken) {
        return;
      }

      if (partialError != null) {
        if (allTranslations.isEmpty) {
          Error.throwWithStackTrace(partialError, partialStackTrace!);
        }
        setState(() {
          _chapterTranslationStatus = _ReaderTranslationStatus.success;
          _chapterTranslationKey = chapter!.key;
        });
        _showReaderSnackBar(
          '已翻译 ${allTranslations.length}/${chapter.paragraphs.length} 段，剩余段落稍后可重试',
        );
        unawaited(
          _reportReaderError(
            partialError,
            stackTrace: partialStackTrace,
            source: 'bookReader.chapterTranslation.partial',
            extra: {
              'chapterKey': chapter.key,
              'chapterHref': chapter.href,
              'paragraphCount': chapter.paragraphs.length,
              'translatedCount': allTranslations.length,
            },
          ),
        );
        return;
      }

      if (!mounted || token != _chapterTranslationRequestToken) {
        return;
      }

      setState(() {
        _chapterTranslationStatus = _ReaderTranslationStatus.success;
        _chapterTranslationKey = chapter!.key;
      });
    } on Object catch (error, stackTrace) {
      if (mounted && token == _chapterTranslationRequestToken) {
        setState(() {
          _chapterTranslationStatus = _ReaderTranslationStatus.error;
          _chapterTranslationKey = null;
        });
        _showReaderSnackBar(_readerTranslationErrorText(error));
      }
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.chapterTranslation.translate',
          extra: {
            'chapterKey': chapter?.key,
            'chapterHref': chapter?.href,
            'paragraphCount': chapter?.paragraphs.length,
          },
        ),
      );
    }
  }

  Future<void> _restoreTextHighlights() async {
    if (!_annotationsEnabled && !_notesEnabled) {
      return;
    }
    try {
      final annotations = await widget.annotationDelegate
          .loadAnnotationsForPage(_annotationPageUrl);
      final highlights = <Map<String, Object?>>[];
      for (final annotation in annotations) {
        final value = annotation.locatorValue;
        if (value.isEmpty) {
          continue;
        }
        final rawStyle = annotation.style;
        if (rawStyle == 'note') {
          if (!_notesEnabled) {
            continue;
          }
          highlights.add({
            'value': value,
            'type': 'note',
            'style': 'note',
            'color': _readerHighlightColors.first.hex,
            'text': annotation.text,
            'note': annotation.note,
          });
          continue;
        }
        if (!_annotationsEnabled) {
          continue;
        }
        final style = _ReaderHighlightStyle.fromValue(rawStyle);
        final color = _readerHighlightColorByHex(annotation.color);
        highlights.add({
          'value': value,
          'type': style.jsValue,
          'style': style.jsValue,
          'color': color.hex,
          'text': annotation.text,
        });
      }
      final payload = jsonEncode(highlights);
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.setTextHighlights?.($payload);',
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.restoreHighlights',
        ),
      );
    }
  }

  Map<String, dynamic>? _decodeReaderJsonResult(Object? value) {
    var decoded = value;
    for (var i = 0; i < 2 && decoded is String; i++) {
      final text = decoded.trim();
      if (text.isEmpty || text == 'null') {
        return null;
      }
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        break;
      }
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return null;
  }

  void _openReaderSearch(String initialQuery) {
    if (!_searchEnabled) {
      return;
    }
    _hideTextActionMenu();
    if (_autoPaging) {
      _pauseAutoPaging();
    }
    final query = initialQuery.trim();
    setState(() {
      _searchVisible = true;
      _searchQuery = query;
      _searchChapters = const [];
      _searchLoading = query.isNotEmpty;
    });
    _scheduleReaderSearch(query, immediate: true);
  }

  void _closeReaderSearch({bool clearWebSearch = true}) {
    _searchDebounce?.cancel();
    _searchRequestId++;
    setState(() {
      _searchVisible = false;
      _searchLoading = false;
      _searchQuery = '';
      _searchChapters = const [];
    });
    if (clearWebSearch) {
      unawaited(_clearReaderSearchResults());
    }
    if (_autoPaging) {
      _resumeAutoPaging();
    }
  }

  void _handleSearchQueryChanged(String query) {
    if (!_searchEnabled) {
      return;
    }
    setState(() {
      _searchQuery = query;
      _searchLoading = query.trim().isNotEmpty;
      _searchChapters = const [];
    });
    _scheduleReaderSearch(query);
  }

  void _scheduleReaderSearch(String query, {bool immediate = false}) {
    if (!_searchEnabled) {
      return;
    }
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      _searchRequestId++;
      unawaited(_clearReaderSearchResults());
      return;
    }
    if (immediate) {
      unawaited(_runReaderSearch(query));
      return;
    }
    _searchDebounce = Timer(
      widget.options.behavior.searchDebounce,
      () => unawaited(_runReaderSearch(query)),
    );
  }

  Future<void> _runReaderSearch(String query) async {
    if (!_searchEnabled) {
      return;
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final requestId = ++_searchRequestId;
    try {
      final encodedQuery = jsonEncode(trimmed);
      _webSearchActive = true;
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.searchText?.'
        '($encodedQuery, $requestId);',
      );
      if (!mounted || requestId != _searchRequestId) {
        return;
      }
    } on Object catch (error, stackTrace) {
      if (mounted && requestId == _searchRequestId) {
        setState(() {
          _searchLoading = false;
          _webSearchActive = false;
        });
      }
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.search',
          extra: {'query': trimmed},
        ),
      );
    }
  }

  Future<void> _goToSearchResult(_ReaderSearchItem item) async {
    try {
      final encodedCfi = jsonEncode(item.cfi);
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.goToSearchResult?.($encodedCfi);',
      );
      if (mounted) {
        _closeReaderSearch();
      }
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.searchGoTo',
          extra: {'cfi': item.cfi},
        ),
      );
    }
  }

  Future<void> _clearReaderSearchResults() async {
    _webSearchActive = false;
    try {
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.clearSearch?.();',
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.searchClear',
        ),
      );
    }
  }

  Future<void> _openReaderNoteComposer() async {
    if (!_notesEnabled) {
      return;
    }
    try {
      final result = await _controller.runJavaScriptReturningResult(
        'window.MistdeerReaderBridge?.getTextSelectionAnnotation?.() ?? "";',
      );
      final selection = _ReaderSelectionAnnotation.fromReaderResult(result);
      if (selection == null) {
        unawaited(
          _reportReaderError(
            'Reader note selection result was empty.',
            source: 'bookReader.note.emptySelection',
            extra: {'rawResult': result.toString()},
          ),
        );
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _noteComposerVisible = true;
        _noteSubmitting = false;
        _noteSelection = selection;
        _noteEditingExisting = false;
      });
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.note.open',
        ),
      );
    }
  }

  void _closeReaderNoteComposer({bool clearSelection = true}) {
    setState(() {
      _noteComposerVisible = false;
      _noteSubmitting = false;
      _noteSelection = null;
      _noteEditingExisting = false;
    });
    if (clearSelection) {
      if (_textSelection != null || _textSelectionDragging) {
        _hideTextActionMenu();
      } else {
        unawaited(_clearWebTextSelection());
        if (_autoPaging) {
          _resumeAutoPaging();
        }
      }
    }
  }

  Future<void> _submitReaderNote(String note) async {
    if (!_notesEnabled) {
      return;
    }
    final selection = _noteSelection;
    final trimmed = note.trim();
    if (selection == null || trimmed.isEmpty || _noteSubmitting) {
      return;
    }
    setState(() => _noteSubmitting = true);
    try {
      if (_noteEditingExisting) {
        await widget.annotationDelegate.updateAnnotationNoteByLocator(
          pageUrl: _annotationPageUrl,
          locatorValue: selection.value,
          note: trimmed,
        );
      } else {
        await widget.annotationDelegate.createAnnotation(
          ReaderAnnotationDraft(
            type: 'note',
            text: selection.text,
            note: trimmed,
            pageUrl: _annotationPageUrl,
            pageTitle: _annotationPageTitle,
            locatorValue: selection.value,
            style: 'note',
            color: _readerHighlightColors.first.hex,
          ),
        );
      }
      await _setReaderTextAnnotation(
        value: selection.value,
        text: selection.text,
        note: trimmed,
      );
      _refreshReaderAnnotationsIfVisible();
      if (!mounted) {
        return;
      }
      _closeReaderNoteComposer();
    } on Object catch (error, stackTrace) {
      if (mounted) {
        setState(() => _noteSubmitting = false);
      }
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.note.submit',
          extra: {'locatorValue': selection.value},
        ),
      );
    }
  }

  Future<void> _setReaderTextAnnotation({
    required String value,
    required String text,
    required String note,
  }) async {
    final payload = jsonEncode({
      'value': value,
      'type': 'note',
      'style': 'note',
      'color': _readerHighlightColors.first.hex,
      'text': text,
      'note': note,
    });
    await _controller.runJavaScriptReturningResult(
      'window.MistdeerReaderBridge?.setTextAnnotation?.($payload) ?? "";',
    );
  }

  void _handleReaderAnnotationSelected(_ReaderSelectedAnnotation annotation) {
    if (annotation.isNote && !_notesEnabled) {
      return;
    }
    if (!annotation.isNote && !_annotationsEnabled) {
      return;
    }
    if (_autoPaging) {
      _pauseAutoPaging();
    }
    if (annotation.isNote) {
      setState(() {
        _textSelection = null;
        _textSelectionDragging = false;
        _textSelectionLongPressMoved = false;
        _textSelectionLongPressStart = null;
        _activeHighlight = null;
        _noteComposerVisible = true;
        _noteSubmitting = false;
        _noteSelection = _ReaderSelectionAnnotation(
          value: annotation.value,
          text: annotation.text,
          note: annotation.note,
        );
        _noteEditingExisting = true;
        _controlsVisible = false;
        _tocVisible = false;
        _annotationsVisible = false;
        _progressVisible = false;
        _backgroundVisible = false;
        _settingsVisible = false;
        _autoPageSettingsVisible = false;
      });
      return;
    }
    final style = _ReaderHighlightStyle.fromValue(annotation.style);
    final color = _readerHighlightColorByHex(annotation.colorHex);
    setState(() {
      _noteComposerVisible = false;
      _noteSubmitting = false;
      _noteSelection = null;
      _noteEditingExisting = false;
      _textSelection = annotation.selection;
      _textSelectionDragging = false;
      _textSelectionLongPressMoved = false;
      _textSelectionLongPressStart = null;
      _activeHighlight = _ReaderActiveHighlight(
        value: annotation.value,
        text: annotation.text,
        style: style,
        colorHex: color.hex,
      );
      _highlightStyle = style;
      _highlightColor = color;
      _controlsVisible = false;
      _tocVisible = false;
      _annotationsVisible = false;
      _progressVisible = false;
      _backgroundVisible = false;
      _settingsVisible = false;
      _autoPageSettingsVisible = false;
    });
    unawaited(_applyReaderSystemUi(false));
  }

  _ReaderActiveHighlight? _highlightFromReaderResult(Object? result) {
    final data = _decodeReaderJsonResult(result);
    final value = data?['value']?.toString() ?? '';
    if (value.isEmpty) {
      return null;
    }
    final style = _ReaderHighlightStyle.fromValue(
      data?['style']?.toString() ?? data?['type']?.toString(),
    );
    final color = _readerHighlightColorByHex(data?['color']?.toString());
    return _ReaderActiveHighlight(
      value: value,
      text: data?['text']?.toString() ?? _textSelection?.text ?? '',
      style: style,
      colorHex: color.hex,
    );
  }

  Future<void> _applyTextHighlight() async {
    if (!_annotationsEnabled) {
      return;
    }
    try {
      final style = jsonEncode(_highlightStyle.jsValue);
      final color = jsonEncode(_highlightColor.hex);
      final result = await _controller.runJavaScriptReturningResult(
        'window.MistdeerReaderBridge?.applyTextHighlight?.($style, $color) '
        '?? "";',
      );
      final highlight = _highlightFromReaderResult(result);
      if (highlight == null) {
        unawaited(
          _reportReaderError(
            'Reader highlight result was empty.',
            source: 'bookReader.applyHighlight.emptyResult',
            extra: {'rawResult': result.toString()},
          ),
        );
        return;
      }
      await widget.annotationDelegate.createAnnotation(
        ReaderAnnotationDraft(
          type: highlight.style.jsValue,
          text: highlight.text,
          note: '',
          pageUrl: _annotationPageUrl,
          pageTitle: _annotationPageTitle,
          locatorValue: highlight.value,
          style: highlight.style.jsValue,
          color: highlight.colorHex,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _activeHighlight = highlight;
        _highlightStyle = highlight.style;
        _highlightColor = _readerHighlightColorByHex(highlight.colorHex);
      });
      _refreshReaderAnnotationsIfVisible();
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.applyHighlight',
        ),
      );
    }
  }

  Future<void> _updateTextHighlight({
    _ReaderHighlightStyle? style,
    _ReaderHighlightColorOption? color,
  }) async {
    if (!_annotationsEnabled) {
      return;
    }
    final current = _activeHighlight;
    if (current == null) {
      return;
    }
    final nextStyle = style ?? _highlightStyle;
    final nextColor = color ?? _highlightColor;
    try {
      final encodedValue = jsonEncode(current.value);
      final encodedStyle = jsonEncode(nextStyle.jsValue);
      final encodedColor = jsonEncode(nextColor.hex);
      await _controller.runJavaScriptReturningResult(
        'window.MistdeerReaderBridge?.updateTextHighlight?.'
        '($encodedValue, $encodedStyle, $encodedColor) ?? "";',
      );
      await widget.annotationDelegate.updateAnnotationByLocator(
        pageUrl: _annotationPageUrl,
        locatorValue: current.value,
        type: nextStyle.jsValue,
        style: nextStyle.jsValue,
        color: nextColor.hex,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _highlightStyle = nextStyle;
        _highlightColor = nextColor;
        _activeHighlight = current.copyWith(
          style: nextStyle,
          colorHex: nextColor.hex,
        );
      });
      _refreshReaderAnnotationsIfVisible();
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.updateHighlight',
          extra: {'locatorValue': current.value},
        ),
      );
    }
  }

  Future<void> _deleteTextHighlight() async {
    if (!_annotationsEnabled) {
      _hideTextActionMenu();
      return;
    }
    final current = _activeHighlight;
    if (current == null) {
      _hideTextActionMenu();
      return;
    }
    try {
      final encodedValue = jsonEncode(current.value);
      await _controller.runJavaScriptReturningResult(
        'window.MistdeerReaderBridge?.deleteTextHighlight?.($encodedValue) '
        '?? false;',
      );
      await widget.annotationDelegate.deleteAnnotationByLocator(
        pageUrl: _annotationPageUrl,
        locatorValue: current.value,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _activeHighlight = null;
        _highlightStyle = _ReaderHighlightStyle.highlight;
        _highlightColor = _readerHighlightColors.first;
      });
      _refreshReaderAnnotationsIfVisible();
      _hideTextActionMenu();
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.deleteHighlight',
          extra: {'locatorValue': current.value},
        ),
      );
    }
  }

  Future<void> _applyReaderSettings(ReaderSettings settings) async {
    final effectiveSettings = _settingsForEnabledFeatures(settings);
    if (mounted) {
      setState(() => _readerSettings = effectiveSettings);
    } else {
      _readerSettings = effectiveSettings;
    }
    unawaited(_saveReaderSettings(effectiveSettings));
    unawaited(_applyReaderSystemUi(_controlsVisible));
    await _sendReaderSettingsToWebView(effectiveSettings);
  }

  Duration get _readingDuration => DateTime.now().difference(_readingStartedAt);

  void _showTextActionMenu(Offset position) {
    final token = ++_textSelectionRequestToken;
    if (_autoPaging) {
      _pauseAutoPaging();
    }
    if (_webSearchActive) {
      unawaited(_clearReaderSearchResults());
    }
    _translationRequestToken += 1;
    setState(() {
      _noteComposerVisible = false;
      _noteSubmitting = false;
      _noteSelection = null;
      _noteEditingExisting = false;
      _textSelection = null;
      _textSelectionDragging = true;
      _textSelectionLongPressMoved = false;
      _textSelectionLongPressStart = position;
      _activeHighlight = null;
      _highlightStyle = _ReaderHighlightStyle.highlight;
      _highlightColor = _readerHighlightColors.first;
      _translationStatus = _ReaderTranslationStatus.idle;
      _translationText = '';
      _controlsVisible = false;
      _tocVisible = false;
      _annotationsVisible = false;
      _progressVisible = false;
      _backgroundVisible = false;
      _settingsVisible = false;
    });
    unawaited(_applyReaderSystemUi(false));
    unawaited(_startTextSelection(position, token));
  }

  void _extendTextSelection(Offset position) {
    final start = _textSelectionLongPressStart;
    if (!_textSelectionLongPressMoved &&
        start != null &&
        (position - start).distance <
            widget.options.behavior.selectionDragThreshold) {
      return;
    }
    _textSelectionLongPressMoved = true;
    unawaited(_updateTextSelectionHandle('end', position));
  }

  void _finishLongPressTextSelection(Offset position) {
    if (!_textSelectionLongPressMoved) {
      if (mounted) {
        setState(() {
          _textSelectionDragging = false;
          _textSelectionLongPressMoved = false;
          _textSelectionLongPressStart = null;
        });
      } else {
        _textSelectionDragging = false;
        _textSelectionLongPressMoved = false;
        _textSelectionLongPressStart = null;
      }
      return;
    }
    final token = _textSelectionRequestToken;
    unawaited(_finishTextSelectionDrag('end', position, token: token));
  }

  void _beginTextSelectionDrag(String handle) {
    _clearReaderTranslation();
    if (mounted) {
      setState(() => _textSelectionDragging = true);
    } else {
      _textSelectionDragging = true;
    }
    unawaited(_beginWebTextSelectionDrag(handle));
  }

  Future<void> _finishTextSelectionDrag(
    String handle,
    Offset position, {
    int? token,
  }) async {
    await _finishWebTextSelectionDrag(handle, position);
    if (token != null && token != _textSelectionRequestToken) {
      return;
    }
    if (mounted) {
      setState(() {
        _textSelectionDragging = false;
        _textSelectionLongPressMoved = false;
        _textSelectionLongPressStart = null;
      });
    } else {
      _textSelectionDragging = false;
      _textSelectionLongPressMoved = false;
      _textSelectionLongPressStart = null;
    }
  }

  void _hideTextActionMenu({bool notifyWebView = true}) {
    if (_textSelection == null && !_textSelectionDragging) {
      _clearReaderTranslation();
      return;
    }
    setState(() {
      _textSelection = null;
      _textSelectionDragging = false;
      _textSelectionLongPressMoved = false;
      _textSelectionLongPressStart = null;
      _activeHighlight = null;
      _translationStatus = _ReaderTranslationStatus.idle;
      _translationText = '';
    });
    _textSelectionRequestToken += 1;
    _translationRequestToken += 1;
    if (notifyWebView) {
      unawaited(_clearWebTextSelection());
    }
    if (_autoPaging) {
      _resumeAutoPaging();
    }
  }

  void _handleTextActionSelected(_ReaderTextActionKind kind) {
    if (kind == _ReaderTextActionKind.highlight) {
      if (!_annotationsEnabled) {
        return;
      }
      _clearReaderTranslation();
      unawaited(_applyTextHighlight());
      return;
    }
    if (kind == _ReaderTextActionKind.search) {
      if (!_searchEnabled) {
        return;
      }
      _clearReaderTranslation();
      _openReaderSearch(_textSelection?.text ?? '');
      return;
    }
    if (kind == _ReaderTextActionKind.note) {
      if (!_notesEnabled) {
        return;
      }
      _clearReaderTranslation();
      unawaited(_openReaderNoteComposer());
      return;
    }
    if (kind == _ReaderTextActionKind.translate) {
      if (!_translationEnabled) {
        return;
      }
      unawaited(_translateTextSelection());
      return;
    }
    _hideTextActionMenu();
  }

  String _selectionPointArgs(Offset position) {
    final x = position.dx.toStringAsFixed(2);
    final y = position.dy.toStringAsFixed(2);
    return '$x, $y';
  }

  Future<void> _startTextSelection(Offset position, int token) async {
    try {
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.startTextSelection?.'
        '(${_selectionPointArgs(position)}, $token);',
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.selectionStart',
        ),
      );
    }
  }

  Future<void> _beginWebTextSelectionDrag(String handle) async {
    try {
      final encodedHandle = jsonEncode(handle);
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.beginTextSelectionDrag?.'
        '($encodedHandle);',
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.selectionDragStart',
          extra: {'handle': handle},
        ),
      );
    }
  }

  Future<void> _updateTextSelectionHandle(
    String handle,
    Offset position,
  ) async {
    try {
      final encodedHandle = jsonEncode(handle);
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.updateTextSelectionHandle?.'
        '($encodedHandle, ${_selectionPointArgs(position)});',
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.selectionUpdate',
          extra: {'handle': handle},
        ),
      );
    }
  }

  Future<void> _finishWebTextSelectionDrag(
    String handle,
    Offset position,
  ) async {
    try {
      final encodedHandle = jsonEncode(handle);
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.finishTextSelectionDrag?.'
        '($encodedHandle, ${_selectionPointArgs(position)});',
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.selectionDragEnd',
          extra: {'handle': handle},
        ),
      );
    }
  }

  Future<void> _clearWebTextSelection() async {
    try {
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.clearTextSelection?.();',
      );
    } on Object catch (error, stackTrace) {
      unawaited(
        _reportReaderError(
          error,
          stackTrace: stackTrace,
          source: 'bookReader.selectionClear',
        ),
      );
    }
  }

  void _goBack() {
    if (_noteComposerVisible) {
      _closeReaderNoteComposer();
      return;
    }
    if (_searchVisible) {
      _closeReaderSearch();
      return;
    }
    if (_annotationsVisible) {
      _closeReaderAnnotations();
      return;
    }
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReaderState>(
      valueListenable: _readerController,
      builder: (context, state, _) {
        final topPadding = MediaQuery.paddingOf(context).top;
        final bottomPadding = MediaQuery.paddingOf(context).bottom;
        final readerContext = ReaderChromeContext(
          controller: _readerController,
          state: state,
          settings: state.settings,
          bottomBarHeight: 72 + bottomPadding,
          topPadding: topPadding,
          bottomPadding: bottomPadding,
        );
        return Scaffold(
          extendBody: true,
          resizeToAvoidBottomInset: false,
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: _defaultChrome(context, readerContext),
        );
      },
    );
  }
}
