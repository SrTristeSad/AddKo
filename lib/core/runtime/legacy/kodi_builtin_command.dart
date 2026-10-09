class KodiBuiltinCommand {
  const KodiBuiltinCommand({
    required this.raw,
    required this.name,
    required this.arguments,
  });

  final String raw;
  final String name;
  final List<String> arguments;

  String get normalizedName => name.trim().toLowerCase();

  String? argument(int index) {
    if (index < 0 || index >= arguments.length) {
      return null;
    }
    return arguments[index];
  }

  bool get isEmpty => name.trim().isEmpty;

  factory KodiBuiltinCommand.parse(String source) {
    final raw = source.trim();
    if (raw.isEmpty) {
      return const KodiBuiltinCommand(raw: '', name: '', arguments: []);
    }

    final open = raw.indexOf('(');
    if (open < 0) {
      return KodiBuiltinCommand(
        raw: raw,
        name: raw,
        arguments: const [],
      );
    }

    final close = _matchingClose(raw, open);
    final body = close > open
        ? raw.substring(open + 1, close)
        : raw.substring(open + 1);

    return KodiBuiltinCommand(
      raw: raw,
      name: raw.substring(0, open).trim(),
      arguments: List.unmodifiable(
        _splitArguments(body).map(_unquote).map((value) => value.trim()),
      ),
    );
  }

  static int _matchingClose(String value, int open) {
    var depth = 0;
    String? quote;
    var escaped = false;

    for (var index = open; index < value.length; index++) {
      final char = value[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '\\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          return index;
        }
      }
    }
    return -1;
  }

  static List<String> _splitArguments(String value) {
    if (value.trim().isEmpty) {
      return const [];
    }

    final result = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    String? quote;
    var escaped = false;

    void finish() {
      result.add(buffer.toString());
      buffer.clear();
    }

    for (var index = 0; index < value.length; index++) {
      final char = value[index];
      if (escaped) {
        buffer.write(char);
        escaped = false;
        continue;
      }
      if (char == '\\') {
        buffer.write(char);
        escaped = true;
        continue;
      }
      if (quote != null) {
        buffer.write(char);
        if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        buffer.write(char);
        continue;
      }
      if (char == '(') {
        depth++;
        buffer.write(char);
        continue;
      }
      if (char == ')') {
        if (depth > 0) {
          depth--;
        }
        buffer.write(char);
        continue;
      }
      if (char == ',' && depth == 0) {
        finish();
        continue;
      }
      buffer.write(char);
    }
    finish();
    return result;
  }

  static String _unquote(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      return trimmed;
    }
    final first = trimmed[0];
    final last = trimmed[trimmed.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }
}
