import 'package:ace/chess_core/notation/fen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FenPosition round trip', () {
    final cases = {
      'starting position': FenPosition.startingPosition,
      'Kiwipete': 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      'en passant': 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
      'no castling rights': '4k3/8/8/8/8/8/8/4K3 w - - 0 1',
      'custom clocks': '4k3/8/8/8/8/8/8/4K3 w - - 37 80',
    };

    cases.forEach((name, fen) {
      test(name, () {
        expect(FenPosition.parse(fen).toFen(), fen);
      });
    });
  });

  test('a 4-field FEN parses with default clocks', () {
    final parsed = FenPosition.parse('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -');
    expect(parsed.halfmoveClock, 0);
    expect(parsed.fullmoveNumber, 1);
  });
}
