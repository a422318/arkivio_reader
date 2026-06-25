import 'package:flutter/widgets.dart';

import '../storage/reader_settings_store.dart';
import 'reader_chrome.dart';
import 'reader_diagnostics.dart';
import 'reader_settings.dart';

typedef ReaderLoadingBuilder = Widget Function(BuildContext context);

typedef ReaderErrorBuilder =
    Widget Function(BuildContext context, ReaderErrorViewData error);

class ReaderErrorViewData {
  const ReaderErrorViewData({
    required this.message,
    required this.copyDiagnostics,
  });

  final String message;
  final VoidCallback copyDiagnostics;
}

class ReaderOptions {
  const ReaderOptions({
    this.settings = const ReaderSettingsOptions(),
    this.chrome = const ReaderChromeOptions(),
    this.behavior = const ReaderBehaviorOptions(),
    this.features = const ReaderFeatureOptions(),
    this.diagnostics = const ReaderDiagnosticsOptions(),
  });

  final ReaderSettingsOptions settings;
  final ReaderChromeOptions chrome;
  final ReaderBehaviorOptions behavior;
  final ReaderFeatureOptions features;
  final ReaderDiagnosticsOptions diagnostics;
}

class ReaderSettingsOptions {
  const ReaderSettingsOptions({
    this.initial = const ReaderSettings(),
    this.appearance = const ReaderAppearanceOptions(),
    this.store = const SharedPreferencesReaderSettingsStore(),
  });

  final ReaderSettings initial;
  final ReaderAppearanceOptions appearance;
  final ReaderSettingsStore? store;
}

class ReaderChromeOptions {
  const ReaderChromeOptions({
    this.builders = const ReaderChromeBuilders(),
    this.loadingBuilder,
    this.errorBuilder,
  });

  final ReaderChromeBuilders builders;
  final ReaderLoadingBuilder? loadingBuilder;
  final ReaderErrorBuilder? errorBuilder;
}

class ReaderBehaviorOptions {
  const ReaderBehaviorOptions({
    this.readyTimeout = const Duration(seconds: 15),
    this.bookOpenTimeout = const Duration(seconds: 60),
    this.searchDebounce = const Duration(milliseconds: 280),
    this.bookTransferChunkSize = 512 * 1024,
    this.selectionDragThreshold = 8,
  });

  /// Maximum time to wait for the WebView bridge to become available.
  final Duration readyTimeout;

  /// Maximum time to wait for a book to parse, render, and report `loaded`.
  ///
  /// MOBI, AZW3, and PDF can be slower than EPUB on mobile devices because
  /// they require additional parsing or page rendering in JavaScript.
  final Duration bookOpenTimeout;

  final Duration searchDebounce;
  final int bookTransferChunkSize;
  final double selectionDragThreshold;
}

class ReaderFeatureOptions {
  const ReaderFeatureOptions({
    this.search = true,
    this.annotations = true,
    this.notes = true,
    this.translation = true,
    this.autoPaging = true,
    this.backgroundImages = true,
  });

  /// Enables full-book search UI and controller search commands.
  final bool search;

  /// Enables highlight creation, editing, deletion, and highlight restore.
  ///
  /// A non-noop `ReaderAnnotationDelegate` is also required.
  final bool annotations;

  /// Enables note creation, editing, deletion, and note restore.
  ///
  /// A non-noop `ReaderAnnotationDelegate` is also required.
  final bool notes;

  /// Enables selected-text and chapter translation UI.
  ///
  /// A `ReaderTranslationDelegate` is also required.
  final bool translation;

  /// Enables automatic page turning controls.
  final bool autoPaging;

  /// Enables image choices in the background panel.
  ///
  /// Plain background colors remain available when this is false.
  final bool backgroundImages;
}

class ReaderDiagnosticsOptions {
  const ReaderDiagnosticsOptions({
    this.errorReporter,
    this.textProvider,
    this.enableWebViewConsoleLog = false,
  });

  final ReaderErrorReporter? errorReporter;
  final ReaderDiagnosticsTextProvider? textProvider;
  final bool enableWebViewConsoleLog;
}
