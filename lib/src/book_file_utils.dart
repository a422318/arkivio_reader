String readerBookMimeType(
  String? format, {
  String? fileName,
  String? filePath,
}) {
  final normalized = format?.trim().toLowerCase();
  final inferred = normalized?.isNotEmpty == true
      ? normalized
      : readerBookExtension(fileName) ?? readerBookExtension(filePath);
  return switch (inferred) {
    'epub' => 'application/epub+zip',
    'mobi' => 'application/x-mobipocket-ebook',
    'azw3' || 'kf8' => 'application/vnd.amazon.ebook',
    'fb2' => 'application/x-fictionbook+xml',
    'fbz' || 'fb2.zip' => 'application/x-zip-compressed-fb2',
    'cbz' => 'application/vnd.comicbook+zip',
    'pdf' => 'application/pdf',
    'txt' || 'text' => 'text/plain',
    _ => 'application/octet-stream',
  };
}

String? readerBookExtension(String? path) {
  if (path == null || path.trim().isEmpty) {
    return null;
  }
  final name = path.trim().split(RegExp(r'[/\\]')).last;
  if (name.toLowerCase().endsWith('.fb2.zip')) {
    return 'fb2.zip';
  }
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) {
    return null;
  }
  return name.substring(dot + 1).toLowerCase();
}

const List<String> readerSupportedBookFormats = [
  'epub',
  'mobi',
  'azw3',
  'kf8',
  'pdf',
  'fb2',
  'fb2.zip',
  'fbz',
  'cbz',
  'txt',
];
