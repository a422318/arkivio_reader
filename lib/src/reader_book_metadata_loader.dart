import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';

import 'book_file_utils.dart';
import 'book_reader_asset_server.dart';
import 'reader_api.dart';

/// Loads book metadata before opening [BookReaderPage].
///
/// The loader uses the same bundled Foliate parser as the reader. It inserts a
/// temporary hidden WebView into the nearest overlay, extracts metadata, then
/// removes the WebView automatically.
class ReaderBookMetadataLoader {
  const ReaderBookMetadataLoader._();

  static Future<ReaderBookMetadata> load(
    BuildContext context, {
    required ReaderBookItem book,
    ReaderBookBytesLoader? bookBytesLoader,
    bool includeCover = true,
    Duration readyTimeout = const Duration(seconds: 15),
    Duration metadataTimeout = const Duration(seconds: 60),
  }) {
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    if (overlay == null) {
      return Future.error(
        StateError('ReaderBookMetadataLoader requires an Overlay in context.'),
      );
    }

    final completer = Completer<ReaderBookMetadata>();
    late final OverlayEntry entry;
    var removed = false;

    void removeEntry() {
      if (removed) {
        return;
      }
      removed = true;
      entry.remove();
    }

    void complete(ReaderBookMetadata metadata) {
      if (!completer.isCompleted) {
        completer.complete(metadata);
      }
      removeEntry();
    }

    void completeError(Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      removeEntry();
    }

    entry = OverlayEntry(
      builder: (_) {
        return Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.01,
              child: _ReaderBookMetadataLoaderHost(
                book: book,
                bookBytesLoader: bookBytesLoader,
                includeCover: includeCover,
                readyTimeout: readyTimeout,
                metadataTimeout: metadataTimeout,
                onLoaded: complete,
                onError: completeError,
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    return completer.future.whenComplete(removeEntry);
  }
}

class _ReaderBookMetadataLoaderHost extends StatefulWidget {
  const _ReaderBookMetadataLoaderHost({
    required this.book,
    required this.includeCover,
    required this.readyTimeout,
    required this.metadataTimeout,
    required this.onLoaded,
    required this.onError,
    this.bookBytesLoader,
  });

  final ReaderBookItem book;
  final ReaderBookBytesLoader? bookBytesLoader;
  final bool includeCover;
  final Duration readyTimeout;
  final Duration metadataTimeout;
  final ValueChanged<ReaderBookMetadata> onLoaded;
  final void Function(Object error, StackTrace stackTrace) onError;

  @override
  State<_ReaderBookMetadataLoaderHost> createState() =>
      _ReaderBookMetadataLoaderHostState();
}

class _ReaderBookMetadataLoaderHostState
    extends State<_ReaderBookMetadataLoaderHost> {
  late final WebViewController _controller;
  BookReaderAssetServer? _assetServer;
  Timer? _readyTimer;
  Timer? _metadataTimer;
  bool _bookSent = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'MistdeerReader',
        onMessageReceived: (message) =>
            unawaited(_handleReaderMessage(message.message)),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _fail(StateError(error.description));
            }
          },
        ),
      );
    unawaited(_load());
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    _metadataTimer?.cancel();
    unawaited(_assetServer?.close());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final server = await BookReaderAssetServer.start();
      if (!mounted || _finished) {
        unawaited(server.close());
        return;
      }
      _assetServer = server;
      await _controller.loadRequest(server.readerUri);
      _startReadyTimer();
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _startReadyTimer() {
    _readyTimer?.cancel();
    _readyTimer = Timer(widget.readyTimeout, () {
      _fail(
        TimeoutException(
          'Reader metadata bridge did not become ready.',
          widget.readyTimeout,
        ),
      );
    });
  }

  void _startMetadataTimer() {
    _metadataTimer?.cancel();
    _metadataTimer = Timer(widget.metadataTimeout, () {
      _fail(
        TimeoutException(
          'Book metadata did not finish loading.',
          widget.metadataTimeout,
        ),
      );
    });
  }

  Future<void> _openBookMetadata() async {
    if (_bookSent || _finished) {
      return;
    }
    _bookSent = true;
    try {
      final bytes = await _loadBookBytes();
      final payload = jsonEncode({
        'id': widget.book.id,
        'title': widget.book.title ?? widget.book.fileName,
        'format': widget.book.format,
        'fileName': widget.book.fileName,
        'mimeType': readerBookMimeType(
          widget.book.format,
          fileName: widget.book.fileName,
          filePath: widget.book.filePath,
        ),
        'includeCover': widget.includeCover,
      });
      final base64Content = base64Encode(bytes);
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.beginBook($payload);',
      );
      const chunkSize = 512 * 1024;
      for (var offset = 0; offset < base64Content.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, base64Content.length);
        final chunk = jsonEncode(base64Content.substring(offset, end));
        await _controller.runJavaScript(
          'window.MistdeerReaderBridge?.appendBookChunk($chunk);',
        );
      }
      _startMetadataTimer();
      await _controller.runJavaScript(
        'window.MistdeerReaderBridge?.loadMetadata();',
      );
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  Future<Uint8List> _loadBookBytes() async {
    final loader = widget.bookBytesLoader;
    if (loader != null) {
      return loader(widget.book);
    }
    final filePath = widget.book.filePath;
    if (filePath == null || filePath.isEmpty) {
      throw StateError(
        'Book filePath is required when bookBytesLoader is null.',
      );
    }
    final file = File(filePath);
    if (!file.existsSync()) {
      throw StateError('Book file does not exist: $filePath');
    }
    return file.readAsBytes();
  }

  Future<void> _handleReaderMessage(String message) async {
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) {
        return;
      }
      final type = decoded['type']?.toString();
      if (type == 'ready') {
        _readyTimer?.cancel();
        await _openBookMetadata();
        return;
      }
      if (type == 'metadataLoaded') {
        _metadataTimer?.cancel();
        final metadata = _metadataFromMessage(decoded['metadata']);
        if (metadata == null) {
          _fail(StateError('Reader metadata payload is empty.'));
          return;
        }
        _finished = true;
        widget.onLoaded(metadata);
        return;
      }
      if (type == 'error') {
        _fail(StateError(decoded['message']?.toString() ?? 'Metadata failed.'));
      }
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  ReaderBookMetadata? _metadataFromMessage(Object? value) {
    if (value is! Map) {
      return null;
    }
    return ReaderBookMetadata.fromMap({
      for (final entry in value.entries) entry.key.toString(): entry.value,
    });
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    if (_finished) {
      return;
    }
    _finished = true;
    _readyTimer?.cancel();
    _metadataTimer?.cancel();
    widget.onError(error, stackTrace ?? StackTrace.current);
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
