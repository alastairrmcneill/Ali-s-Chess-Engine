import 'dart:typed_data';

import 'package:ace/engines/v9/core/move.dart';

class TranspositionTable {
  static const int exact = 1, lower = 2, upper = 3;
  static const int mateScore = -999999999;

  final int size; // needs to be a power of two
  final int _mask;
  final Int64List _keys;
  final Int32List _scores;
  final Int32List _moves;
  final Int8List _depths;
  final Uint8List _flags;

  TranspositionTable({int sizePower = 21})
      : size = 1 << sizePower,
        _mask = (1 << sizePower) - 1,
        _keys = Int64List(1 << sizePower),
        _scores = Int32List(1 << sizePower),
        _moves = Int32List(1 << sizePower),
        _depths = Int8List(1 << sizePower),
        _flags = Uint8List(1 << sizePower);

  static int packMove(Move m) => m.startingSquare | (m.targetSquare << 6) | (m.promotion << 12);

  int index(int key) => key & _mask;

  int? probe(int key) {
    final i = index(key);
    return _keys[i] == key && _flags[i] != 0 ? i : null;
  }

  int depthAt(int slot) => _depths[slot];
  int scoreAt(int slot) => _scores[slot];
  int moveAt(int slot) => _moves[slot];
  int flagAt(int slot) => _flags[slot];

  void store(int key, int score, Move move, int depth, int flag) {
    final i = index(key);
    _keys[i] = key;
    _scores[i] = score;
    _moves[i] = packMove(move);
    _depths[i] = depth > 127 ? 127 : depth;
    _flags[i] = flag;
  }
}
