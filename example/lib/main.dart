import 'package:arkivio_reader/arkivio_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arkivio Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff356c8c)),
        useMaterial3: true,
      ),
      home: const _BookLibraryPage(),
    );
  }
}

class _BookLibraryPage extends StatefulWidget {
  const _BookLibraryPage();

  @override
  State<_BookLibraryPage> createState() => _BookLibraryPageState();
}

class _BookLibraryPageState extends State<_BookLibraryPage> {
  final _readerStore = _InMemoryReaderStore();
  final Map<String, ReaderBookMetadata> _metadataByBookId = {};
  final Set<String> _loadingMetadataBookIds = {};
  final Map<String, String> _metadataErrorsByBookId = {};

  void _openBook(_ExampleBook book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReaderExamplePage(book: book, store: _readerStore),
      ),
    );
  }

  Future<void> _loadMetadata(_ExampleBook book) async {
    if (_loadingMetadataBookIds.contains(book.id)) {
      return;
    }
    setState(() {
      _loadingMetadataBookIds.add(book.id);
      _metadataErrorsByBookId.remove(book.id);
    });
    try {
      final metadata = await ReaderBookMetadataLoader.load(
        context,
        book: ReaderBookItem(
          id: book.id,
          title: book.title,
          format: book.format,
          fileName: book.fileName,
        ),
        metadataTimeout: const Duration(seconds: 120),
        bookBytesLoader: (_) async {
          final data = await rootBundle.load(book.assetPath);
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _metadataByBookId[book.id] = metadata;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _metadataErrorsByBookId[book.id] = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingMetadataBookIds.remove(book.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Arkivio Reader',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (final book in _exampleBooks) ...[
                    _BookListButton(
                      book: book,
                      metadata: _metadataByBookId[book.id],
                      metadataLoading: _loadingMetadataBookIds.contains(
                        book.id,
                      ),
                      metadataError: _metadataErrorsByBookId[book.id],
                      onPressed: () => _openBook(book),
                      onMetadataPressed: () => _loadMetadata(book),
                    ),
                    if (book != _exampleBooks.last) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookListButton extends StatelessWidget {
  const _BookListButton({
    required this.book,
    required this.onPressed,
    required this.onMetadataPressed,
    this.metadata,
    this.metadataLoading = false,
    this.metadataError,
  });

  final _ExampleBook book;
  final ReaderBookMetadata? metadata;
  final bool metadataLoading;
  final String? metadataError;
  final VoidCallback onPressed;
  final VoidCallback onMetadataPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _BookCoverPreview(book: book, metadata: metadata),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      metadata?.title ?? book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metadataError ??
                          metadata?.author ??
                          book.format.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: metadataError == null
                            ? colors.onSurfaceVariant
                            : colors.error,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 40,
                child: metadataLoading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: '预读取元数据',
                        onPressed: onMetadataPressed,
                        icon: Icon(
                          Icons.image_search,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCoverPreview extends StatelessWidget {
  const _BookCoverPreview({required this.book, this.metadata});

  final _ExampleBook book;
  final ReaderBookMetadata? metadata;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final coverBytes = metadata?.coverBytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 44,
        height: 58,
        color: colors.surface,
        alignment: Alignment.center,
        child: coverBytes == null
            ? Text(
                book.format.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              )
            : Image.memory(
                coverBytes,
                width: 44,
                height: 58,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Text(
                  book.format.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
      ),
    );
  }
}

class _ReaderExamplePage extends StatelessWidget {
  const _ReaderExamplePage({required this.book, required this.store});

  final _ExampleBook book;
  final _InMemoryReaderStore store;

  @override
  Widget build(BuildContext context) {
    return BookReaderPage(
      book: ReaderBookItem(
        id: book.id,
        title: book.title,
        format: book.format,
        fileName: book.fileName,
      ),
      bookBytesLoader: (_) async {
        final data = await rootBundle.load(book.assetPath);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      },
      progressDelegate: store,
      annotationDelegate: store,
      options: const ReaderOptions(
        chrome: ReaderChromeOptions(),
        behavior: ReaderBehaviorOptions(
          bookOpenTimeout: Duration(seconds: 120),
        ),
        diagnostics: ReaderDiagnosticsOptions(enableWebViewConsoleLog: true),
      ),
    );
  }
}

class _ExampleBook {
  const _ExampleBook({
    required this.assetPath,
    required this.title,
    required this.format,
  });

  final String assetPath;
  final String title;
  final String format;

  String get fileName => assetPath.split('/').last;

  String get id {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? fileName : fileName.substring(0, dot);
  }
}

const _exampleBooks = [
  _ExampleBook(
    assetPath: 'assets/books/818461aad1c6ab23403fc95519e103c5.epub',
    title: 'EPUB 示例书籍',
    format: 'epub',
  ),
  _ExampleBook(
    assetPath: 'assets/books/763e5033d4ae21cf21d9d31c7aeaac95.mobi',
    title: 'MOBI 示例书籍',
    format: 'mobi',
  ),
  _ExampleBook(
    assetPath: 'assets/books/5aa15eb2cdff50b64fcd16aaef7f2090.azw3',
    title: 'AZW3 示例书籍',
    format: 'azw3',
  ),
  _ExampleBook(
    assetPath: 'assets/books/6730e7285995224b67960f1803c6121c.pdf',
    title: 'PDF 示例书籍',
    format: 'pdf',
  ),
];

class _InMemoryReaderStore extends ReaderContentDelegate {
  final Map<String, ReaderProgress> _progressByContentId = {};
  final Map<String, List<_StoredAnnotation>> _annotationsByPageUrl = {};

  @override
  Future<ReaderProgress?> loadReadingProgress(String contentId) async {
    return _progressByContentId[contentId];
  }

  @override
  Future<ReaderProgress?> saveBookLocator({
    required String contentId,
    required double progress,
    required String locatorJson,
  }) async {
    final next = ReaderProgress(
      contentId: contentId,
      progress: progress,
      locatorJson: locatorJson,
    );
    _progressByContentId[contentId] = next;
    return next;
  }

  @override
  Future<List<ReaderAnnotation>> loadAnnotationsForPage(String pageUrl) async {
    final annotations = _annotationsByPageUrl[pageUrl] ?? const [];
    return [
      for (final a in annotations)
        ReaderAnnotation(
          locatorValue: a.locatorValue,
          text: a.text,
          note: a.note,
          style: a.style,
          type: a.type,
          color: a.color,
          updatedAt: a.updatedAt,
        ),
    ];
  }

  @override
  Future<void> createAnnotation(ReaderAnnotationDraft draft) async {
    final annotations = _annotationsByPageUrl.putIfAbsent(
      draft.pageUrl,
      () => [],
    );
    annotations.add(
      _StoredAnnotation(
        locatorValue: draft.locatorValue ?? '',
        text: draft.text,
        note: draft.note,
        style: draft.style ?? 'highlight',
        type: draft.type,
        color: draft.color,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateAnnotationByLocator({
    required String pageUrl,
    required String locatorValue,
    required String type,
    required String style,
    required String color,
  }) async {
    final annotations = _annotationsByPageUrl[pageUrl];
    if (annotations == null) {
      return;
    }
    final index = annotations.indexWhere((a) => a.locatorValue == locatorValue);
    if (index >= 0) {
      final old = annotations[index];
      annotations[index] = _StoredAnnotation(
        locatorValue: locatorValue,
        text: old.text,
        note: old.note,
        style: style,
        type: type,
        color: color,
        updatedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> updateAnnotationNoteByLocator({
    required String pageUrl,
    required String locatorValue,
    required String note,
  }) async {
    final annotations = _annotationsByPageUrl[pageUrl];
    if (annotations == null) {
      return;
    }
    final index = annotations.indexWhere((a) => a.locatorValue == locatorValue);
    if (index >= 0) {
      final old = annotations[index];
      annotations[index] = _StoredAnnotation(
        locatorValue: locatorValue,
        text: old.text,
        note: note,
        style: old.style,
        type: old.type,
        color: old.color,
        updatedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> deleteAnnotationByLocator({
    required String pageUrl,
    required String locatorValue,
  }) async {
    _annotationsByPageUrl[pageUrl]?.removeWhere(
      (a) => a.locatorValue == locatorValue,
    );
  }
}

class _StoredAnnotation {
  const _StoredAnnotation({
    required this.locatorValue,
    required this.text,
    required this.note,
    required this.style,
    required this.type,
    required this.color,
    required this.updatedAt,
  });

  final String locatorValue;
  final String text;
  final String note;
  final String style;
  final String? type;
  final String? color;
  final DateTime updatedAt;
}
