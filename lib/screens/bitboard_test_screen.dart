import 'dart:math';
import 'dart:typed_data';

import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/fen.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/components/square.dart';
import 'package:ace/engines/v12/core/attack_tables.dart';
import 'package:ace/engines/v12/core/bitboard.dart';
import 'package:ace/engines/v12/core/board.dart';
import 'package:ace/engines/v12/core/move.dart';
import 'package:ace/engines/v12/core/move_generator.dart';
import 'package:ace/engines/v12/core/sliders.dart';
import 'package:ace/engines/v12/core/zobrist.dart';
import 'package:flutter/material.dart';

String _hex(int b) {
  final hi = (b >>> 32).toRadixString(16).padLeft(8, '0');
  final lo = (b & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '0x$hi$lo';
}

/// Debug screen for the v12 bitboard work.
/// - Tables & sliders: attack tables, plus Sliders (rook/bishop/queen) with editable blockers, checked against a
///   naive square-by-square walk.
/// - Board: play moves on a real v12 Board and verify after every make/unmake that the bitboards, Zobrist key and
///   undo state agree with the mailbox. Includes a random-playout fuzz test.
class BitboardTestScreen extends StatelessWidget {
  const BitboardTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bitboard debug'),
          bottom: const TabBar(tabs: [Tab(text: 'Tables & sliders'), Tab(text: 'Board')]),
        ),
        body: const SafeArea(child: TabBarView(children: [_TablesTab(), _BoardTab()])),
      ),
    );
  }
}

/// 8x8 grid of [Square]s. Index 0 = a8 (top left), 63 = h1.
class _Grid extends StatelessWidget {
  final int Function(int index) pieceAt;
  final int targets; // bitboard drawn as move hints / capture rings
  final int selected; // bitboard drawn highlighted
  final int marked; // bitboard drawn with the "last move" highlight (used for mismatches)
  final void Function(int index) onTap;

