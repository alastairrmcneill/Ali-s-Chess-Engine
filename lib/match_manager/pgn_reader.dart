class PgnGame {
  final Map<String, String> headers;
  final List<String> sanMoves;
  final String? result; // '1-0', '0-1', '1/2-1/2', '*' or null

  const PgnGame(this.headers, this.sanMoves, this.result);
}

/// Reads PGN text: headers, comments {…} and ;…, nested variations (…), NAGs $n and move numbers.
class PgnReader {
  static const _results = {'1-0', '0-1', '1/2-1/2', '*'};
  static final _header = RegExp(r'^\[(\w+)\s+"(.*)"\]$');
  static final _moveNumber = RegExp(r'^\d+\.+');

  static List<PgnGame> parseMany(String text) {
    final games = <PgnGame>[];
    var headers = <String, String>{};
    var moves = <String>[];
    var inComment = false;
    var variationDepth = 0;

    void finish(String? result) {
      if (moves.isNotEmpty || result != null) games.add(PgnGame(headers, moves, result));
      headers = {};
      moves = [];
    }

    void handleToken(String token) {
      final stripped = token.replaceFirst(_moveNumber, '');
      if (stripped.isEmpty) return;
      if (_results.contains(stripped)) {
        finish(stripped);
      } else {
        moves.add(stripped);
      }
    }

    for (final rawLine in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (!inComment && variationDepth == 0 && line.startsWith('[') && line.endsWith(']')) {
        final match = _header.firstMatch(line);
        if (match != null) {
          if (moves.isNotEmpty) finish(null);
          headers[match.group(1)!] = match.group(2)!;
          continue;
        }
      }

      var token = StringBuffer();
      void flush() {
        if (token.isNotEmpty) handleToken(token.toString());
        token = StringBuffer();
      }

      for (int i = 0; i < line.length; i++) {
        final c = line[i];
        if (inComment) {
          if (c == '}') inComment = false;
          continue;
        }
        if (c == '{') {
          flush();
          inComment = true;
        } else if (c == ';') {
          break; // rest-of-line comment
        } else if (c == '(') {
          flush();
          variationDepth++;
        } else if (c == ')') {
          flush();
          if (variationDepth > 0) variationDepth--;
        } else if (variationDepth > 0) {
          continue;
        } else if (c == ' ' || c == '\t') {
          flush();
        } else if (c == r'$' && token.isEmpty) {
          while (i + 1 < line.length && '0123456789'.contains(line[i + 1])) {
            i++;
          }
        } else {
          token.write(c);
        }
      }
      flush();
    }
    finish(null);
    return games.where((g) => g.sanMoves.isNotEmpty || g.result != null).toList();
  }
}
