import 'package:ace/match/pgn_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses two headed games with their headers, moves and result', () {
    const pgn = '''
[Event "Test Event 1"]
[White "Alice"]
[Black "Bob"]

1. e4 e5 2. Nf3 Nc6 1-0

[Event "Test Event 2"]
[White "Carol"]
[Black "Dave"]

1. d4 d5 2. c4 e6 1/2-1/2
''';
    final games = PgnReader.parseMany(pgn);

    expect(games, hasLength(2));
    expect(games[0].headers['Event'], 'Test Event 1');
    expect(games[0].headers['White'], 'Alice');
    expect(games[0].sanMoves, ['e4', 'e5', 'Nf3', 'Nc6']);
    expect(games[0].result, '1-0');
    expect(games[1].headers['White'], 'Carol');
    expect(games[1].sanMoves, ['d4', 'd5', 'c4', 'e6']);
    expect(games[1].result, '1/2-1/2');
  });

  test('splits header-less games on the result token', () {
    const pgn = '1. e4 e5 2. Nf3 * 1. d4 d5 *';
    final games = PgnReader.parseMany(pgn);

    expect(games, hasLength(2));
    expect(games[0].sanMoves, ['e4', 'e5', 'Nf3']);
    expect(games[0].result, '*');
    expect(games[1].sanMoves, ['d4', 'd5']);
    expect(games[1].result, '*');
  });

  test('skips comments, nested variations, NAGs and line comments', () {
    const pgn = '1. e4 {best by test} e5 (1... c5 2. Nf3 (2. c3)) 2. Nf3 \$1 ; comment';
    final games = PgnReader.parseMany(pgn);

    expect(games, hasLength(1));
    expect(games.single.sanMoves, ['e4', 'e5', 'Nf3']);
  });

  test('parses move numbers with no space after the dot, and black move numbers', () {
    const pgn = '1.e4 e5 2.Nf3 Nc6 3... Nf6';
    final games = PgnReader.parseMany(pgn);

    expect(games.single.sanMoves, ['e4', 'e5', 'Nf3', 'Nc6', 'Nf6']);
  });

  test('skips a multi-line comment', () {
    const pgn = '1. e4 e5 {this is\na multi-line comment} 2. Nf3\n*';
    final games = PgnReader.parseMany(pgn);

    expect(games.single.sanMoves, ['e4', 'e5', 'Nf3']);
    expect(games.single.result, '*');
  });
}
