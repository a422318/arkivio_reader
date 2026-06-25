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

  void _openBook(_ExampleBook book) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReaderExamplePage(book: book, store: _readerStore),
      ),
    );
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
                      onPressed: () => _openBook(book),
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
  const _BookListButton({required this.book, required this.onPressed});

  final _ExampleBook book;
  final VoidCallback onPressed;

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
              SizedBox(
                width: 58,
                child: Text(
                  book.format.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
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
