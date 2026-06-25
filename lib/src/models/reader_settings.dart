enum ReaderFontStyle {
  system('默认', 'system'),
  sans('黑体', 'sans'),
  serif('宋体', 'serif'),
  kai('楷体', 'kai');

  const ReaderFontStyle(this.label, this.value);

  final String label;
  final String value;

  static ReaderFontStyle fromValue(Object? value) {
    for (final option in values) {
      if (option.value == value) {
        return option;
      }
    }
    return ReaderFontStyle.system;
  }
}

enum ReaderTextIndent {
  flush('首行顶格', 'flush'),
  indent('首行缩进', 'indent');

  const ReaderTextIndent(this.label, this.value);

  final String label;
  final String value;

  static ReaderTextIndent fromValue(Object? value) {
    for (final option in values) {
      if (option.value == value) {
        return option;
      }
    }
    return ReaderTextIndent.indent;
  }
}

enum ReaderFlow {
  paginated('左右滑动', 'paginated'),
  scrolled('上下滚动', 'scrolled');

  const ReaderFlow(this.label, this.value);

  final String label;
  final String value;

  static ReaderFlow fromValue(Object? value) {
    for (final option in values) {
      if (option.value == value) {
        return option;
      }
    }
    return ReaderFlow.paginated;
  }
}

const double readerAutoPageSpeedMin = 0.5;
const double readerAutoPageSpeedMax = 3;
const double readerAutoPageSpeedDefault = 1.5;

/// Current JSON schema version for persisted reader settings.
const int readerSettingsSchemaVersion = 2;

/// Default plain reader background color.
const String readerDefaultBackgroundColor = '#fbfaf7';

/// Default reader background image. An empty value means no image.
const String readerDefaultBackgroundImage = '';

/// How a reader background image should fit the visible reader viewport.
enum ReaderBackgroundImageFit {
  /// Stretch the image to fill the viewport without cropping.
  stretch('stretch'),

  /// Fill the viewport while preserving aspect ratio. Some cropping may occur.
  cover('cover'),

  /// Preserve the full image. Empty space may remain around the image.
  contain('contain');

  const ReaderBackgroundImageFit(this.value);

  final String value;
}

/// Appearance choices shown by the built-in reader background panel.
///
/// Background image paths are relative to `assets/reader/` as served by the
/// reader asset server, for example `bg/bg_1.png`.
class ReaderAppearanceOptions {
  const ReaderAppearanceOptions({
    this.backgroundColors = const ['#fbfaf7', '#f7f2df', '#ccf0cf', '#202124'],
    this.backgroundImages = const [
      'bg/bg_1.png',
      'bg/bg_2.png',
      'bg/bg_3.png',
      'bg/bg_4.png',
    ],
    this.backgroundImageFit = ReaderBackgroundImageFit.stretch,
  });

  final List<String> backgroundColors;

  /// Background image choices shown in the background panel.
  ///
  /// Paths must be relative, must not contain `..`, and must not include a URL
  /// scheme. Unsafe entries are filtered out before rendering.
  final List<String> backgroundImages;

  /// Fit mode used when a background image is selected.
  final ReaderBackgroundImageFit backgroundImageFit;

  List<String> get safeBackgroundColors {
    return List.unmodifiable(backgroundColors.where(_isValidBackgroundColor));
  }

  List<String> get safeBackgroundImages {
    return List.unmodifiable(
      backgroundImages.where(_isSafeBackgroundImagePath),
    );
  }

  static final RegExp _hexColorPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

  static bool _isValidBackgroundColor(String color) {
    return _hexColorPattern.hasMatch(color.trim());
  }

  static bool _isSafeBackgroundImagePath(String path) {
    final normalized = path.trim();
    return normalized.isNotEmpty &&
        !normalized.startsWith('/') &&
        !normalized.contains('..') &&
        Uri.tryParse(normalized)?.hasScheme != true;
  }
}

/// User-configurable reader settings that can be persisted and restored.
class ReaderSettings {
  const ReaderSettings({
    this.schemaVersion = readerSettingsSchemaVersion,
    this.fontSize = 18,
    this.lineHeight = 1.55,
    this.margin = 0,
    this.brightness = 1,
    this.backgroundColor = readerDefaultBackgroundColor,
    this.backgroundImage = readerDefaultBackgroundImage,
    this.fontStyle = ReaderFontStyle.system,
    this.textIndent = ReaderTextIndent.indent,
    this.flow = ReaderFlow.paginated,
    this.autoPageSpeed = readerAutoPageSpeedDefault,
  });

