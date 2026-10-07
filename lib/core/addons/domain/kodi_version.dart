class KodiVersion implements Comparable<KodiVersion> {
  KodiVersion(String value) : raw = value.trim();

  final String raw;

  late final List<_VersionToken> _tokens = _tokenize(raw);

  @override
  int compareTo(KodiVersion other) {
    final maxLength = _tokens.length > other._tokens.length
        ? _tokens.length
        : other._tokens.length;

    for (var index = 0; index < maxLength; index += 1) {
      final left = index < _tokens.length ? _tokens[index] : _VersionToken.zero;
      final right = index < other._tokens.length
          ? other._tokens[index]
          : _VersionToken.zero;
      final comparison = left.compareTo(right);
      if (comparison != 0) {
        return comparison;
      }
    }

    return 0;
  }

  bool isAtLeast(String? minimum) {
    if (minimum == null || minimum.trim().isEmpty) {
      return true;
    }
    return compareTo(KodiVersion(minimum)) >= 0;
  }

  static List<_VersionToken> _tokenize(String value) {
    if (value.isEmpty) {
      return const [_VersionToken.zero];
    }

    final matches = RegExp(r'[0-9]+|[A-Za-z]+').allMatches(value);
    if (matches.isEmpty) {
      return [_VersionToken.text(value.toLowerCase())];
    }

    return [
      for (final match in matches)
        if (int.tryParse(match.group(0)!) case final number?)
          _VersionToken.number(number)
        else
          _VersionToken.text(match.group(0)!.toLowerCase()),
    ];
  }

  @override
  String toString() => raw;
}

class _VersionToken implements Comparable<_VersionToken> {
  const _VersionToken.number(this.number)
      : text = null,
        isNumber = true;

  const _VersionToken.text(this.text)
      : number = null,
        isNumber = false;

  static const zero = _VersionToken.number(0);

  final int? number;
  final String? text;
  final bool isNumber;

  @override
  int compareTo(_VersionToken other) {
    if (isNumber && other.isNumber) {
      return number!.compareTo(other.number!);
    }
    if (isNumber != other.isNumber) {
      return isNumber ? 1 : -1;
    }
    return text!.compareTo(other.text!);
  }
}
