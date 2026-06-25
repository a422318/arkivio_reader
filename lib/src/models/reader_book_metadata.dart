import 'dart:convert';
import 'dart:typed_data';

/// Metadata extracted from the opened book file.
class ReaderBookMetadata {
  const ReaderBookMetadata({
    this.title,
    this.author,
    this.publisher,
    this.language,
    this.description,
    this.identifier,
    this.subject,
    this.source,
    this.rights,
    this.published,
    this.modified,
    this.coverDataUrl,
  });

  factory ReaderBookMetadata.fromMap(Map<String, Object?> data) {
    String? readString(String key) {
      final value = data[key];
      if (value == null) {
        return null;
      }
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return ReaderBookMetadata(
      title: readString('title'),
      author: readString('author'),
      publisher: readString('publisher'),
      language: readString('language'),
      description: readString('description'),
      identifier: readString('identifier'),
      subject: readString('subject'),
      source: readString('source'),
      rights: readString('rights'),
      published: readString('published'),
      modified: readString('modified'),
      coverDataUrl: readString('coverDataUrl'),
    );
  }

  final String? title;
  final String? author;
  final String? publisher;
  final String? language;
  final String? description;
  final String? identifier;
  final String? subject;
  final String? source;
  final String? rights;
  final String? published;
  final String? modified;

  /// Cover image as a data URL, for example `data:image/jpeg;base64,...`.
  final String? coverDataUrl;

  /// MIME type parsed from [coverDataUrl], if present.
  String? get coverMimeType {
    final dataUrl = coverDataUrl;
    if (dataUrl == null || !dataUrl.startsWith('data:')) {
      return null;
    }
    final separator = dataUrl.indexOf(';');
    if (separator <= 5) {
      return null;
    }
    return dataUrl.substring(5, separator);
  }

  /// Cover image bytes decoded from [coverDataUrl], if it is base64 encoded.
  Uint8List? get coverBytes {
    final dataUrl = coverDataUrl;
    if (dataUrl == null || !dataUrl.startsWith('data:')) {
      return null;
    }
    final comma = dataUrl.indexOf(',');
    if (comma < 0) {
      return null;
    }
    final metadata = dataUrl.substring(5, comma).toLowerCase();
    if (!metadata.contains(';base64')) {
      return null;
    }
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'author': author,
      'publisher': publisher,
      'language': language,
      'description': description,
      'identifier': identifier,
      'subject': subject,
      'source': source,
      'rights': rights,
      'published': published,
      'modified': modified,
      'coverDataUrl': coverDataUrl,
    };
  }
}
