part of 'book_reader_page.dart';

String _bookMimeType(String? format, {String? fileName, String? filePath}) {
  final normalized = format?.trim().toLowerCase();
  final inferred = normalized?.isNotEmpty == true
      ? normalized
      : _bookExtension(fileName) ?? _bookExtension(filePath);
  return switch (inferred) {
    'epub' => 'application/epub+zip',
    'mobi' => 'application/x-mobipocket-ebook',
    'azw3' => 'application/vnd.amazon.ebook',
    'fb2' => 'application/x-fictionbook+xml',
    'cbz' => 'application/vnd.comicbook+zip',
    'pdf' => 'application/pdf',
    'txt' || 'text' => 'text/plain',
    _ => 'application/octet-stream',
  };
}

String? _bookExtension(String? path) {
  if (path == null || path.trim().isEmpty) {
    return null;
  }
  final name = path.trim().split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) {
    return null;
  }
  return name.substring(dot + 1).toLowerCase();
}

enum _ReaderPanel {
  toc(LucideIcons.listTree, '目录'),
  annotations(LucideIcons.highlighter, '批注'),
  progress(LucideIcons.chartNoAxesColumnIncreasing, '进度'),
  background(LucideIcons.palette, '背景色'),
  font(LucideIcons.type, '字体设置');

  const _ReaderPanel(this.icon, this.label);

  final IconData icon;
  final String label;

  ReaderPanel toPublic() {
    return switch (this) {
      _ReaderPanel.toc => ReaderPanel.toc,
      _ReaderPanel.annotations => ReaderPanel.annotations,
      _ReaderPanel.progress => ReaderPanel.progress,
      _ReaderPanel.background => ReaderPanel.background,
      _ReaderPanel.font => ReaderPanel.font,
    };
  }

  static _ReaderPanel fromPublic(ReaderPanel panel) {
    return switch (panel) {
      ReaderPanel.toc => _ReaderPanel.toc,
      ReaderPanel.annotations => _ReaderPanel.annotations,
      ReaderPanel.progress => _ReaderPanel.progress,
      ReaderPanel.background => _ReaderPanel.background,
      ReaderPanel.font => _ReaderPanel.font,
    };
  }
}

enum _ReaderHighlightStyle {
  highlight('highlight'),
  underline('underline'),
  squiggle('squiggle');

  const _ReaderHighlightStyle(this.jsValue);

  final String jsValue;

  static _ReaderHighlightStyle fromValue(String? value) {
    if (value == 'wavy' || value == 'squiggly') {
      return _ReaderHighlightStyle.squiggle;
    }
    for (final style in values) {
      if (style.jsValue == value) {
        return style;
      }
    }
    return _ReaderHighlightStyle.highlight;
  }
}

enum _ReaderTranslationStatus { idle, loading, success, error }

extension _ReaderTranslationStatusPublic on _ReaderTranslationStatus {
  ReaderTranslationStatus toPublic() {
    return switch (this) {
      _ReaderTranslationStatus.idle => ReaderTranslationStatus.idle,
      _ReaderTranslationStatus.loading => ReaderTranslationStatus.loading,
      _ReaderTranslationStatus.success => ReaderTranslationStatus.success,
      _ReaderTranslationStatus.error => ReaderTranslationStatus.error,
    };
  }
}

class _ReaderParagraph {
  const _ReaderParagraph({
    required this.text,
    required this.index,
    this.tag = 'p',
  });

  final String text;
  final int index;
  final String tag;

  static List<_ReaderParagraph> fromJsonList(Object? data) {
    if (data is! List) {
      return [];
    }
    return data
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => _ReaderParagraph(
            text: item['text']?.toString() ?? '',
            index: item['index'] as int? ?? 0,
            tag: item['tag']?.toString() ?? 'p',
          ),
        )
        .where((p) => p.text.isNotEmpty)
        .toList();
  }
}

class _ReaderChapterText {
  const _ReaderChapterText({
    required this.key,
    required this.text,
    this.href = '',
    this.title = '',
    this.paragraphs = const [],
  });

  final String key;
  final String href;
  final String title;
  final String text;
  final List<_ReaderParagraph> paragraphs;

