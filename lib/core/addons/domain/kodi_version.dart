class KodiVersion implements Comparable<KodiVersion> {
  KodiVersion(String value):raw=value.trim(); final String raw; late final List<_VersionToken> _tokens=_tokenize(raw);
  @override int compareTo(KodiVersion other){final maxLength=_tokens.length>other._tokens.length?_tokens.length:other._tokens.length;for(var i=0;i<maxLength;i++){final l=i<_tokens.length?_tokens[i]:_VersionToken.zero;final r=i<other._tokens.length?other._tokens[i]:_VersionToken.zero;final c=l.compareTo(r);if(c!=0)return c;}return 0;}
  bool isAtLeast(String? minimum)=>minimum==null||minimum.trim().isEmpty||compareTo(KodiVersion(minimum))>=0;
  static List<_VersionToken> _tokenize(String value){if(value.isEmpty)return const [_VersionToken.zero];final matches=RegExp(r'[0-9]+|[A-Za-z]+').allMatches(value);if(matches.isEmpty)return [_VersionToken.text(value.toLowerCase())];return [for(final m in matches) if(int.tryParse(m.group(0)!) case final n?) _VersionToken.number(n) else _VersionToken.text(m.group(0)!.toLowerCase())];}
  @override String toString()=>raw;
}
class _VersionToken implements Comparable<_VersionToken>{const _VersionToken.number(this.number):text=null,isNumber=true;const _VersionToken.text(this.text):number=null,isNumber=false;static const zero=_VersionToken.number(0);final int? number;final String? text;final bool isNumber;@override int compareTo(_VersionToken other){if(isNumber&&other.isNumber)return number!.compareTo(other.number!);if(isNumber!=other.isNumber)return isNumber?1:-1;return text!.compareTo(other.text!);}}
