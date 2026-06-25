import 'dart:typed_data';

export 'controller/reader_controller.dart';
export 'models/reader_book_metadata.dart';
export 'models/reader_chrome.dart';
export 'models/reader_diagnostics.dart';
export 'models/reader_options.dart';
export 'models/reader_settings.dart';
export 'storage/reader_settings_store.dart';

/// Metadata and local file information for a book opened by the reader.
class ReaderBookItem {
  const ReaderBookItem({
    required this.id,
    this.filePath,
    this.title,
    this.format,
    this.fileName,
  });

  factory ReaderBookItem.fromMap(Map<String, dynamic> data) {
    final filePath = data['filePath']?.toString().trim();
    return ReaderBookItem(
      id: data['id']?.toString() ?? '',
      filePath: filePath == null || filePath.isEmpty ? null : filePath,
      title: data['title']?.toString(),
      format: data['format']?.toString(),
      fileName: data['fileName']?.toString(),
    );
  }

  final String id;

  /// Local file path used when [BookReaderPage.bookBytesLoader] is omitted.
  ///
  /// This can be null when the host provides bytes through
  /// [BookReaderPage.bookBytesLoader].
  final String? filePath;
  final String? title;
  final String? format;
  final String? fileName;

  String get displayTitle => title ?? fileName ?? '';
}

/// Persisted progress information returned by [ReaderProgressDelegate].
class ReaderProgress {
  const ReaderProgress({
    required this.contentId,
    required this.progress,
    this.locatorJson,
    this.updatedAt,
  });

  factory ReaderProgress.fromMap(Map<String, dynamic> data) {
    return ReaderProgress(
      contentId: data['contentId']?.toString() ?? '',
      progress: ((data['progress'] as num?)?.toDouble() ?? 0)
          .clamp(0, 1)
          .toDouble(),
      locatorJson: data['locatorJson']?.toString(),
      updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? ''),
    );
  }

  final String contentId;
  final double progress;
  final String? locatorJson;
  final DateTime? updatedAt;
}

/// Draft annotation data emitted when the reader creates a new annotation.
class ReaderAnnotationDraft {
  const ReaderAnnotationDraft({
    required this.type,
    required this.text,
    required this.note,
    required this.pageUrl,
    required this.pageTitle,
    this.locatorValue,
    this.style,
    this.color,
  });

  final String type;
  final String text;
  final String note;
  final String pageUrl;
  final String pageTitle;
  final String? locatorValue;
  final String? style;
  final String? color;
}

/// Annotation data loaded from the host application.
class ReaderAnnotation {
  const ReaderAnnotation({
    required this.locatorValue,
    required this.text,
    this.note = '',
    this.style = 'highlight',
    this.type,
    this.color,
    this.updatedAt,
  });

  factory ReaderAnnotation.fromMap(Map<String, dynamic> data) {
    return ReaderAnnotation(
      locatorValue: data['locatorValue']?.toString() ?? '',
      text: data['text']?.toString() ?? '',
      note: data['note']?.toString() ?? '',
      style:
          data['style']?.toString() ?? data['type']?.toString() ?? 'highlight',
      type: data['type']?.toString(),
      color: data['color']?.toString(),
      updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? ''),
    );
  }

  final String locatorValue;
  final String text;
  final String note;
  final String style;
  final String? type;
  final String? color;
  final DateTime? updatedAt;
}

/// Host application bridge for loading and saving reading progress.
abstract class ReaderProgressDelegate {
  const ReaderProgressDelegate();

  const factory ReaderProgressDelegate.none() = NoopReaderProgressDelegate;

  /// Loads the last saved reading progress for [contentId].
  Future<ReaderProgress?> loadReadingProgress(String contentId);

  /// Persists the current locator and fractional progress.
  Future<ReaderProgress?> saveBookLocator({
    required String contentId,
    required double progress,
    required String locatorJson,
  });
}

/// No-op progress delegate for apps that do not need progress persistence.
class NoopReaderProgressDelegate extends ReaderProgressDelegate {
  const NoopReaderProgressDelegate();

  @override
  Future<ReaderProgress?> loadReadingProgress(String contentId) async => null;

  @override
  Future<ReaderProgress?> saveBookLocator({
    required String contentId,
    required double progress,
    required String locatorJson,
  }) async {
    return ReaderProgress(
      contentId: contentId,
      progress: progress,
      locatorJson: locatorJson,
    );
  }
}

/// Host application bridge for highlights and notes.
abstract class ReaderAnnotationDelegate {
  const ReaderAnnotationDelegate();

  const factory ReaderAnnotationDelegate.none() = NoopReaderAnnotationDelegate;

  /// Loads annotations associated with [pageUrl].
  Future<List<ReaderAnnotation>> loadAnnotationsForPage(String pageUrl);

  /// Creates an annotation from reader-selected text.
  Future<void> createAnnotation(ReaderAnnotationDraft draft);

  /// Updates an existing annotation style/color identified by locator.
  Future<void> updateAnnotationByLocator({
    required String pageUrl,
    required String locatorValue,
    required String type,
    required String style,
    required String color,
  });

  /// Updates an existing annotation note identified by locator.
  Future<void> updateAnnotationNoteByLocator({
    required String pageUrl,
    required String locatorValue,
    required String note,
  });

  /// Deletes an annotation identified by locator.
  Future<void> deleteAnnotationByLocator({
    required String pageUrl,
    required String locatorValue,
  });
}

/// No-op annotation delegate for apps that do not need highlights or notes.
class NoopReaderAnnotationDelegate extends ReaderAnnotationDelegate {
  const NoopReaderAnnotationDelegate();

  @override
  Future<List<ReaderAnnotation>> loadAnnotationsForPage(String pageUrl) async {
    return const [];
  }

  @override
  Future<void> createAnnotation(ReaderAnnotationDraft draft) async {}

  @override
  Future<void> updateAnnotationByLocator({
    required String pageUrl,
    required String locatorValue,
    required String type,
    required String style,
    required String color,
  }) async {}

  @override
  Future<void> updateAnnotationNoteByLocator({
    required String pageUrl,
    required String locatorValue,
    required String note,
  }) async {}

  @override
  Future<void> deleteAnnotationByLocator({
    required String pageUrl,
    required String locatorValue,
  }) async {}
}

/// Convenience bridge for apps that prefer one object for progress and notes.
abstract class ReaderContentDelegate
    implements ReaderProgressDelegate, ReaderAnnotationDelegate {
  const ReaderContentDelegate();
}

/// Optional host application translation bridge.
abstract class ReaderTranslationDelegate {
  /// Translates a single selected text fragment.
  Future<String> translate(String content);

  /// Translates a batch of paragraphs for chapter translation.
  Future<List<String>> translateBatch(List<String> paragraphs);
}

typedef ReaderBookBytesLoader = Future<Uint8List> Function(ReaderBookItem book);