  factory ReaderSettings.fromJson(Map<String, Object?> json) {
    const fallback = ReaderSettings();
    return ReaderSettings(
      schemaVersion: _readInt(
        json['schemaVersion'],
        fallback.schemaVersion,
        min: 1,
        max: readerSettingsSchemaVersion,
      ),
      fontSize: _readDouble(
        json['fontSize'],
        fallback.fontSize,
        min: 12,
        max: 32,
      ),
      lineHeight: _readDouble(
        json['lineHeight'],
        fallback.lineHeight,
        min: 1.1,
        max: 2.4,
      ),
      margin: _readDouble(json['margin'], fallback.margin, min: 0, max: 64),
      brightness: _readDouble(
        json['brightness'],
        fallback.brightness,
        min: .55,
        max: 1.25,
      ),
      backgroundColor: _readBackgroundColor(json['backgroundColor']),
      backgroundImage: _readBackgroundImage(json['backgroundImage']),
      fontStyle: ReaderFontStyle.fromValue(json['fontStyle']),
      textIndent: ReaderTextIndent.fromValue(json['textIndent']),
      flow: ReaderFlow.fromValue(json['flow']),
      autoPageSpeed: _readDouble(
        json['autoPageSpeed'],
        fallback.autoPageSpeed,
        min: readerAutoPageSpeedMin,
        max: readerAutoPageSpeedMax,
      ),
    );
  }

  final int schemaVersion;

  /// Font size in logical pixels.
  final double fontSize;

  /// Line height multiplier.
  final double lineHeight;

  /// Horizontal content margin in logical pixels.
  final double margin;

  /// Screen brightness multiplier applied inside the reader web view.
  final double brightness;

  /// Plain background color as `#RRGGBB`.
  final String backgroundColor;

  /// Background image path relative to `assets/reader/`, or empty for none.
  final String backgroundImage;

  /// Font family preset used for book content.
  final ReaderFontStyle fontStyle;

  /// Paragraph first-line indent behavior.
  final ReaderTextIndent textIndent;

  /// Reader layout flow.
  final ReaderFlow flow;

  /// Auto page speed multiplier.
  final double autoPageSpeed;

  static double _readDouble(
    Object? value,
    double fallback, {
    required double min,
    required double max,
  }) {
    final parsed = value is num
        ? value.toDouble()
        : value is String
        ? double.tryParse(value)
        : null;
    if (parsed == null || !parsed.isFinite) {
      return fallback;
    }
    return parsed.clamp(min, max);
  }

  static int _readInt(
    Object? value,
    int fallback, {
    required int min,
    required int max,
  }) {
    final parsed = value is num
        ? value.toInt()
        : value is String
        ? int.tryParse(value)
        : null;
    if (parsed == null) {
      return fallback;
    }
    return parsed.clamp(min, max);
  }

  static String _readBackgroundColor(Object? value) {
    if (value is! String) {
      return readerDefaultBackgroundColor;
    }
    final normalized = value.trim();
    return ReaderAppearanceOptions._isValidBackgroundColor(normalized)
        ? normalized
        : readerDefaultBackgroundColor;
  }

  static String _readBackgroundImage(Object? value) {
    if (value is! String) {
      return readerDefaultBackgroundImage;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return readerDefaultBackgroundImage;
    }
    return ReaderAppearanceOptions._isSafeBackgroundImagePath(normalized)
        ? normalized
        : readerDefaultBackgroundImage;
  }

  ReaderSettings copyWith({
    int? schemaVersion,
    double? fontSize,
    double? lineHeight,
    double? margin,
    double? brightness,
    String? backgroundColor,
    String? backgroundImage,
    ReaderFontStyle? fontStyle,
    ReaderTextIndent? textIndent,
    ReaderFlow? flow,
    double? autoPageSpeed,
  }) {
    return ReaderSettings(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      margin: margin ?? this.margin,
      brightness: brightness ?? this.brightness,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      fontStyle: fontStyle ?? this.fontStyle,
      textIndent: textIndent ?? this.textIndent,
      flow: flow ?? this.flow,
      autoPageSpeed: autoPageSpeed ?? this.autoPageSpeed,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'margin': margin,
      'brightness': brightness,
      'backgroundColor': backgroundColor,
      'backgroundImage': backgroundImage,
      'fontStyle': fontStyle.value,
      'textIndent': textIndent.value,
      'flow': flow.value,
      'autoPageSpeed': autoPageSpeed,
    };
  }
}
