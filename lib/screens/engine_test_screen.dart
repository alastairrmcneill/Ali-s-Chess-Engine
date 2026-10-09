import 'dart:isolate';

import 'package:ace/chess_core/notation/board_helper.dart';
import 'package:ace/chess_core/notation/uci.dart';
import 'package:ace/chess_core/rules/board.dart';
import 'package:ace/chess_core/rules/move.dart';
import 'package:ace/chess_core/rules/move_generator.dart';
import 'package:ace/chess_core/notation/piece.dart';
import 'package:ace/chess_core/rules/zobrist.dart';
import 'package:ace/components/piece_image.dart';
import 'package:ace/components/square.dart';
import 'package:ace/engines/engine_interface.dart';
import 'package:ace/engines/engine_registry.dart';
import 'package:flutter/material.dart';

const _startFen = 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1';

class _SearchResult {
  final int? nodes;
  final int? eval; // centipawns, white's point of view
  final Duration elapsed;
  final String bestMove;
  final int? depth;
  final SearchStats? stats;

  const _SearchResult(this.nodes, this.eval, this.elapsed, this.bestMove, this.depth, this.stats);
}

bool _zobristReady = false;

String _uci(Move move) => UciMove(
      from: move.startingSquare,
      to: move.targetSquare,
      promotion: move.promotion == 0 ? null : ' qnrb'[move.promotion],
    ).toString();

/// Builds the position after [uciMoves] from [startFen]. Throws if a move is not legal.
Board _replay(String startFen, List<String> uciMoves) {
  if (!_zobristReady) {
    Zobrist();
    _zobristReady = true;
  }
  final board = Board.fromFEN(startFen);
  final generator = MoveGenerator();
  for (final uci in uciMoves) {
    final move = generator.generateLegalMoves(board).where((m) => _uci(m) == uci).firstOrNull;
    if (move == null) throw StateError('Illegal move $uci');
    board.makeMove(move);
  }
  return board;
}

_SearchResult _runSearch(String engineId, String startFen, List<String> uciMoves, int depth) {
  final engine = EngineRegistry.create(engineId)..newGame();
  final stopwatch = Stopwatch()..start();
  final result = engine.getMove(startFen, uciMoves, SearchLimits(moveTime: const Duration(minutes: 10), depth: depth));
  stopwatch.stop();
  return _SearchResult(result.nodes, result.evaluation, stopwatch.elapsed, result.uciMove, result.depth, result.stats);
}

/// Top level so the isolate closure cannot capture the widget state, which is not sendable.
Future<_SearchResult> _searchInIsolate(String engineId, String startFen, List<String> uciMoves, int depth) =>
    Isolate.run(() => _runSearch(engineId, startFen, uciMoves, depth));

String? _fenProblem(String fen) {
  final parts = fen.split(' ');
  if (parts.length < 2) return 'needs at least pieces and side to move';
  final ranks = parts[0].split('/');
  if (ranks.length != 8) return 'needs 8 ranks, found ${ranks.length}';
  for (final rank in ranks) {
    var squares = 0;
    for (final c in rank.split('')) {
      squares += int.tryParse(c) ?? 1;
    }
    if (squares != 8) return 'rank "$rank" has $squares squares';
  }
  return null;
}

class EngineTestScreen extends StatefulWidget {
  final String engineId;

  const EngineTestScreen({super.key, required this.engineId});

  @override
  State<EngineTestScreen> createState() => _EngineTestScreenState();
}

class _EngineTestScreenState extends State<EngineTestScreen> {
  final _fenController = TextEditingController(text: _startFen);
  final _generator = MoveGenerator();

  late String _rootFen;
  late Board _board;
  List<Move> _legalMoves = [];
  final List<Move> _played = [];
  final List<String> _playedUci = [];

  int _depth = 3;
  bool _playerIsWhite = true;
  bool _autoReply = true;
  bool _flipped = false;
  bool _thinking = false;
  int? _selected;
  String? _error;
  _SearchResult? _result;

