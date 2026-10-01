class BoardHelper {
  static String files = 'abcdefgh';
  static int getFileFromIndex(int index) {
    return index % 8;
  }

  static int getRankFromIndex(int index) {
    return index ~/ 8;
  }

  static String squareName(int index) {
    final file = getFileFromIndex(index);
    final row = getRankFromIndex(index);
    return '${files[file]}${8 - row}';
  }

  static int squareIndex(String square) {
    final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.parse(square[1]);
    return (8 - rank) * 8 + file;
  }
}
