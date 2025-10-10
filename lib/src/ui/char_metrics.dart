import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/painting.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';

/// Shared metrics cache so multiple widgets can reuse the same character size
/// measurements. The key factors incorporate Flutter's [TextScaler] to honor
/// platform text scaling preferences.
class CharMetricsCache {
  Size measure(TerminalStyle style, TextScaler textScaler) {
    final key = _CharMetricsKey.from(style, textScaler);
    return _cache.putIfAbsent(key, () => _compute(style, textScaler));
  }

  void clear() {
    _cache.clear();
  }

  final Map<_CharMetricsKey, Size> _cache = {};

  Size _compute(TerminalStyle style, TextScaler textScaler) {
    const test = 'mmmmmmmmmm';

    final textStyle = style.toTextStyle();
    final builder = ParagraphBuilder(textStyle.getParagraphStyle());
    builder.pushStyle(textStyle.getTextStyle(textScaler: textScaler));
    builder.addText(test);

    final paragraph = builder.build();
    paragraph.layout(const ParagraphConstraints(width: double.infinity));

    final result = Size(
      paragraph.maxIntrinsicWidth / test.length,
      paragraph.height,
    );

    paragraph.dispose();
    return result;
  }

  static final CharMetricsCache instance = CharMetricsCache();

  static const _listEquality = ListEquality<String>();
}

/// Convenience wrapper to reuse the shared cache from existing call sites.
Size calcCharSize(TerminalStyle style, TextScaler textScaler) {
  return CharMetricsCache.instance.measure(style, textScaler);
}

class _CharMetricsKey {
  const _CharMetricsKey({
    required this.effectiveFontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.fontFamilyFallback,
    required this.textScalerHash,
    required this.letterSpacing,
  });

  factory _CharMetricsKey.from(TerminalStyle style, TextScaler textScaler) {
    return _CharMetricsKey(
      effectiveFontSize: textScaler.scale(style.fontSize),
      lineHeight: style.height,
      fontFamily: style.fontFamily,
      fontFamilyFallback: List<String>.unmodifiable(style.fontFamilyFallback),
      textScalerHash: Object.hash(textScaler.runtimeType, textScaler.hashCode),
      letterSpacing: style.letterSpacing,
    );
  }

  final double effectiveFontSize;
  final double lineHeight;
  final String fontFamily;
  final List<String> fontFamilyFallback;
  final int textScalerHash;
  final double letterSpacing;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _CharMetricsKey &&
        other.effectiveFontSize == effectiveFontSize &&
        other.lineHeight == lineHeight &&
        other.fontFamily == fontFamily &&
        other.letterSpacing == letterSpacing &&
        other.textScalerHash == textScalerHash &&
        CharMetricsCache._listEquality.equals(
          other.fontFamilyFallback,
          fontFamilyFallback,
        );
  }

  @override
  int get hashCode {
    return Object.hash(
      effectiveFontSize,
      lineHeight,
      fontFamily,
      textScalerHash,
      letterSpacing,
      CharMetricsCache._listEquality.hash(fontFamilyFallback),
    );
  }
}
