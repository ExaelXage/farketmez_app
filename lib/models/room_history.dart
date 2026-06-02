import 'dart:convert';

class RoomHistoryEntry {
  final String roomCode;
  final String myNickname;
  final String winnerName;
  final String winnerAddress;
  final DateTime completedAt;
  final int participantCount;
  final bool didVoteForWinner;

  const RoomHistoryEntry({
    required this.roomCode,
    required this.myNickname,
    required this.winnerName,
    required this.winnerAddress,
    required this.completedAt,
    required this.participantCount,
    required this.didVoteForWinner,
  });

  Map<String, dynamic> toJson() => {
        'roomCode':          roomCode,
        'myNickname':        myNickname,
        'winnerName':        winnerName,
        'winnerAddress':     winnerAddress,
        'completedAt':       completedAt.toIso8601String(),
        'participantCount':  participantCount,
        'didVoteForWinner':  didVoteForWinner,
      };

  factory RoomHistoryEntry.fromJson(Map<String, dynamic> j) => RoomHistoryEntry(
        roomCode:         j['roomCode'] as String,
        myNickname:       j['myNickname'] as String,
        winnerName:       j['winnerName'] as String,
        winnerAddress:    j['winnerAddress'] as String,
        completedAt:      DateTime.parse(j['completedAt'] as String),
        participantCount: (j['participantCount'] as num).toInt(),
        didVoteForWinner: j['didVoteForWinner'] as bool,
      );

  static List<RoomHistoryEntry> listFromJson(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => RoomHistoryEntry.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<RoomHistoryEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());
}
