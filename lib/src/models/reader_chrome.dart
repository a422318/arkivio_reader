import 'package:flutter/widgets.dart';

import '../controller/reader_controller.dart';
import 'reader_settings.dart';

/// Public reader panels that can be selected or customized.
enum ReaderPanel { toc, annotations, progress, background, font }

enum ReaderHighlightStyle {
  highlight('highlight'),
  underline('underline'),
  squiggle('squiggle');

  const ReaderHighlightStyle(this.value);

  final String value;
}

enum ReaderTranslationStatus { idle, loading, success, error }

class ReaderTocEntry {
  const ReaderTocEntry({
    required this.label,
    required this.href,
    required this.depth,
  });

  final String label;
  final String href;
  final int depth;
}

class ReaderAnnotationEntry {
  const ReaderAnnotationEntry({
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
}

/// Context passed to custom reader chrome builders.
class ReaderChromeContext {
  const ReaderChromeContext({
    required this.controller,
    required this.state,
    required this.settings,
    required this.bottomBarHeight,
    required this.topPadding,
    required this.bottomPadding,
  });

  final ReaderController controller;
  final ReaderState state;
  final ReaderSettings settings;
  final double bottomBarHeight;
  final double topPadding;
  final double bottomPadding;
}

typedef ReaderChromeBuilder =
    Widget Function(BuildContext context, ReaderChromeContext reader);

typedef ReaderBarBuilder =
    Widget Function(BuildContext context, ReaderChromeContext reader);

typedef ReaderPanelBuilder =
    Widget Function(
      BuildContext context,
      ReaderChromeContext reader,
      ReaderPanel panel,
    );

/// Builder overrides for the reader's built-in chrome.
///
/// Use [chromeBuilder] to replace the whole overlay, [topBarBuilder] or
/// [bottomBarBuilder] to replace individual bars, and [panelBuilder] to replace
/// a specific panel.
class ReaderChromeBuilders {
  const ReaderChromeBuilders({
    this.chromeBuilder,
    this.topBarBuilder,
    this.bottomBarBuilder,
    this.panelBuilder,
  });

  final ReaderChromeBuilder? chromeBuilder;
  final ReaderBarBuilder? topBarBuilder;
  final ReaderBarBuilder? bottomBarBuilder;
  final ReaderPanelBuilder? panelBuilder;
}