  static _ReaderChapterText? fromReaderResult(Object? result) {
    var decoded = result;
    for (var i = 0; i < 2 && decoded is String; i++) {
      final text = decoded.trim();
      if (text.isEmpty || text == 'null') {
        return null;
      }
      decoded = jsonDecode(text);
    }
    if (decoded is! Map) {
      return null;
    }
    final key = decoded['key']?.toString().trim() ?? '';

    // 解析段落数组（新格式）
    final paragraphs = _ReaderParagraph.fromJsonList(decoded['paragraphs']);

    // 向后兼容：如果有 paragraphs 用它，否则用 text
    final text = paragraphs.isNotEmpty
        ? paragraphs.map((p) => p.text).join('\n\n')
        : (decoded['text']?.toString().trim() ?? '');

    if (key.isEmpty || (text.isEmpty && paragraphs.isEmpty)) {
      return null;
    }

    return _ReaderChapterText(
      key: key,
      href: decoded['href']?.toString() ?? '',
      title: decoded['title']?.toString() ?? '',
      text: text,
      paragraphs: paragraphs,
    );
  }
}

class _ReaderHighlightColorOption {
  const _ReaderHighlightColorOption({required this.hex, required this.color});

  final String hex;
  final Color color;
}

const _readerHighlightColors = <_ReaderHighlightColorOption>[
  _ReaderHighlightColorOption(hex: '#ffd54f', color: Color(0xffffd54f)),
  _ReaderHighlightColorOption(hex: '#81c784', color: Color(0xff81c784)),
  _ReaderHighlightColorOption(hex: '#64b5f6', color: Color(0xff64b5f6)),
  _ReaderHighlightColorOption(hex: '#f48fb1', color: Color(0xfff48fb1)),
  _ReaderHighlightColorOption(hex: '#b39ddb', color: Color(0xffb39ddb)),
];

_ReaderHighlightColorOption _readerHighlightColorByHex(String? hex) {
  final normalized = hex?.trim().toLowerCase();
  for (final option in _readerHighlightColors) {
    if (option.hex == normalized) {
      return option;
    }
  }
  return _readerHighlightColors.first;
}

class _ReaderActiveHighlight {
  const _ReaderActiveHighlight({
    required this.value,
    required this.text,
    required this.style,
    required this.colorHex,
  });

  final String value;
  final String text;
  final _ReaderHighlightStyle style;
  final String colorHex;

  _ReaderActiveHighlight copyWith({
    _ReaderHighlightStyle? style,
    String? colorHex,
  }) {
    return _ReaderActiveHighlight(
      value: value,
      text: text,
      style: style ?? this.style,
      colorHex: colorHex ?? this.colorHex,
    );
  }
}

class _ReaderSelectionAnnotation {
  const _ReaderSelectionAnnotation({
    required this.value,
    required this.text,
    this.note = '',
  });

  final String value;
  final String text;
  final String note;

  static _ReaderSelectionAnnotation? fromReaderResult(Object? result) {
    var decoded = result;
    for (var i = 0; i < 2 && decoded is String; i++) {
      final text = decoded.trim();
      if (text.isEmpty || text == 'null') {
        return null;
      }
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        break;
      }
    }
    final data = decoded is Map ? decoded.cast<String, dynamic>() : null;
    final value = data?['value']?.toString() ?? '';
    final text = data?['text']?.toString() ?? '';
    if (value.isEmpty || text.trim().isEmpty) {
      return null;
    }
    return _ReaderSelectionAnnotation(
      value: value,
      text: text,
      note: data?['note']?.toString() ?? '',
    );
  }
}

class _ReaderSelectedAnnotation {
  const _ReaderSelectedAnnotation({
    required this.value,
    required this.text,
    required this.note,
    required this.style,
    required this.colorHex,
    required this.selection,
  });

  final String value;
  final String text;
  final String note;
  final String style;
  final String colorHex;
  final _ReaderTextSelection selection;

  bool get isNote => style == 'note';

  static _ReaderSelectedAnnotation? fromMessage(Map<dynamic, dynamic> message) {
    final annotation = message['annotation'];
    if (annotation is! Map) {
      return null;
    }
    final value = annotation['value']?.toString() ?? '';
    if (value.isEmpty) {
      return null;
    }
    final selection = _ReaderTextSelection.fromMessage(message);
    if (selection == null) {
      return null;
    }
    final style =
        annotation['style']?.toString() ??
        annotation['type']?.toString() ??
        'highlight';
    return _ReaderSelectedAnnotation(
      value: value,
      text: annotation['text']?.toString() ?? selection.text,
      note: annotation['note']?.toString() ?? '',
      style: style,
      colorHex: annotation['color']?.toString() ?? '#ffd54f',
      selection: selection,
    );
  }
}

