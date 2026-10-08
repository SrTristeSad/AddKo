import 'package:flutter/material.dart';

class KodiText extends StatelessWidget {
  const KodiText(
    this.data, {
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign,
    super.key,
  });

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final spans = KodiMarkup.parse(
      data,
      fallbackColor: DefaultTextStyle.of(context).style.color,
    );
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

class KodiMarkup {
  const KodiMarkup._();

  static final RegExp _tagPattern = RegExp(
    r'\[(/?)(B|I|COLOR|LIGHT|UPPERCASE|LOWERCASE|CAPITALIZE|CR)(?:[ =]([^\]]+))?\]',
    caseSensitive: false,
  );

  static List<InlineSpan> parse(
    String input, {
    Color? fallbackColor,
  }) {
    final spans = <InlineSpan>[];
    final stack = <_KodiStyleState>[_KodiStyleState.root(fallbackColor)];
    var cursor = 0;

    for (final match in _tagPattern.allMatches(input)) {
      if (match.start > cursor) {
        _appendText(spans, input.substring(cursor, match.start), stack.last);
      }

      final closing = match.group(1) == '/';
      final tag = match.group(2)!.toUpperCase();
      final argument = match.group(3)?.trim();

      if (tag == 'CR' && !closing) {
        _appendText(spans, '\n', stack.last);
      } else if (closing) {
        _closeTag(stack, tag);
      } else {
        stack.add(stack.last.open(tag, argument));
      }

      cursor = match.end;
    }

    if (cursor < input.length) {
      _appendText(spans, input.substring(cursor), stack.last);
    }

    return spans;
  }

  static String strip(String input) {
    return input.replaceAllMapped(_tagPattern, (match) {
      final tag = match.group(2)!.toUpperCase();
      return tag == 'CR' && match.group(1) != '/' ? '\n' : '';
    });
  }

  static void _appendText(
    List<InlineSpan> spans,
    String raw,
    _KodiStyleState state,
  ) {
    if (raw.isEmpty) return;

    var text = raw;
    switch (state.transform) {
      case _TextTransform.uppercase:
        text = text.toUpperCase();
      case _TextTransform.lowercase:
        text = text.toLowerCase();
      case _TextTransform.capitalize:
        text = _capitalize(text);
      case _TextTransform.none:
        break;
    }

    spans.add(
      TextSpan(
        text: text,
        style: TextStyle(
          fontWeight: state.bold ? FontWeight.w700 : null,
          fontStyle: state.italic ? FontStyle.italic : null,
          color: state.color,
          fontWeightFallback: const [],
        ).copyWith(
          color: state.light
              ? state.color?.withValues(alpha: 0.72)
              : state.color,
        ),
      ),
    );
  }

  static void _closeTag(List<_KodiStyleState> stack, String tag) {
    for (var index = stack.length - 1; index > 0; index -= 1) {
      if (stack[index].tag == tag) {
        stack.removeRange(index, stack.length);
        return;
      }
    }
  }

  static String _capitalize(String value) {
    return value.replaceAllMapped(
      RegExp(r'(^|\s)(\S)'),
      (match) => '${match.group(1)}${match.group(2)!.toUpperCase()}',
    );
  }
}

class _KodiStyleState {
  const _KodiStyleState({
    required this.tag,
    required this.bold,
    required this.italic,
    required this.light,
    required this.color,
    required this.transform,
  });

  factory _KodiStyleState.root(Color? color) {
    return _KodiStyleState(
      tag: 'ROOT',
      bold: false,
      italic: false,
      light: false,
      color: color,
      transform: _TextTransform.none,
    );
  }

  final String tag;
  final bool bold;
  final bool italic;
  final bool light;
  final Color? color;
  final _TextTransform transform;

  _KodiStyleState open(String nextTag, String? argument) {
    return _KodiStyleState(
      tag: nextTag,
      bold: nextTag == 'B' ? true : bold,
      italic: nextTag == 'I' ? true : italic,
      light: nextTag == 'LIGHT' ? true : light,
      color: nextTag == 'COLOR' ? _parseColor(argument) ?? color : color,
      transform: switch (nextTag) {
        'UPPERCASE' => _TextTransform.uppercase,
        'LOWERCASE' => _TextTransform.lowercase,
        'CAPITALIZE' => _TextTransform.capitalize,
        _ => transform,
      },
    );
  }

  static Color? _parseColor(String? raw) {
    if (raw == null) return null;
    final value = raw.trim().replaceAll('#', '').toLowerCase();
    final hex = int.tryParse(value, radix: 16);
    if (hex != null && (value.length == 6 || value.length == 8)) {
      return Color(value.length == 6 ? 0xff000000 | hex : hex);
    }

    return _namedColors[value];
  }

  static const Map<String, Color> _namedColors = {
    'black': Color(0xff000000),
    'white': Color(0xffffffff),
    'red': Color(0xffff0000),
    'green': Color(0xff008000),
    'blue': Color(0xff0000ff),
    'yellow': Color(0xffffff00),
    'orange': Color(0xffffa500),
    'lime': Color(0xff00ff00),
    'aqua': Color(0xff00ffff),
    'cyan': Color(0xff00ffff),
    'teal': Color(0xff008080),
    'navy': Color(0xff000080),
    'purple': Color(0xff800080),
    'violet': Color(0xffee82ee),
    'magenta': Color(0xffff00ff),
    'fuchsia': Color(0xffff00ff),
    'pink': Color(0xffffc0cb),
    'gold': Color(0xffffd700),
    'silver': Color(0xffc0c0c0),
    'gray': Color(0xff808080),
    'grey': Color(0xff808080),
    'lightgray': Color(0xffd3d3d3),
    'lightgrey': Color(0xffd3d3d3),
    'darkgray': Color(0xffa9a9a9),
    'darkgrey': Color(0xffa9a9a9),
    'brown': Color(0xffa52a2a),
    'maroon': Color(0xff800000),
    'olive': Color(0xff808000),
    'aquamarine': Color(0xff7fffd4),
    'firebrick': Color(0xffb22222),
    'orangered': Color(0xffff4500),
    'tomato': Color(0xffff6347),
    'coral': Color(0xffff7f50),
    'chocolate': Color(0xffd2691e),
    'khaki': Color(0xfff0e68c),
    'wheat': Color(0xfff5deb3),
    'beige': Color(0xfff5f5dc),
    'ivory': Color(0xfffffff0),
    'deepskyblue': Color(0xff00bfff),
    'dodgerblue': Color(0xff1e90ff),
    'skyblue': Color(0xff87ceeb),
    'royalblue': Color(0xff4169e1),
    'steelblue': Color(0xff4682b4),
    'chartreuse': Color(0xff7fff00),
    'lawngreen': Color(0xff7cfc00),
    'yellowgreen': Color(0xff9acd32),
  };
}

enum _TextTransform { none, uppercase, lowercase, capitalize }