  /// Bumped whenever the position is replaced, so a search that finishes late is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadFen(_startFen, notify: false);
  }

  @override
  void dispose() {
    _fenController.dispose();
    super.dispose();
  }

  String get _engineName => EngineRegistry.create(widget.engineId).displayName;

  bool get _whiteToPlay => _board.whiteToPlay;
  bool get _humanTurn => !_thinking && _legalMoves.isNotEmpty && _whiteToPlay == _playerIsWhite;

  String? get _gameOver {
    if (_legalMoves.isNotEmpty) return null;
    if (!_inCheck) return 'Stalemate';
    return _whiteToPlay ? 'Checkmate - Black wins' : 'Checkmate - White wins';
  }

  bool _inCheck = false;

  void _refreshLegal() {
    _legalMoves = _generator.generateLegalMoves(_board);
    _inCheck = _generator.inCheck;
  }

  void _loadFen(String fen, {bool notify = true}) {
    try {
      final problem = _fenProblem(fen);
      if (problem != null) throw FormatException(problem);
      _replay(fen, const []);
    } catch (e) {
      setState(() => _error = 'Bad FEN: $e');
      return;
    }
    _generation++;
    _rootFen = fen;
    _board = _replay(fen, const []);
    _played.clear();
    _playedUci.clear();
    _selected = null;
    _thinking = false;
    _result = null;
    _error = null;
    _refreshLegal();
    if (notify) {
      setState(() {});
      _maybeEngineReply();
    }
  }

  void _applyMove(Move move) {
    _board.makeMove(move);
    _played.add(move);
    _playedUci.add(_uci(move));
    _selected = null;
    _refreshLegal();
    setState(() {});
    _maybeEngineReply();
  }

  void _undo() {
    if (_played.isEmpty) return;
    // Undo the engine reply as well, so it is the human's turn again.
    final count = _autoReply && _played.length >= 2 && _whiteToPlay == _playerIsWhite ? 2 : 1;
    _generation++;
    for (int i = 0; i < count && _played.isNotEmpty; i++) {
      _board.unMakeMove(_played.removeLast());
      _playedUci.removeLast();
    }
    _thinking = false;
    _selected = null;
    _refreshLegal();
    setState(() {});
  }

  void _maybeEngineReply() {
    if (_autoReply && _gameOver == null && _whiteToPlay != _playerIsWhite) _engineMove();
  }

  Future<void> _engineMove() async {
    if (_thinking || _legalMoves.isEmpty) return;
    final generation = ++_generation;
    final startFen = _rootFen;
    final moves = List.of(_playedUci);
    final depth = _depth;
    setState(() {
      _thinking = true;
      _selected = null;
      _error = null;
    });
    try {
      final result = await _searchInIsolate(widget.engineId, startFen, moves, depth);
      if (!mounted || generation != _generation) return;
      final move = _legalMoves.where((m) => _uci(m) == result.bestMove).firstOrNull;
      _result = result;
      _thinking = false;
      if (move == null) {
        setState(() => _error = 'Engine returned no legal move');
        return;
      }
      _applyMove(move);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _thinking = false;
        _error = e.toString();
      });
    }
  }

  List<Move> _movesBetween(int from, int to) =>
      _legalMoves.where((m) => m.startingSquare == from && m.targetSquare == to).toList();

  bool _canPickUp(int index) {
    if (!_humanTurn) return false;
    final piece = _board.position[index];
    return piece != Piece.none && Piece.isColor(piece, _whiteToPlay ? Piece.white : Piece.black);
  }

  Future<void> _attemptMove(int from, int to) async {
    final moves = _movesBetween(from, to);
    if (moves.isEmpty) return;
    Move? chosen = moves.first;
    if (moves.length > 1) chosen = await _pickPromotion(moves);
    if (chosen == null) {
      setState(() => _selected = null);
      return;
    }
    _applyMove(chosen);
  }

  Future<Move?> _pickPromotion(List<Move> moves) {
    const order = [1, 3, 4, 2];
    final sorted = [...moves]..sort((a, b) => order.indexOf(a.promotion).compareTo(order.indexOf(b.promotion)));
    final color = _whiteToPlay ? Piece.white : Piece.black;

    return showDialog<Move>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Promote to'),
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              for (final move in sorted)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).pop(move),
                  child: SizedBox(width: 64, height: 64, child: pieceImage(move.promotingPiece() | color)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    final last = _played.lastOrNull;

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
                      for (int col = 0; col < 8; col++)
                        _buildSquare(_flipped ? 63 - (row * 8 + col) : row * 8 + col, row, col, size, last),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSquare(int index, int row, int col, double size, Move? last) {
    final rank = BoardHelper.getRankFromIndex(index);
    final file = BoardHelper.getFileFromIndex(index);
    final from = _selected;

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => _humanTurn && _movesBetween(details.data, index).isNotEmpty,
      onAcceptWithDetails: (details) => _attemptMove(details.data, index),
      builder: (context, candidates, rejected) => Square(
        index: index,
        size: size,
        isLight: (rank + file) % 2 == 0,
        piece: _board.position[index],
        isSelected: index == from,
        isLastMove: last != null && (index == last.startingSquare || index == last.targetSquare),
        isMoveTarget: from != null && _humanTurn && _movesBetween(from, index).isNotEmpty,
        isDraggable: _canPickUp(index),
        rankLabel: col == 0 ? BoardHelper.squareName(index)[1] : null,
        fileLabel: row == 7 ? BoardHelper.squareName(index)[0] : null,
        onDragStarted: () {
          if (_canPickUp(index) && _selected != index) setState(() => _selected = index);
        },
        onTap: () {
          if (from != null && _humanTurn && _movesBetween(from, index).isNotEmpty) {
            _attemptMove(from, index);
          } else {
            setState(() => _selected = _canPickUp(index) && _selected != index ? index : null);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final over = _gameOver;
    final status = over ??
        (_thinking
            ? '${widget.engineId} thinking...'
            : _whiteToPlay == _playerIsWhite
                ? 'Your move'
                : '${widget.engineId} to move');

    return Scaffold(
      appBar: AppBar(title: Text('$_engineName test')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBoard(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_thinking)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      Expanded(child: Text(status, style: theme.textTheme.titleMedium)),
                      IconButton(
                        tooltip: 'Flip board',
                        onPressed: () => setState(() => _flipped = !_flipped),
                        icon: const Icon(Icons.swap_vert_rounded),
                      ),
                      IconButton(
                        tooltip: 'Undo',
                        onPressed: _played.isEmpty ? null : _undo,
                        icon: const Icon(Icons.undo_rounded),
                      ),
                    ],
                  ),
                  if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _row(theme, 'Depth', result == null ? '-' : '${result.depth ?? '-'}'),
                                _row(theme, 'Time', result == null ? '-' : '${result.elapsed.inMilliseconds} ms'),
                                _row(theme, 'Nodes', result == null ? '-' : '${result.nodes ?? '-'}'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              children: [
                                _row(theme, 'Nodes/s', result == null ? '-' : _nps(result)),
                                _row(theme, 'Best move', result?.bestMove ?? '-'),
                                _row(theme, 'Eval', result == null ? '-' : '${result.eval ?? '-'}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (result?.stats case final stats?) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  _row(theme, 'Q nodes', '${stats.qNodes}'),
                                  _row(theme, 'Evals', '${stats.evaluations}'),
                                  _row(theme, 'Max Q depth', '${stats.maxQDepth}'),
                                  _row(theme, 'Q check nodes', '${stats.qCheckNodes}'),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                children: [
                                  _row(theme, 'Beta cutoffs', '${stats.betaCutoffs}'),
                                  _row(theme, 'Q cutoffs', '${stats.qBetaCutoffs}'),
                                  _row(theme, '1st move', _firstMovePercent(stats)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text('Depth', style: theme.textTheme.labelLarge)),
                              Text('$_depth', style: theme.textTheme.titleSmall),
                            ],
                          ),
                          Slider(
                            value: _depth.toDouble(),
                            min: 1,
                            max: 8,
                            divisions: 7,
                            onChanged: (v) => setState(() => _depth = v.round()),
                          ),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: true, label: Text('Play white')),
                              ButtonSegment(value: false, label: Text('Play black')),
                            ],
                            selected: {_playerIsWhite},
                            onSelectionChanged: (s) {
                              setState(() {
                                _playerIsWhite = s.first;
                                _flipped = !_playerIsWhite;
                              });
                              _maybeEngineReply();
                            },
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Engine replies automatically'),
                            value: _autoReply,
                            onChanged: (v) {
                              setState(() => _autoReply = v);
                              _maybeEngineReply();
                            },
                          ),
                          FilledButton.icon(
                            onPressed: _thinking || over != null ? null : _engineMove,
                            icon: const Icon(Icons.memory_rounded),
                            label: const Text('Make engine move for side to move'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Position (FEN)', style: theme.textTheme.labelLarge),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _fenController,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _loadFen(_fenController.text.trim()),
                                  child: const Text('Set position'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    _fenController.text = _startFen;
                                    _loadFen(_startFen);
                                  },
                                  child: const Text('Reset'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _nps(_SearchResult r) {
    final seconds = r.elapsed.inMicroseconds / 1e6;
    final nodes = r.nodes;
    return seconds == 0 || nodes == null ? '-' : (nodes / seconds).round().toString();
  }

  String _firstMovePercent(SearchStats s) =>
      s.betaCutoffs == 0 ? '-' : '${(100 * s.firstMoveCutoffs / s.betaCutoffs).toStringAsFixed(1)}%';

  Widget _row(ThemeData theme, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
            Text(value, style: theme.textTheme.titleMedium),
          ],
        ),
      );
}
