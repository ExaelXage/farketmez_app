import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Cihaza özgü, kalıcı bir kimlik üretir ve SharedPreferences'ta saklar.
/// Backend bu ID'yi device_id + nickname + room kodu eşleşmesiyle aynı
/// katılımcıyı tanımak (ör. uygulama kapanıp yeniden açıldığında "isim
/// kullanılıyor" hatası vermemek) için kullanabilir.
class DeviceService {
  static const _key = 'device_id';
  static String? _cached;

  static Future<String> getDeviceId() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.isEmpty) {
      id = _generateUuidV4();
      await prefs.setString(_key, id);
    }
    _cached = id;
    return id;
  }

  static String _generateUuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10xx
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}
