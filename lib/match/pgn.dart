/// Minimal PGN reading and writing: headers, SAN moves, {comments} and $NAGs. Variations are skipped when reading.
class PgnMove {
  final String san;
  final String? comment;
  final List<int> nags; // e.g. 2 = "?" (mistake)

  const PgnMove(this.san, {this.comment, this.nags = const []});
}

class PgnGame {
  final Map<String, String> headers;
  final List<PgnMove> moves;

  PgnGame(this.headers, this.moves);

  String get result => headers["Result"] ?? "*";

  String toPgn() {
    StringBuffer buffer = StringBuffer();
    headers.forEach((key, value) => buffer.writeln('[$key "${value.replaceAll('"', "'")}"]'));
    buffer.writeln();

    // Work out whether the first move is white's from the FEN header so move numbers are right
    bool whiteToMove = true;
    int moveNumber = 1;
    String? fen = headers["FEN"];
    if (fen != null) {
      List<String> fields = fen.split(" ");
      whiteToMove = fields.length < 2 || fields[1] == "w";
      moveNumber = fields.length > 5 ? int.tryParse(fields[5]) ?? 1 : 1;
    }

    List<String> tokens = [];
    bool needNumber = true;
    for (PgnMove move in moves) {
      if (whiteToMove) {
        tokens.add("$moveNumber.");
      } else if (needNumber) {
        tokens.add("$moveNumber...");
      }
      tokens.add(move.san);
      for (int nag in move.nags) {
        tokens.add("\$$nag");
      }
      if (move.comment != null) tokens.add("{${move.comment!.replaceAll("}", ")")}}");

      // After a comment the next black move needs its number repeated
      needNumber = move.comment != null;
      if (!whiteToMove) moveNumber++;
      whiteToMove = !whiteToMove;
    }
    tokens.add(result);

    // Wrap lines at 80 characters
    String line = "";
    for (String token in tokens) {
      if (line.isNotEmpty && line.length + token.length + 1 > 80) {
        buffer.writeln(line);
        line = token;
      } else {
        line = line.isEmpty ? token : "$line $token";
      }
    }
    buffer.writeln(line);
    return buffer.toString();
  }

  static String writeAll(Iterable<PgnGame> games) => games.map((game) => game.toPgn()).join("\n");

  static List<PgnGame> parseAll(String pgn) {
    List<PgnGame> games = [];
    _PgnScanner scanner = _PgnScanner(pgn);

    while (true) {
      scanner.skipWhitespace();
      if (scanner.atEnd) break;

      Map<String, String> headers = {};
      while (scanner.peek == "[") {
        String tag = scanner.readUntil("]");
        scanner.skip(1);
        Match? match = RegExp(r'^\[\s*(\w+)\s+"(.*)"\s*$').firstMatch(tag);
        if (match != null) headers[match.group(1)!] = match.group(2)!;
        scanner.skipWhitespace();
      }

      List<PgnMove> moves = [];
      while (!scanner.atEnd && scanner.peek != "[") {
        String char = scanner.peek;
        if (char == "{") {
          scanner.skip(1);
          String comment = scanner.readUntil("}").trim();
          scanner.skip(1);
          if (moves.isNotEmpty) {
            PgnMove last = moves.removeLast();
            String combined = last.comment == null ? comment : "${last.comment} $comment";
            moves.add(PgnMove(last.san, comment: combined, nags: last.nags));
          }
        } else if (char == "(") {
          scanner.skipVariation();
        } else if (char == ";") {
          scanner.readUntil("\n");
        } else if (RegExp(r"\s").hasMatch(char)) {
          scanner.skip(1);
        } else {
          String token = scanner.readToken();
          if (token.startsWith("\$")) {
            if (moves.isNotEmpty) {
              PgnMove last = moves.removeLast();
              moves.add(PgnMove(last.san, comment: last.comment, nags: [...last.nags, int.tryParse(token.substring(1)) ?? 0]));
            }
          } else if (const ["1-0", "0-1", "1/2-1/2", "*"].contains(token)) {
            headers.putIfAbsent("Result", () => token);
          } else {
            // Strip move numbers like "12." or "12..." that may be glued to the move
            String san = token.replaceFirst(RegExp(r"^\d+\.+"), "");
            if (san.isNotEmpty) moves.add(PgnMove(san));
          }
        }
      }

      games.add(PgnGame(headers, moves));
    }
    return games;
  }
}

class _PgnScanner {
  final String text;
  int position = 0;

  _PgnScanner(this.text);

  bool get atEnd => position >= text.length;
  String get peek => text[position];

  void skip(int count) => position += count;

  void skipWhitespace() {
    while (!atEnd && RegExp(r"\s").hasMatch(peek)) {
      position++;
    }
  }

  String readUntil(String end) {
    int index = text.indexOf(end, position);
    if (index == -1) index = text.length;
    String result = text.substring(position, index);
    position = index;
    return result;
  }

  String readToken() {
    int start = position;
    while (!atEnd && !RegExp(r"[\s{}()\[;]").hasMatch(peek)) {
      position++;
    }
    return text.substring(start, position);
  }

  void skipVariation() {
    int depth = 0;
    while (!atEnd) {
      String char = peek;
      position++;
      if (char == "{") {
        readUntil("}");
        position++;
      } else if (char == "(") {
        depth++;
      } else if (char == ")") {
        depth--;
        if (depth == 0) return;
      }
    }
  }
}
