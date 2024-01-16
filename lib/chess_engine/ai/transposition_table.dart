import 'package:ace/chess_engine/move.dart';

class TranspositionTable {
  final int size;
  final Map<int, TranspositionTableEntry> _table = {};

  TranspositionTable(this.size);

  void clear() {
    _table.clear();
  }

  void addEntry(TranspositionTableEntry entry) {
    if (_table.length >= size) {
      print("out of space");
    }
    _table[entry.zobristHash] = entry;
  }

  TranspositionTableEntry? retrieve(int zobristHash, int depth, int alpha, int beta, int plyFromRoot) {
    TranspositionTableEntry? entry = _table[zobristHash];

    // Return null if it doesn't exist
    if (entry == null) {
      return null;
    }

    // If it does exist only return it if entry has been done to a deeper depth.
    if (entry.depth >= depth) {
      int eval = adjustMateScore(entry.eval, plyFromRoot);

      // If its an exact eval then just return the whole entry
      if (entry.type == EntryType.exact) {
        return entry;
      }

      // If its an upper bound but the stored eval is less than
      // alpha then we don't want to bother searching so just return the entry
      if (entry.type == EntryType.upperBound && eval <= alpha) {
        return entry;
      }

      // If its a lower bound then only return this if it will cause a beta cut off.
      // We have stored the lower bound of the eval for this position. Only return if it causes a beta cut-off.
      if (entry.type == EntryType.lowerBound && eval >= beta) {
        return entry;
      }
    }

    // If none of those then return null
    return null;
  }

  int adjustMateScore(int score, int plyFromRoot) {
    // If the score is above the score given for checkmate/10.
    if (score.abs() > 99999999) {
      // If it is then adjust it for the number of moves to reach checkamte now.
      int sign = score.sign;
      return sign * (score * sign - plyFromRoot);
    }

    return score;
  }
}

class TranspositionTableEntry {
  final int zobristHash;
  final int depth;
  final int eval;
  final EntryType type; // Enum for entry type: EXACT, LOWERBOUND, UPPERBOUND
  final Move bestMove; // Represent the move in a format that suits your engine

  TranspositionTableEntry({
    required this.zobristHash,
    required this.depth,
    required this.eval,
    required this.type,
    required this.bestMove,
  });
}

enum EntryType { exact, lowerBound, upperBound }
