## 0.0.1

Initial release.

- Added `BookReaderPage`, a full-screen ebook reader widget backed by a local
  WebView renderer and Foliate.
- Supported opening books from a local file path or a host-provided
  `bookBytesLoader`.
- Added reader progress persistence through `ReaderProgressDelegate`.
- Added optional highlights and notes through `ReaderAnnotationDelegate`.
- Added `ReaderController` for external navigation, search, settings updates,
  and reader state observation.
- Added configurable reader settings, chrome builders, feature toggles,
  diagnostics reporting, search, translation hooks, and auto paging.
- Added English and Simplified Chinese documentation.
