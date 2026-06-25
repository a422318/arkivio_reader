import 'package:flutter_test/flutter_test.dart';

import 'package:arkivio_reader/arkivio_reader.dart';

void main() {
  test('ReaderController can be created through the public API', () async {
    final controller = ReaderController();

    expect(controller.value.loading, isTrue);
    await controller.nextPage();

    controller.dispose();
  });

  test('ReaderBookItem maps display metadata', () {
    const book = ReaderBookItem(id: 'book-1', fileName: 'book.epub');

    expect(book.displayTitle, 'book.epub');
    expect(book.filePath, isNull);
  });

  test('ReaderBookMetadata exposes cover bytes', () {
    final metadata = ReaderBookMetadata.fromMap({
      'title': 'Example',
      'author': 'Author',
      'coverDataUrl': 'data:image/png;base64,aGVsbG8=',
    });

    expect(metadata.title, 'Example');
    expect(metadata.author, 'Author');
    expect(metadata.coverMimeType, 'image/png');
    expect(metadata.coverBytes, [104, 101, 108, 108, 111]);

    final state = const ReaderState()
        .copyWith(bookMetadata: metadata)
        .copyWith(clearBookMetadata: true);

    expect(state.bookMetadata, isNull);
  });

  test('supported book formats are exposed', () {
    expect(
      readerSupportedBookFormats,
      containsAll(['epub', 'mobi', 'azw3', 'pdf', 'fb2', 'cbz', 'txt']),
    );
  });

  test('no-op delegates are safe defaults', () async {
    const progressDelegate = ReaderProgressDelegate.none();
    const annotationDelegate = ReaderAnnotationDelegate.none();

    expect(await progressDelegate.loadReadingProgress('book-1'), isNull);
    expect(
      await annotationDelegate.loadAnnotationsForPage('book:book-1'),
      isEmpty,
    );
  });
}
