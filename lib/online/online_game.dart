enum OnlineGameStatus { waiting, active, finished, cancelled }

/// One row of the `online_games` table.
class OnlineGame {
  final String id;
  final String code;
  final String createdBy;
  final String? whiteId;
  final String? blackId;
  final String? whiteName;
  final String? blackName;
  final OnlineGameStatus status;

  /// Every move so far in UCI notation, from the standard starting position.
  final List<String> moves;

  /// PGN style result ("1-0", "0-1" or "1/2-1/2") once the game is finished.
  final String? result;

  /// Why the game finished: a [GameTermination] name, 'resignation' or 'agreement'.
  final String? termination;
  final String? drawOfferedBy;
  final DateTime updatedAt;

  const OnlineGame({
    required this.id,
    required this.code,
    required this.createdBy,
    this.whiteId,
    this.blackId,
    this.whiteName,
    this.blackName,
    required this.status,
    required this.moves,
    this.result,
    this.termination,
    this.drawOfferedBy,
    required this.updatedAt,
  });

  factory OnlineGame.fromJson(Map<String, dynamic> json) => OnlineGame(
        id: json['id'] as String,
        code: json['code'] as String,
        createdBy: json['created_by'] as String,
        whiteId: json['white_id'] as String?,
        blackId: json['black_id'] as String?,
        whiteName: json['white_name'] as String?,
        blackName: json['black_name'] as String?,
        status: OnlineGameStatus.values.byName(json['status'] as String),
        moves: List<String>.from(json['moves'] as List? ?? const []),
        result: json['result'] as String?,
        termination: json['termination'] as String?,
        drawOfferedBy: json['draw_offered_by'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  bool isWhite(String userId) => whiteId == userId;
  String? opponentName(String userId) => isWhite(userId) ? blackName : whiteName;
}
