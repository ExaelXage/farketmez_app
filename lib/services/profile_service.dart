import 'package:shared_preferences/shared_preferences.dart';
import '../models/room_history.dart';

class ProfileService {
  static const _nicknameKey = 'user_nickname';
  static const _historyKey  = 'room_history';
  static const _maxHistory  = 30;

  static Future<String?> getNickname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nicknameKey);
  }

  static Future<void> saveNickname(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nicknameKey, nickname.trim());
  }

  static Future<List<RoomHistoryEntry>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return [];
    return RoomHistoryEntry.listFromJson(raw);
  }

  static Future<void> addToHistory(RoomHistoryEntry entry) async {
    final prefs   = await SharedPreferences.getInstance();
    final history = await getHistory();
    // Newest first; cap at _maxHistory
    history.insert(0, entry);
    if (history.length > _maxHistory) history.removeRange(_maxHistory, history.length);
    await prefs.setString(_historyKey, RoomHistoryEntry.listToJson(history));
  }

  static Future<({int totalRooms, int wins, int totalParticipants})> getStats() async {
    final history = await getHistory();
    final wins = history.where((e) => e.didVoteForWinner).length;
    final totalParticipants = history.fold<int>(0, (sum, e) => sum + e.participantCount);
    return (
      totalRooms:         history.length,
      wins:               wins,
      totalParticipants:  totalParticipants,
    );
  }
}
