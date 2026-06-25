import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BookReaderAssetServer {
  BookReaderAssetServer._(this._server);

  final HttpServer _server;

  Uri get readerUri =>
      Uri.parse('http://127.0.0.1:${_server.port}/reader/reader.html');

  static Future<BookReaderAssetServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final assetServer = BookReaderAssetServer._(server);
    unawaited(assetServer._serve());
    return assetServer;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }
      final assetKey = readerAssetKeyForPath(request.uri.path);
      if (assetKey == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final data = await rootBundle.load(assetKey);
      response.headers
        ..contentType = readerContentTypeForAssetKey(assetKey)
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('Cross-Origin-Embedder-Policy', 'unsafe-none')
        ..set('Cross-Origin-Opener-Policy', 'unsafe-none');
      response.add(data.buffer.asUint8List());
    } on Exception {
      response.statusCode = HttpStatus.notFound;
    } finally {
      await response.close();
    }
  }
}

@visibleForTesting
String? readerAssetKeyForPath(String path) {
  final normalized = Uri.decodeComponent(path);
  if (!normalized.startsWith('/reader/')) {
    return null;
  }
  final relative = normalized.substring('/reader/'.length);
  if (!_isAllowedReaderAssetPath(relative)) {
    return null;
  }
  return 'packages/arkivio_reader/assets/reader/$relative';
}

@visibleForTesting
ContentType readerContentTypeForAssetKey(String assetKey) {
  final extension = assetKey.split('.').last.toLowerCase();
  return switch (extension) {
    'html' => ContentType.html,
    'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
    'css' => ContentType('text', 'css', charset: 'utf-8'),
    'png' => ContentType('image', 'png'),
    'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
    'svg' => ContentType('image', 'svg+xml'),
    'json' => ContentType.json,
    'wasm' => ContentType('application', 'wasm'),
    'ttf' => ContentType('font', 'ttf'),
    'otf' => ContentType('font', 'otf'),
    'woff' => ContentType('font', 'woff'),
    'woff2' => ContentType('font', 'woff2'),
    'pfb' => ContentType('application', 'octet-stream'),
    'map' => ContentType.json,
    _ => ContentType.binary,
  };
}

const Set<String> _allowedReaderAssetExtensions = {
  'bcmap',
  'css',
  'html',
  'js',
  'json',
  'jpeg',
  'jpg',
  'map',
  'mjs',
  'otf',
  'pfb',
  'png',
  'svg',
  'ttf',
  'wasm',
  'woff',
  'woff2',
};

bool _isAllowedReaderAssetPath(String relative) {
  if (relative.isEmpty || relative.startsWith('/') || relative.contains('..')) {
    return false;
  }
  final segments = relative.split('/');
  if (segments.any((segment) => segment.isEmpty || segment.startsWith('.'))) {
    return false;
  }
  final extension = relative.split('.').last.toLowerCase();
  if (!_allowedReaderAssetExtensions.contains(extension)) {
    return false;
  }
  return relative == 'reader.html' ||
      relative == 'reader-bootstrap.js' ||
      relative == 'mistdeer-reader.js' ||
      relative.startsWith('bg/') ||
      relative.startsWith('foliate-js/');
}
