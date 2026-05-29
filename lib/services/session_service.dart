import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static String _key(String roomCode) => 'session_$roomCode';

  static Future<void> save({
    required String roomCode,
    required String token,
    required String nickname,
    required bool isHost,
    required String category,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(roomCode), jsonEncode({
      'token':    token,
      'nickname': nickname,
      'isHost':   isHost,
      'category': category,
    }));
  }

  static Future<Map<String, dynamic>?> load(String roomCode) async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_key(roomCode));
    if (str == null) return null;
    try {
      return jsonDecode(str) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String roomCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(roomCode));
  }
}
