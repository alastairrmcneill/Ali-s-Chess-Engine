class BoardHelper {
  static int getFileFromIndex(int index) {
    return index % 8;
  }

  static int getRankFromIndex(int index) {
    return index ~/ 8;
  }
}