class _ReaderAnnotationItem {
  const _ReaderAnnotationItem({
    required this.locatorValue,
    required this.text,
    required this.note,
    required this.style,
    required this.colorHex,
    required this.chapterLabel,
    required this.updatedAt,
  });

  final String locatorValue;
  final String text;
  final String note;
  final String style;
  final String colorHex;
  final String chapterLabel;
  final DateTime? updatedAt;

  bool get isNote => style == 'note' || note.trim().isNotEmpty;

  _ReaderAnnotationItem copyWith({String? chapterLabel}) {
    return _ReaderAnnotationItem(
      locatorValue: locatorValue,
      text: text,
      note: note,
      style: style,
      colorHex: colorHex,
      chapterLabel: chapterLabel ?? this.chapterLabel,
      updatedAt: updatedAt,
    );
  }

  static _ReaderAnnotationItem? fromAnnotation(ReaderAnnotation annotation) {
    final locatorValue = annotation.locatorValue;
    final text = annotation.text;
    if (locatorValue.isEmpty || text.trim().isEmpty) {
      return null;
    }
    return _ReaderAnnotationItem(
      locatorValue: locatorValue,
      text: text,
      note: annotation.note,
      style: annotation.style,
      colorHex: annotation.color ?? _readerHighlightColors.first.hex,
      chapterLabel: '未知章节',
      updatedAt: annotation.updatedAt,
    );
  }
}

class _ReaderSearchChapter {
  const _ReaderSearchChapter({required this.label, required this.items});

  final String label;
  final List<_ReaderSearchItem> items;

  static _ReaderSearchChapter? fromMessage(Object? value) {
    if (value is! Map) {
      return null;
    }
    final chapter = _ReaderSearchChapter(
      label: value['label']?.toString() ?? '',
      items: _ReaderSearchItem.parseList(value['items']),
    );
    if (chapter.items.isEmpty) {
      return null;
    }
    return chapter;
  }

  static List<_ReaderSearchChapter> parseList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [for (final item in value) ?_ReaderSearchChapter.fromMessage(item)];
  }
}

class _ReaderSearchItem {
  const _ReaderSearchItem({
    required this.cfi,
    required this.pre,
    required this.match,
    required this.post,
  });

  final String cfi;
  final String pre;
  final String match;
  final String post;

  static List<_ReaderSearchItem> parseList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return [
      for (final item in value)
        if (item is Map)
          _ReaderSearchItem(
            cfi: item['cfi']?.toString() ?? '',
            pre: item['pre']?.toString() ?? '',
            match: item['match']?.toString() ?? '',
            post: item['post']?.toString() ?? '',
          ),
    ].where((item) => item.cfi.isNotEmpty).toList();
  }
}

const double kAutoPageBaseSeconds = 12;
const double kAutoScrollBasePxPerSecond = 40;

Duration autoPageInterval(double speed) {
  final clamped = speed.clamp(readerAutoPageSpeedMin, readerAutoPageSpeedMax);
  final ms = (kAutoPageBaseSeconds / clamped * 1000).round();
  return Duration(milliseconds: ms);
}

class _ReaderTocItem {
  const _ReaderTocItem({
    required this.label,
    required this.href,
    required this.depth,
  });

  final String label;
  final String href;
  final int depth;

  static List<_ReaderTocItem> parseList(Object? raw) {
    final items = raw is List ? raw : const <Object?>[];
    final results = <_ReaderTocItem>[];
    void append(Object? value, int depth) {
      if (value is! Map) {
        return;
      }
      final label = value['label']?.toString().trim() ?? '';
      final href = value['href']?.toString().trim() ?? '';
      if (label.isNotEmpty || href.isNotEmpty) {
        results.add(_ReaderTocItem(label: label, href: href, depth: depth));
      }
      final children = value['children'];
      if (children is List) {
        for (final child in children) {
          append(child, depth + 1);
        }
      }
    }

    for (final item in items) {
      append(item, 0);
    }
    return results;
  }
}
