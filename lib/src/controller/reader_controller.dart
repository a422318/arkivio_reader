import 'package:flutter/foundation.dart';

import '../models/reader_chrome.dart';
import '../models/reader_settings.dart';

/// Snapshot of the reader's observable state.
class ReaderState {
  const ReaderState({
    this.loading = true,
    this.error,
    this.controlsVisible = false,
    this.selectedPanel = ReaderPanel.toc,
    this.openPanel,
    this.progress = 0,
    this.chapterHref,
    this.tocItems = const [],
    this.selectedTocIndex = -1,
    this.annotations = const [],
    this.annotationsLoading = false,
    this.autoPaging = false,
    this.autoPageProgress = 0,
    this.chapterTranslationStatus = ReaderTranslationStatus.idle,
    this.readingDuration = Duration.zero,
    this.noteCount = 0,
    this.settings = const ReaderSettings(),
  });

  final bool loading;
  final String? error;
  final bool controlsVisible;
  final ReaderPanel selectedPanel;
  final ReaderPanel? openPanel;
  final double progress;
  final String? chapterHref;
  final List<ReaderTocEntry> tocItems;
  final int selectedTocIndex;
  final List<ReaderAnnotationEntry> annotations;
  final bool annotationsLoading;
  final bool autoPaging;
  final double autoPageProgress;
  final ReaderTranslationStatus chapterTranslationStatus;
  final Duration readingDuration;
  final int noteCount;
  final ReaderSettings settings;

  ReaderState copyWith({
    bool? loading,
    String? error,
    bool clearError = false,
    bool? controlsVisible,
    ReaderPanel? selectedPanel,
    ReaderPanel? openPanel,
    bool clearOpenPanel = false,
    double? progress,
    String? chapterHref,
    List<ReaderTocEntry>? tocItems,
    int? selectedTocIndex,
    List<ReaderAnnotationEntry>? annotations,
    bool? annotationsLoading,
    bool? autoPaging,
    double? autoPageProgress,
    ReaderTranslationStatus? chapterTranslationStatus,
    Duration? readingDuration,
    int? noteCount,
    ReaderSettings? settings,
  }) {
    return ReaderState(
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      controlsVisible: controlsVisible ?? this.controlsVisible,
      selectedPanel: selectedPanel ?? this.selectedPanel,
      openPanel: clearOpenPanel ? null : openPanel ?? this.openPanel,
      progress: progress ?? this.progress,
      chapterHref: chapterHref ?? this.chapterHref,
      tocItems: tocItems ?? this.tocItems,
      selectedTocIndex: selectedTocIndex ?? this.selectedTocIndex,
      annotations: annotations ?? this.annotations,
      annotationsLoading: annotationsLoading ?? this.annotationsLoading,
      autoPaging: autoPaging ?? this.autoPaging,
      autoPageProgress: autoPageProgress ?? this.autoPageProgress,
      chapterTranslationStatus:
          chapterTranslationStatus ?? this.chapterTranslationStatus,
      readingDuration: readingDuration ?? this.readingDuration,
      noteCount: noteCount ?? this.noteCount,
      settings: settings ?? this.settings,
    );
  }
}

typedef ReaderCommandHandler = Future<void> Function();
typedef ReaderHrefCommandHandler = Future<void> Function(String href);
typedef ReaderFractionCommandHandler = Future<void> Function(double fraction);
typedef ReaderSearchCommandHandler = Future<void> Function(String query);
typedef ReaderSettingsCommandHandler =
    Future<void> Function(ReaderSettings settings);
typedef ReaderPanelCommandHandler = Future<void> Function(ReaderPanel panel);

/// Controller used to observe and drive a reader page.
///
/// The controller is bound when the reader page mounts and unbound when it
/// disposes. Reuse the same controller while the page is alive if external
/// widgets need to observe [value] or issue commands.
class ReaderController extends ChangeNotifier
    implements ValueListenable<ReaderState> {
  ReaderController();

  ReaderState _value = const ReaderState();
  ReaderCommandHandler? _nextPage;
  ReaderCommandHandler? _previousPage;
  ReaderHrefCommandHandler? _goToHref;
  ReaderFractionCommandHandler? _goToFraction;
  ReaderSearchCommandHandler? _search;
  ReaderCommandHandler? _clearSearch;
  ReaderSettingsCommandHandler? _applySettings;
  ReaderCommandHandler? _toggleControls;
  ReaderCommandHandler? _dismissControls;
  ReaderPanelCommandHandler? _selectPanel;
  ReaderCommandHandler? _toggleAutoPaging;
  ReaderCommandHandler? _toggleChapterTranslation;

  @override
  ReaderState get value => _value;

  void setValue(ReaderState value) {
    _value = value;
    notifyListeners();
  }

  void bind({
    ReaderCommandHandler? nextPage,
    ReaderCommandHandler? previousPage,
    ReaderHrefCommandHandler? goToHref,
    ReaderFractionCommandHandler? goToFraction,
    ReaderSearchCommandHandler? search,
    ReaderCommandHandler? clearSearch,
    ReaderSettingsCommandHandler? applySettings,
    ReaderCommandHandler? toggleControls,
    ReaderCommandHandler? dismissControls,
    ReaderPanelCommandHandler? selectPanel,
    ReaderCommandHandler? toggleAutoPaging,
    ReaderCommandHandler? toggleChapterTranslation,
  }) {
    _nextPage = nextPage;
    _previousPage = previousPage;
    _goToHref = goToHref;
    _goToFraction = goToFraction;
    _search = search;
    _clearSearch = clearSearch;
    _applySettings = applySettings;
    _toggleControls = toggleControls;
    _dismissControls = dismissControls;
    _selectPanel = selectPanel;
    _toggleAutoPaging = toggleAutoPaging;
    _toggleChapterTranslation = toggleChapterTranslation;
  }

  void unbind() {
    bind();
  }

  Future<void> nextPage() => _nextPage?.call() ?? Future.value();

  Future<void> previousPage() => _previousPage?.call() ?? Future.value();

  Future<void> goToHref(String href) => _goToHref?.call(href) ?? Future.value();

  Future<void> goToFraction(double fraction) =>
      _goToFraction?.call(fraction) ?? Future.value();

  Future<void> search(String query) => _search?.call(query) ?? Future.value();

  Future<void> clearSearch() => _clearSearch?.call() ?? Future.value();

  Future<void> applySettings(ReaderSettings settings) =>
      _applySettings?.call(settings) ?? Future.value();

  Future<void> toggleControls() => _toggleControls?.call() ?? Future.value();

  Future<void> dismissControls() => _dismissControls?.call() ?? Future.value();

  Future<void> selectPanel(ReaderPanel panel) =>
      _selectPanel?.call(panel) ?? Future.value();

  Future<void> toggleAutoPaging() =>
      _toggleAutoPaging?.call() ?? Future.value();

  Future<void> toggleChapterTranslation() =>
      _toggleChapterTranslation?.call() ?? Future.value();
}

@Deprecated('Use ReaderController instead.')
class ReaderControllerImpl extends ReaderController {
  ReaderControllerImpl();
}
