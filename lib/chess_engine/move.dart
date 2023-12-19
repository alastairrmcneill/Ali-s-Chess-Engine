class Move {
  final int startingSquare;
  final int targetSquare;

  Move({
    required this.startingSquare,
    required this.targetSquare,
  });

  @override
  String toString() {
    return "From: ${startingSquare} To: ${targetSquare}";
  }
}
