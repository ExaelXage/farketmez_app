import 'package:dio/dio.dart';

/// Converts a network/server exception to a user-friendly Turkish message.
String toTurkishError(Object e) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionError:
        return 'İnternet bağlantınızı kontrol edin';
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return 'Sunucuya bağlanılamıyor, lütfen tekrar deneyin';
      case DioExceptionType.receiveTimeout:
        return 'Sunucu yanıt vermiyor, tekrar deneyin';
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        final data   = e.response?.data;
        if (data is Map && data['error'] != null) return data['error'].toString();
        return switch (status) {
          400       => 'Geçersiz istek',
          401       => 'Oturum süresi doldu, tekrar giriş yapın',
          403       => 'Bu işlem için yetkiniz yok',
          404       => 'Oda bulunamadı',
          409       => 'Bu isim zaten kullanılıyor',
          500       => 'Sunucu hatası, lütfen tekrar deneyin',
          502 || 503 || 504 => 'Sunucuya ulaşılamıyor, birazdan tekrar deneyin',
          _         => 'Bir hata oluştu (${status ?? "bilinmiyor"})',
        };
      case DioExceptionType.cancel:
        return 'İstek iptal edildi';
      default:
        return 'Bağlantı hatası, tekrar deneyin';
    }
  }
  return 'Beklenmedik bir hata oluştu';
}

bool isConnectionError(Object e) {
  if (e is DioException) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout;
  }
  return false;
}
