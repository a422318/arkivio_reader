import '../reader_api.dart';

/// Error payload reported through [ReaderErrorReporter].
class ReaderErrorReport {
  const ReaderErrorReport({
    required this.error,
    required this.source,
    this.stackTrace,
    this.extra = const {},
    this.book,
  });

  final Object error;
  final StackTrace? stackTrace;
  final String source;
  final Map<String, Object?> extra;
  final ReaderBookItem? book;
}

typedef ReaderErrorReporter = Future<void> Function(ReaderErrorReport report);
typedef ReaderDiagnosticsTextProvider = Future<String> Function();
