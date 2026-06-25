# Arkivio Reader

English | [简体中文](README.zh-CN.md)

A Flutter ebook reader widget backed by a local WebView renderer and Foliate.
It opens EPUB, MOBI, AZW3, PDF, FB2, CBZ, and text files from a local file path
or from bytes supplied by the host app.

## Quick Start

For the smallest integration, provide a book and either `filePath` or
`bookBytesLoader`. Progress, highlights, and notes are optional.

```dart
BookReaderPage(
  book: const ReaderBookItem(
    id: 'book-1',
    title: 'Example Book',
    format: 'epub',
    fileName: 'example.epub',
  ),
  bookBytesLoader: (_) async {
    final data = await rootBundle.load('assets/books/example.epub');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  },
)
```

If your book is already available as a local file, omit `bookBytesLoader` and
set `filePath` instead:

```dart
BookReaderPage(
  book: ReaderBookItem(
    id: 'book-1',
    filePath: localFile.path,
    title: 'Example Book',
    format: 'epub',
  ),
)
```

## Persistence

Progress and annotations are split so simple apps do not need to implement
methods they do not use.

Use `ReaderProgressDelegate` to restore and save the last reading location:

```dart
class MyProgressStore extends ReaderProgressDelegate {
  ReaderProgress? _progress;

  @override
  Future<ReaderProgress?> loadReadingProgress(String contentId) async {
    return _progress;
  }

  @override
  Future<ReaderProgress?> saveBookLocator({
    required String contentId,
    required double progress,
    required String locatorJson,
  }) async {
    return _progress = ReaderProgress(
      contentId: contentId,
      progress: progress,
      locatorJson: locatorJson,
    );
  }
}
```

Use `ReaderAnnotationDelegate` only when the app supports highlights or notes.
When no annotation delegate is supplied, the built-in annotation and note UI is
hidden automatically.

If you prefer one storage object, implement `ReaderContentDelegate` and pass the
same instance to both delegate slots:

```dart
final readerStore = MyReaderStore();

BookReaderPage(
  book: book,
  progressDelegate: readerStore,
  annotationDelegate: readerStore,
)
```

## Options

`ReaderOptions` groups optional behavior:

```dart
BookReaderPage(
  book: book,
  options: const ReaderOptions(
    features: ReaderFeatureOptions(
      search: true,
      annotations: false,
      notes: false,
      translation: false,
      autoPaging: true,
      backgroundImages: false,
    ),
  ),
)
```

Feature notes:

- `annotations` controls highlights.
- `notes` controls note creation and editing.
- `translation` also requires a `ReaderTranslationDelegate`; otherwise the
  translation buttons stay hidden.
- `backgroundImages: false` still allows plain background colors.

## Controller

Create a `ReaderController` when widgets outside the reader need to observe or
drive the page.

```dart
final controller = ReaderController();

BookReaderPage(
  book: book,
  controller: controller,
)

await controller.nextPage();
await controller.goToFraction(0.5);
controller.addListener(() {
  final state = controller.value;
  debugPrint('Progress: ${state.progress}');
});
```

Dispose controllers you own when the parent widget is disposed.

## Platform Notes

The reader serves its bundled WebView assets from a loopback HTTP server at
`127.0.0.1`. Android apps must allow local cleartext traffic in release builds:

```xml
<uses-permission android:name="android.permission.INTERNET"/>

<application
    android:usesCleartextTraffic="true"
    android:networkSecurityConfig="@xml/network_security_config">
</application>
```

The example app includes a `network_security_config.xml` that permits
`127.0.0.1`.

## Diagnostics

Use `ReaderDiagnosticsOptions.errorReporter` to collect structured errors from
the WebView bridge, asset server, storage delegates, and reader commands.

```dart
ReaderOptions(
  diagnostics: ReaderDiagnosticsOptions(
    errorReporter: (report) async {
      debugPrint('[${report.source}] ${report.error}');
    },
  ),
)
```

## Licenses

Bundled Foliate, PDF.js, CMap, and font license notices are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
