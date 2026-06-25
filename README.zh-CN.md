# Arkivio Reader

[English](README.md) | 简体中文

Arkivio Reader 是一个 Flutter 电子书阅读器组件，底层使用本地 WebView
和 Foliate 渲染。它支持从本地文件路径或宿主应用提供的 bytes 打开 EPUB、
MOBI、AZW3、PDF、FB2、CBZ 和纯文本文件。

## 快速开始

最小接入只需要提供一本书，以及 `filePath` 或 `bookBytesLoader` 其中之一。
阅读进度、划线和笔记都是可选能力。

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

如果书籍已经是本地文件，可以省略 `bookBytesLoader`，直接设置 `filePath`：

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

## 持久化

阅读进度和批注能力已经拆开，简单应用不需要实现自己不用的方法。

使用 `ReaderProgressDelegate` 恢复和保存阅读位置：

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

只有当应用支持划线或笔记时，才需要实现 `ReaderAnnotationDelegate`。
如果没有传入批注 delegate，内置划线和笔记 UI 会自动隐藏。

如果你更希望用一个对象统一管理存储，可以实现 `ReaderContentDelegate`，
并把同一个实例同时传给两个 delegate 参数：

```dart
final readerStore = MyReaderStore();

BookReaderPage(
  book: book,
  progressDelegate: readerStore,
  annotationDelegate: readerStore,
)
```

## 配置

`ReaderOptions` 用于集中配置阅读器行为：

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

功能开关说明：

- `annotations` 控制划线能力。
- `notes` 控制笔记创建和编辑能力。
- `translation` 还需要同时传入 `ReaderTranslationDelegate`，否则翻译按钮会隐藏。
- `backgroundImages: false` 只会隐藏背景图片选项，纯色背景仍可使用。

## 控制器

当阅读器外部的 widget 需要监听状态或控制阅读器时，可以创建
`ReaderController`。

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

如果 controller 由父组件持有，请在父组件销毁时 dispose。

## 平台注意事项

阅读器会通过 `127.0.0.1` 上的本地 HTTP server 为 WebView 提供内置资源。
Android 应用在 release 构建中需要允许本地明文流量：

```xml
<uses-permission android:name="android.permission.INTERNET"/>

<application
    android:usesCleartextTraffic="true"
    android:networkSecurityConfig="@xml/network_security_config">
</application>
```

example 应用已经包含允许 `127.0.0.1` 的 `network_security_config.xml`。

## 诊断

使用 `ReaderDiagnosticsOptions.errorReporter` 可以收集来自 WebView bridge、
资源服务、存储 delegate 和阅读器命令的结构化错误。

```dart
ReaderOptions(
  diagnostics: ReaderDiagnosticsOptions(
    errorReporter: (report) async {
      debugPrint('[${report.source}] ${report.error}');
    },
  ),
)
```

## 授权

随包分发的 Foliate、PDF.js、CMap 和字体授权说明见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
