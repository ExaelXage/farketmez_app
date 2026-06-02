import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static bool _initialized = false;
  static String? _token;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _initialized = true;
      debugPrint('[FCM] Firebase başlatıldı');
    } catch (e) {
      debugPrint('[FCM] Firebase başlatılamadı (google-services.json eksik olabilir): $e');
    }
  }

  static Future<String?> getToken() async {
    if (_token != null) return _token;
    try {
      if (!_initialized) await init();
      _token = await FirebaseMessaging.instance.getToken();
      debugPrint('[FCM] Token: ${_token?.substring(0, 20)}...');
      return _token;
    } catch (e) {
      debugPrint('[FCM] Token alınamadı: $e');
      return null;
    }
  }
}