  const _Grid({
    required this.pieceAt,
    required this.targets,
    required this.selected,
    required this.marked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide / 8;
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                for (int row = 0; row < 8; row++)
                  Row(
                    children: [
                      for (int col = 0; col < 8; col++) _square(row * 8 + col, row, col, size),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _square(int index, int row, int col, double size) {
    final rank = BoardHelper.getRankFromIndex(index);
    final file = BoardHelper.getFileFromIndex(index);
    return Square(
      index: index,
      size: size,
      isLight: (rank + file) % 2 == 0,
      piece: pieceAt(index),
      isSelected: (selected >>> index) & 1 == 1,
      isLastMove: (marked >>> index) & 1 == 1,
      isMoveTarget: (targets >>> index) & 1 == 1,
      isDraggable: false,
      rankLabel: col == 0 ? BoardHelper.squareName(index)[1] : null,
      fileLabel: row == 7 ? BoardHelper.squareName(index)[0] : null,
      onDragStarted: () {},
      onTap: () => onTap(index),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Tab 1: attack tables and sliders
// ---------------------------------------------------------------------------------------------------------------

enum _Kind {
  knight('Knight', Piece.whiteKnight),
  king('King', Piece.whiteKing),
  whitePawn('White pawn', Piece.whitePawn),
  blackPawn('Black pawn', Piece.blackPawn),
  rook('Rook', Piece.whiteRook),
  bishop('Bishop', Piece.whiteBishop),
  queen('Queen', Piece.whiteQueen),
  between('Between (tap two squares)', Piece.none),
  line('Line (tap two squares)', Piece.none);

  final String label;
  final int piece;
  const _Kind(this.label, this.piece);

  bool get isTwoSquare => this == _Kind.between || this == _Kind.line;
  bool get isSlider => this == _Kind.rook || this == _Kind.bishop || this == _Kind.queen;
}

const _orthogonal = [
  [-1, 0],
  [1, 0],
  [0, 1],
  [0, -1],
];
const _diagonal = [
  [-1, 1],
  [1, 1],
  [1, -1],
  [-1, -1],
];

/// Reference implementation: walk each direction square by square until the first occupied square (inclusive).
int _naiveSlider(int sq, int occ, List<List<int>> dirs) {
  int result = 0;
  for (final d in dirs) {
    int rank = (sq >> 3) + d[0];
    int file = (sq & 7) + d[1];
    while (rank >= 0 && rank < 8 && file >= 0 && file < 8) {
      final bit = 1 << (rank * 8 + file);
      result |= bit;
      if (occ & bit != 0) break;
      rank += d[0];
      file += d[1];
    }
  }
  return result;
}

class _TablesTab extends StatefulWidget {
  const _TablesTab();

  @override
  State<_TablesTab> createState() => _TablesTabState();
}

class _TablesTabState extends State<_TablesTab> {
  final AttackTables _tables = AttackTables();
  late final Sliders _sliders = Sliders(_tables);
  final Random _random = Random();

  _Kind _kind = _Kind.knight;
  int _square = 36; // e4
  int _squareB = 27; // second square for the two-square modes (d5)
  bool _pickingSecond = false;
  bool _editBlockers = false;
  int _blockers = 0; // occupancy used by the slider kinds

  int _attacks() {
    final pair = _square * 64 + _squareB;
    return switch (_kind) {
      _Kind.knight => _tables.knightAttacks[_square],
      _Kind.king => _tables.kingAttacks[_square],
      _Kind.whitePawn => _tables.pawnAttacks[_square],
      _Kind.blackPawn => _tables.pawnAttacks[64 + _square],
      _Kind.rook => _sliders.rookAttacks(_square, _blockers),
      _Kind.bishop => _sliders.bishopAttacks(_square, _blockers),
      _Kind.queen => _sliders.queenAttacks(_square, _blockers),
      _Kind.between => _tables.between[pair],
      _Kind.line => _tables.line[pair],
    };
  }

  int _expectedSlider() {
    return switch (_kind) {
      _Kind.rook => _naiveSlider(_square, _blockers, _orthogonal),
      _Kind.bishop => _naiveSlider(_square, _blockers, _diagonal),
      _Kind.queen => _naiveSlider(_square, _blockers, _orthogonal) | _naiveSlider(_square, _blockers, _diagonal),
      _ => 0,
    };
  }

  void _tap(int index) {
    setState(() {
      if (_kind.isSlider && _editBlockers) {
        if (index != _square) _blockers ^= 1 << index;
      } else if (!_kind.isTwoSquare) {
        _square = index;
        _blockers &= ~(1 << index);
      } else if (_pickingSecond) {
        _squareB = index;
        _pickingSecond = false;
      } else {
        _square = index;
        _pickingSecond = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attacks = _attacks();
    final twoSquare = _kind.isTwoSquare;
    final showBlockers = _kind.isSlider;

    String? sliderCheck;
    if (showBlockers) {
      final expected = _expectedSlider();
      sliderCheck = expected == attacks
          ? 'Sliders match the naive walk'
          : 'MISMATCH. Sliders ${_hex(attacks)} vs naive ${_hex(expected)}';
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in _Kind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: k == _kind,
                      onSelected: (_) => setState(() {
                        _kind = k;
                        _pickingSecond = false;
                        _editBlockers = false;
                      }),
                    ),
                ],
              ),
              if (showBlockers) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('Edit blockers'),
                      selected: _editBlockers,
                      onSelected: (v) => setState(() => _editBlockers = v),
                    ),
                    OutlinedButton(onPressed: () => setState(() => _blockers = 0), child: const Text('Clear')),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _blockers = ((_random.nextInt(1 << 32) << 32) | _random.nextInt(1 << 32)) &
                            ((_random.nextInt(1 << 32) << 32) | _random.nextInt(1 << 32)) &
                            ~(1 << _square);
                      }),
                      child: const Text('Random blockers'),
                    ),
                    Text(_editBlockers ? 'Tap squares to toggle blockers' : 'Tap a square to move the piece'),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              _Grid(
                // Blockers are drawn as black pawns, the slider as its piece.
                pieceAt: (i) => i == _square
                    ? _kind.piece
                    : (showBlockers && (_blockers >>> i) & 1 == 1)
                        ? Piece.blackPawn
                        : Piece.none,
                targets: attacks,
                selected: (1 << _square) | (twoSquare ? 1 << _squareB : 0),
                marked: 0,
                onTap: _tap,
              ),
              const SizedBox(height: 16),
              Text(
                twoSquare
                    ? '${_kind == _Kind.line ? 'Line through' : 'Between'} ${BoardHelper.squareName(_square)} and '
                        '${BoardHelper.squareName(_squareB)} (index $_square, $_squareB)'
                    : '${_kind.label} on ${BoardHelper.squareName(_square)} (index $_square)',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${BitOps.popCount(attacks)} ${switch (_kind) {
                  _Kind.between => 'squares between',
                  _Kind.line => 'squares on the line',
                  _ => 'attacked squares',
                }}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              SelectableText(_hex(attacks), style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace')),
              if (showBlockers) ...[
                const SizedBox(height: 4),
                SelectableText('occ ${_hex(_blockers)}',
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Text(
                  sliderCheck!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: sliderCheck.startsWith('MISMATCH') ? Colors.red : Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Tab 2: real Board, make/unmake, invariants and fuzz
// ---------------------------------------------------------------------------------------------------------------

final _fuzzFens = [
  FenPosition.startingPosition,
  'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
  '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
  'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
  'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
  'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10',
];

/// Everything the board stores that make/unmake must put back exactly.
class _Snapshot {
  final Uint8List squares;
  final Uint64List pieceBB;
  final Uint64List colourBB;
  final int zobristKey;
  final bool whiteToPlay;
  final int enPassantSquare;
  final int castling;
  final int halfMove;
  final int plyCount;

  _Snapshot(Board b)
      : squares = Uint8List.fromList(b.squares),
        pieceBB = Uint64List.fromList(b.pieceBB),
        colourBB = Uint64List.fromList(b.colourBB),
        zobristKey = b.zobristKey,
        whiteToPlay = b.whiteToPlay,
        enPassantSquare = b.epSquare,
        castling = b.castling,
        halfMove = b.halfMove,
        plyCount = b.plyCount;

  /// Fields that differ from the board's current state (empty list = identical).
  List<String> diff(Board b) {
    final out = <String>[];
    for (int i = 0; i < 64; i++) {
      if (squares[i] != b.squares[i]) out.add('squares[${BoardHelper.squareName(i)}] ${squares[i]} -> ${b.squares[i]}');
    }
    for (int p = 0; p < pieceBB.length; p++) {
      if (pieceBB[p] != b.pieceBB[p]) out.add('pieceBB[$p] ${_hex(pieceBB[p])} -> ${_hex(b.pieceBB[p])}');
    }
    for (int c = 0; c < 2; c++) {
      if (colourBB[c] != b.colourBB[c]) out.add('colourBB[$c] ${_hex(colourBB[c])} -> ${_hex(b.colourBB[c])}');
    }
    if (zobristKey != b.zobristKey) out.add('zobristKey ${_hex(zobristKey)} -> ${_hex(b.zobristKey)}');
    if (whiteToPlay != b.whiteToPlay) out.add('whiteToPlay $whiteToPlay -> ${b.whiteToPlay}');
    if (enPassantSquare != b.epSquare) out.add('enPassantSquare $enPassantSquare -> ${b.epSquare}');
    if (castling != b.castling) out.add('castling $castling -> ${b.castling}');
    if (halfMove != b.halfMove) out.add('halfMove $halfMove -> ${b.halfMove}');
    if (plyCount != b.plyCount) out.add('plyCount $plyCount -> ${b.plyCount}');
    return out;
  }
}

/// Rebuilds the bitboards and Zobrist key from `squares` and compares them with the incrementally updated ones.
/// Returns the problems found and (via [mismatch]) a bitboard of squares involved in a bitboard disagreement.
List<String> _invariants(Board b, {void Function(int mismatch)? mismatch}) {
  final errors = <String>[];
  final rebuiltPieces = Uint64List(16);
  final rebuiltColours = Uint64List(2);
  for (int sq = 0; sq < 64; sq++) {
    final p = b.squares[sq];
    if (p == Piece.none) continue;
    rebuiltPieces[p] |= 1 << sq;
    rebuiltColours[p >> 3] |= 1 << sq;
  }

  int bad = 0;
  for (final p in Piece.pieceList) {
    if (rebuiltPieces[p] != b.pieceBB[p]) {
      bad |= rebuiltPieces[p] ^ b.pieceBB[p];
      errors.add('pieceBB[$p] is ${_hex(b.pieceBB[p])}, squares say ${_hex(rebuiltPieces[p])}');
    }
  }
  if (b.pieceBB[0] != 0) errors.add('pieceBB[0] (empty) is not 0: ${_hex(b.pieceBB[0])}');
  for (int c = 0; c < 2; c++) {
    if (rebuiltColours[c] != b.colourBB[c]) {
      bad |= rebuiltColours[c] ^ b.colourBB[c];
      errors.add('colourBB[$c] is ${_hex(b.colourBB[c])}, squares say ${_hex(rebuiltColours[c])}');
    }
  }
  if (b.colourBB[0] & b.colourBB[1] != 0) errors.add('colourBB overlap: ${_hex(b.colourBB[0] & b.colourBB[1])}');

  final scratchKey = Zobrist.getZobristForBoard(b);
  if (scratchKey != b.zobristKey) {
    errors.add('zobristKey ${_hex(b.zobristKey)} != from scratch ${_hex(scratchKey)}');
  }
  mismatch?.call(bad);
  return errors;
}

class _BoardTab extends StatefulWidget {
  const _BoardTab();

  @override
  State<_BoardTab> createState() => _BoardTabState();
}

class _BoardTabState extends State<_BoardTab> {
  static const int _overlayNone = -1;
  static const int _overlayOccupied = -2;
  static const int _overlayWhite = -3;
  static const int _overlayBlack = -4;

  final MoveGenerator _generator = MoveGenerator();
  final TextEditingController _fenController = TextEditingController(text: FenPosition.startingPosition);

  late Board _board;
  String _startFen = FenPosition.startingPosition;
  final List<Move> _played = [];
  final List<_Snapshot> _snapshots = []; // state before each played move
  List<Move> _legal = [];
  int _selected = -1;
  int _overlay = _overlayNone;
  String? _error;
  String? _fuzzReport;
  List<String> _repetitionLog = [];

  @override
  void initState() {
    super.initState();
    Zobrist.ensureInitialised();
    _load(FenPosition.startingPosition);
  }

  @override
  void dispose() {
    _fenController.dispose();
    super.dispose();
  }

  void _load(String fen) {
    try {
      final board = Board.fromFEN(fen);
      setState(() {
        _board = board;
        _startFen = fen;
        _played.clear();
        _snapshots.clear();
        _selected = -1;
        _error = null;
        _fuzzReport = null;
        _repetitionLog = [];
        _legal = _generator.generateLegalMoves(_board);
      });
    } catch (e) {
      setState(() => _error = 'Could not load FEN: $e');
    }
  }

  void _play(Move move) {
    setState(() {
      _snapshots.add(_Snapshot(_board));
      _board.makeMove(move);
      _played.add(move);
      _selected = -1;
      _legal = _generator.generateLegalMoves(_board);
    });
  }

  void _undo() {
    if (_played.isEmpty) return;
    setState(() {
      final move = _played.removeLast();
      final before = _snapshots.removeLast();
      _board.unMakeMove(move);
      final problems = before.diff(_board);
      _error = problems.isEmpty ? null : 'Undo of ${move.uci} did not restore:\n${problems.join('\n')}';
      _selected = -1;
      _legal = _generator.generateLegalMoves(_board);
    });
  }

  void _tap(int index) {
    if (_selected != -1) {
      final candidates = _legal.where((m) => m.from == _selected && m.to == index).toList();
      if (candidates.isNotEmpty) {
        // Auto-queen: promotion 1 is the queen.
        _play(candidates.firstWhere((m) => m.promotion <= 1, orElse: () => candidates.first));
        return;
      }
    }
    final piece = _board.squares[index];
    final ownPiece = piece != Piece.none && (piece >> 3 == 0) == _board.whiteToPlay;
    setState(() => _selected = ownPiece && index != _selected ? index : -1);
  }

  int _overlayBits() {
    final b = _board;
    if (_overlay == _overlayNone) return 0;
    if (_overlay == _overlayOccupied) return b.colourBB[0] | b.colourBB[1];
    if (_overlay == _overlayWhite) return b.colourBB[0];
    if (_overlay == _overlayBlack) return b.colourBB[1];
    return b.pieceBB[_overlay];
  }

  /// Plays the Nf3 Nf6 Ng1 Ng8 sequence from the start position and records isRepetition() after each ply.
  void _repetitionDemo() {
    final board = Board.fromFEN(FenPosition.startingPosition);
    final log = <String>[];
    for (final uci in ['g1f3', 'g8f6', 'f3g1', 'f6g8']) {
      final move = _generator.generateLegalMoves(board).firstWhere((m) => m.uci == uci);
      board.makeMove(move);
      log.add('$uci -> isRepetition: ${board.isRepetition()}');
    }
    setState(() => _repetitionLog = [...log, '(expected: false, false, false, true)']);
  }

  /// Random playouts from several FENs. After each makeMove the invariants are checked; at the end every move is
  /// unmade and the full state is compared with the snapshot taken before it.
  void _fuzz({int games = 40, int plies = 150}) {
    final random = Random(7);
    final generator = MoveGenerator();
    int movesChecked = 0;

    for (int g = 0; g < games; g++) {
      final fen = _fuzzFens[g % _fuzzFens.length];
      final board = Board.fromFEN(fen);
      final played = <Move>[];
      final snapshots = <_Snapshot>[];

      String failure(String what, List<String> details) {
        final path = played.map((m) => m.uci).join(' ');
        return 'FAILED in game $g ($what)\nFEN: $fen\nMoves: $path\n${details.take(8).join('\n')}';
      }

      for (int ply = 0; ply < plies; ply++) {
        final moves = generator.generateLegalMoves(board);
        if (moves.isEmpty) break;
        final move = moves[random.nextInt(moves.length)];
        snapshots.add(_Snapshot(board));
        board.makeMove(move);
        played.add(move);
        movesChecked++;

        final problems = _invariants(board);
        if (problems.isNotEmpty) {
          setState(() => _fuzzReport = failure('after makeMove ${move.uci}', problems));
          return;
        }
      }

      while (played.isNotEmpty) {
        final move = played.removeLast();
        final before = snapshots.removeLast();
        board.unMakeMove(move);
        movesChecked++;
        final problems = [...before.diff(board), ..._invariants(board)];
        if (problems.isNotEmpty) {
          played.add(move);
          setState(() => _fuzzReport = failure('after unMakeMove ${move.uci}', problems));
          return;
        }
      }
    }
    setState(() => _fuzzReport = 'OK: $games games, $movesChecked make/unmake steps, every invariant held.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = _board;

    int mismatch = 0;
    final invariantErrors = _invariants(b, mismatch: (m) => mismatch = m);
    final overlay = _overlayBits();
    final legalTargets =
        _selected == -1 ? 0 : _legal.where((m) => m.from == _selected).fold<int>(0, (acc, m) => acc | (1 << m.to));

    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final ok = invariantErrors.isEmpty && _error == null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fenController,
                      decoration: const InputDecoration(labelText: 'FEN', isDense: true),
                      onSubmitted: _load,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => _load(_fenController.text.trim()), child: const Text('Load')),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      _fenController.text = FenPosition.startingPosition;
                      _load(FenPosition.startingPosition);
                    },
                    child: const Text('Start'),
                  ),
                  OutlinedButton(onPressed: _played.isEmpty ? null : _undo, child: const Text('Undo')),
                  OutlinedButton(onPressed: () => _load(_startFen), child: const Text('Reset')),
                  OutlinedButton(onPressed: _repetitionDemo, child: const Text('Repetition demo')),
                  FilledButton.tonal(onPressed: _fuzz, child: const Text('Fuzz make/unmake')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Highlight bitboard: '),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _overlay,
                      items: [
                        const DropdownMenuItem(value: _overlayNone, child: Text('none (legal moves of selection)')),
                        const DropdownMenuItem(value: _overlayOccupied, child: Text('occupied (white | black)')),
                        const DropdownMenuItem(value: _overlayWhite, child: Text('colourBB[0] white')),
                        const DropdownMenuItem(value: _overlayBlack, child: Text('colourBB[1] black')),
                        for (final p in Piece.pieceList)
                          DropdownMenuItem(value: p, child: Text('pieceBB[$p] ${_name(p)}')),
                      ],
                      onChanged: (v) => setState(() => _overlay = v ?? _overlayNone),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Grid(
                // Pieces come from the mailbox. Red-ish squares are where the bitboards disagree with it.
                pieceAt: (i) => b.squares[i],
                targets: _overlay == _overlayNone ? legalTargets : overlay,
                selected: _selected == -1 ? 0 : 1 << _selected,
                marked: mismatch,
                onTap: _tap,
              ),
              const SizedBox(height: 12),
              Text(
                ok ? 'Invariants OK' : 'Invariants BROKEN',
                style: theme.textTheme.titleMedium?.copyWith(color: ok ? Colors.green : Colors.red),
              ),
              for (final e in invariantErrors) Text(e, style: mono?.copyWith(color: Colors.red)),
              if (_error != null) Text(_error!, style: mono?.copyWith(color: Colors.red)),
              const SizedBox(height: 8),
              Text('${b.whiteToPlay ? 'White' : 'Black'} to move, ${_legal.length} legal moves', style: mono),
              Text(
                'plyCount ${b.plyCount}  halfMove ${b.halfMove}  castling ${b.castling.toRadixString(2).padLeft(4, '0')}'
                '  ep ${b.epSquare == -1 ? '-' : BoardHelper.squareName(b.epSquare)}',
                style: mono,
              ),
              SelectableText('zobristKey ${_hex(b.zobristKey)}', style: mono),
              Text(
                'kingSquare: white ${BoardHelper.squareName(b.kingSquare(Piece.white))}, '
                'black ${BoardHelper.squareName(b.kingSquare(Piece.black))}',
                style: mono,
              ),
              Text('isRepetition(): ${b.isRepetition()}', style: mono),
              SelectableText('colourBB[0] ${_hex(b.colourBB[0])}', style: mono),
              SelectableText('colourBB[1] ${_hex(b.colourBB[1])}', style: mono),
              if (_played.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Moves: ${_played.map((m) => m.uci).join(' ')}', style: mono),
              ],
              if (_repetitionLog.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Repetition demo', style: theme.textTheme.titleSmall),
                for (final line in _repetitionLog) Text(line, style: mono),
              ],
              if (_fuzzReport != null) ...[
                const SizedBox(height: 8),
                Text('Fuzz', style: theme.textTheme.titleSmall),
                SelectableText(
                  _fuzzReport!,
                  style: mono?.copyWith(color: _fuzzReport!.startsWith('OK') ? Colors.green : Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _name(int piece) {
    const types = {1: 'king', 2: 'pawn', 3: 'knight', 4: 'bishop', 5: 'rook', 6: 'queen'};
    return '${piece >> 3 == 0 ? 'white' : 'black'} ${types[piece & 7]}';
  }
}
