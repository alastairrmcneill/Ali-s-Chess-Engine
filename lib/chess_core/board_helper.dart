class BoardHelper {
  static const String files = "abcdefgh";

  static int getFileFromIndex(int index) {
    return index % 8;
  }

  static int getRankFromIndex(int index) {
    return index ~/ 8;
  }

  /// Index 0 is a8 and index 63 is h1
  static String squareName(int index) {
    return "${files[getFileFromIndex(index)]}${8 - getRankFromIndex(index)}";
  }

  static int squareIndex(String name) {
    if (name.length != 2) throw FormatException("Invalid square", name);
    int file = files.indexOf(name[0]);
    int rank = int.tryParse(name[1]) ?? 0;
    if (file == -1 || rank < 1 || rank > 8) throw FormatException("Invalid square", name);
    return (8 - rank) * 8 + file;
  }
}
