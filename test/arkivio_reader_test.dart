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
