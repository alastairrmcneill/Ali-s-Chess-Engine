import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/components/square.dart';
import 'package:ace/engines/v12/core/attack_tables.dart';
import 'package:ace/engines/v12/core/bitboard.dart';
import 'package:flutter/material.dart';

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

  /// Attack bitboard from [sq] using the v12 tables.
  int attacks(AttackTables t, int sq) => switch (this) {
        _Kind.knight => t.knightAttacks[sq],
        _Kind.king => t.kingAttacks[sq],
        _Kind.whitePawn => t.pawnAttacks[sq],
        _Kind.blackPawn => t.pawnAttacks[64 + sq],
        // rays is indexed sq * 8 + dir; dirs 0-3 are orthogonal (N, E, S, W), 4-7 diagonal (NE, SE, SW, NW)
        _Kind.rook => _rays(t, sq, 0, 4),
        _Kind.bishop => _rays(t, sq, 4, 4),
        _Kind.queen => _rays(t, sq, 0, 8),
        _Kind.between ||
        _Kind.line =>
          0, // two-square modes are handled by the screen
      };
}

int _rays(AttackTables t, int sq, int firstDir, int count) {
  int b = 0;
  for (int i = 0; i < count; i++) {
    b |= t.rays[sq * 8 + firstDir + i];
  }
  return b;
}

/// Debug screen: pick a piece type, tap a square, and see the bitboard attack squares from the v12 tables.
class BitboardTestScreen extends StatefulWidget {
  const BitboardTestScreen({super.key});

  @override
  State<BitboardTestScreen> createState() => _BitboardTestScreenState();
}

class _BitboardTestScreenState extends State<BitboardTestScreen> {
  final AttackTables _tables = AttackTables();
  _Kind _kind = _Kind.knight;
  int _square = 36; // e4
  int _squareB = 27; // second square for the two-square modes (d5)
  bool _pickingSecond =
      false; // two-square modes: next tap sets the second square

  String _hex(int b) {
    final hi = (b >>> 32).toRadixString(16).padLeft(8, '0');
    final lo = (b & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '0x$hi$lo';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final twoSquare = _kind.isTwoSquare;
    final pair = _square * 64 + _squareB;
    final attacks = switch (_kind) {
      _Kind.between => _tables.between[pair],
      _Kind.line => _tables.line[pair],
      _ => _kind.attacks(_tables, _square),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Bitboard attack tables')),
      body: SafeArea(
        child: Center(
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
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AspectRatio(
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
                                    for (int col = 0; col < 8; col++)
                                      _buildSquare(row * 8 + col, row, col,
                                          size, attacks),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
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
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  SelectableText(_hex(attacks),
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSquare(int index, int row, int col, double size, int attacks) {
    final rank = BoardHelper.getRankFromIndex(index);
    final file = BoardHelper.getFileFromIndex(index);
    return Square(
      index: index,
      size: size,
      isLight: (rank + file) % 2 == 0,
      piece: index == _square ? _kind.piece : Piece.none,
      isSelected: index == _square || (_kind.isTwoSquare && index == _squareB),
      isLastMove: false,
      isMoveTarget: (attacks >>> index) & 1 == 1,
      isDraggable: false,
      rankLabel: col == 0 ? BoardHelper.squareName(index)[1] : null,
      fileLabel: row == 7 ? BoardHelper.squareName(index)[0] : null,
      onDragStarted: () {},
      onTap: () => setState(() {
        if (!_kind.isTwoSquare) {
          _square = index;
        } else if (_pickingSecond) {
          _squareB = index;
          _pickingSecond = false;
        } else {
          _square = index;
          _pickingSecond = true;
        }
      }),
    );
  }
}
