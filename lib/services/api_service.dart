import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/place.dart';
import 'device_service.dart';

class ApiService {
  static const String baseUrl = 'https://farketmez-ls1o.onrender.com';
  static const int _maxRetries = 3;

  // text/plain → basit istek (simple request) → tarayıcı preflight OPTIONS
  // göndermez → CORS sorunu yaşanmaz. Flask get_json(force=True) bunu okur.
  static final _plainOpts = Options(contentType: 'text/plain');

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  ));

  io.Socket? socket;
  String? _token;
  final Map<String, (DateTime, Map<String, dynamic>)> _roomCache = {};

  ApiService() {
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        responseHeader: false,
        error: true,
        logPrint: (o) => debugPrint('[DIO] $o'),
      ));
    }
    // Cihaz ID'sini en başta önbelleğe al; createRoom/joinRoom çağrıldığında
    // ayrıca beklemeye gerek kalmaz (splash ekranı zaten birkaç saniye sürer).
    DeviceService.getDeviceId();
  }

  void _setToken(String token) {
    _token = token;
    // ignore: avoid_print
    print('[API] Token kaydedildi: ${token.substring(0, 8)}... (toplam ${token.length} karakter)');
  }

  /// JSON body'ye token ekle ve string olarak kodla (text/plain için)
  String _body(Map<String, dynamic> data) {
    if (_token != null) {
      data['token'] = _token;
    } else {
      // ignore: avoid_print
      print('[API] UYARI: _body() çağrıldı ama _token null! Kimlik doğrulaması başarısız olabilir.');
    }
    return jsonEncode(data);
  }

  // ── REST API ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createRoom({
    required String nickname,
    required String category,
    double? lat,
    double? lng,
  }) async {
    final deviceId = await DeviceService.getDeviceId();
    // ignore: avoid_print
    print('[FARKETMEZ] POST $baseUrl/api/rooms  nickname=$nickname category=$category');
    final response = await _dio.post(
      '/api/rooms',
      data: _body({
        'nickname': nickname,
        'category': category,
        'device_id': deviceId,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      }),
      options: _plainOpts,
    );
    // ignore: avoid_print
    print('[FARKETMEZ] createRoom -> ${response.statusCode}');
    final data = Map<String, dynamic>.from(response.data);
    if (data['token'] != null) _setToken(data['token']);
    return data;
  }

  Future<Map<String, dynamic>> joinRoom({
    required String code,
    required String nickname,
  }) async {
    final deviceId = await DeviceService.getDeviceId();
    // ignore: avoid_print
    print('[FARKETMEZ] POST $baseUrl/api/rooms/$code/join  nickname=$nickname');
    final response = await _dio.post(
      '/api/rooms/$code/join',
      data: _body({'nickname': nickname, 'device_id': deviceId}),
      options: _plainOpts,
    );
    // ignore: avoid_print
    print('[FARKETMEZ] joinRoom -> ${response.statusCode}');
    final data = Map<String, dynamic>.from(response.data);
    if (data['token'] != null) _setToken(data['token']);
    return data;
  }

  Future<List<Place>> searchPlaces({
    required String code,
    required double lat,
    required double lng,
    int radius = 2000,
    void Function(int attempt)? onRetry,
  }) async {
    final url = '$baseUrl/api/flutter/room/$code/search';
    final bodyStr = _body({'lat': lat, 'lng': lng, 'radius': radius});
    // ignore: avoid_print
    print('╔═══ [FARKETMEZ] searchPlaces ════════════════════════');
    // ignore: avoid_print
    print('║ URL         : POST $url');
    // ignore: avoid_print
    print('║ ContentType : text/plain');
    // ignore: avoid_print
    print('║ Token durum : ${_token != null ? "VAR → ${_token!.substring(0, 8)}..." : "NULL ❌ - kimlik doğrulanamaz!"}');
    // ignore: avoid_print
    print('║ Body        : $bodyStr');
    // ignore: avoid_print
    print('╚═════════════════════════════════════════════════════');

    DioException? lastError;

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        if (attempt > 1) {
          onRetry?.call(attempt);
          // ignore: avoid_print
          print('[FARKETMEZ] Retry $attempt/$_maxRetries ...');
          await Future.delayed(const Duration(seconds: 3));
        }

        final response = await _dio.post(
          '/api/flutter/room/$code/search',
          data: bodyStr,
          options: _plainOpts,
        );

        // ignore: avoid_print
        print('[FARKETMEZ] searchPlaces -> ${response.statusCode}');
        final data = Map<String, dynamic>.from(response.data);
        final List raw = data['places'] ?? [];
        final places =
            raw.map((p) => Place.fromJson(Map<String, dynamic>.from(p))).toList();
        // ignore: avoid_print
        print('[FARKETMEZ] ${places.length} mekan yuklendi');
        return places;
      } on DioException catch (e) {
        lastError = e;
        // ignore: avoid_print
        print('[FARKETMEZ] HATA attempt=$attempt type=${e.type} '
            'status=${e.response?.statusCode} body=${e.response?.data}');
        if (attempt == _maxRetries) break;
        if (e.type != DioExceptionType.connectionTimeout &&
            e.type != DioExceptionType.receiveTimeout &&
            e.type != DioExceptionType.connectionError) {
          break;
        }
      } catch (e) {
        // ignore: avoid_print
        print('[FARKETMEZ] Unexpected: $e');
        rethrow;
      }
    }
    throw lastError ?? Exception('Mekan araması başarısız');
  }

  // ── Overpass API ────────────────────────────────────────────────────────────

  static String _buildOverpassQuery(
      List<String> categories, double lat, double lng, int radius) {
    final sb = StringBuffer('[out:json][timeout:25];\n(\n');
    final all = categories.isEmpty || categories.contains('Tümü');

    void add(String q) => sb.writeln('  $q');

    if (all) {
      add('node["amenity"~"restaurant|cafe|fast_food"](around:$radius,$lat,$lng);');
      add('way["amenity"~"restaurant|cafe|fast_food"](around:$radius,$lat,$lng);');
    } else {
      for (final cat in categories) {
        switch (cat) {
          case 'Pizza':
            add('node["amenity"~"restaurant|fast_food"]["name"~"pizza",i](around:$radius,$lat,$lng);');
            add('node["amenity"~"restaurant|fast_food"]["cuisine"~"pizza",i](around:$radius,$lat,$lng);');
            add('way["amenity"~"restaurant|fast_food"]["cuisine"~"pizza",i](around:$radius,$lat,$lng);');
          case 'Burger':
            add('node["amenity"~"restaurant|fast_food"]["name"~"burger",i](around:$radius,$lat,$lng);');
            add('node["amenity"~"restaurant|fast_food"]["cuisine"~"burger|hamburger",i](around:$radius,$lat,$lng);');
          case 'Kebap':
            add('node["amenity"~"restaurant|fast_food"]["name"~"kebap|kebab|d\\u00f6ner|doner",i](around:$radius,$lat,$lng);');
            add('node["amenity"~"restaurant|fast_food"]["cuisine"~"kebab|doner|turkish",i](around:$radius,$lat,$lng);');
          case 'Kafe':
            add('node["amenity"="cafe"](around:$radius,$lat,$lng);');
            add('way["amenity"="cafe"](around:$radius,$lat,$lng);');
          case 'Steak':
            add('node["amenity"="restaurant"]["name"~"steak",i](around:$radius,$lat,$lng);');
            add('node["amenity"="restaurant"]["cuisine"~"steak_house|steak",i](around:$radius,$lat,$lng);');
          case 'Fastfood':
            add('node["amenity"="fast_food"](around:$radius,$lat,$lng);');
            add('way["amenity"="fast_food"](around:$radius,$lat,$lng);');
        }
      }
    }

    sb.write(');\nout center;');
    return sb.toString();
  }

  Future<List<Place>> searchPlacesOverpass({
    required double lat,
    required double lng,
    int radius = 2000,
    List<String> categories = const [],
    Set<int> excludeIds = const {},
  }) async {
    final query = _buildOverpassQuery(categories, lat, lng, radius);
    // ignore: avoid_print
    print('[OVERPASS] lat=$lat lng=$lng radius=$radius cats=${categories.isEmpty ? "Tümü" : categories.join(",")}');

    final overpassDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));

    final response = await overpassDio.post(
      'https://overpass-api.de/api/interpreter',
      data: 'data=${Uri.encodeComponent(query)}',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        headers: {'Accept': 'application/json'},
      ),
    );

    final raw = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : response.data as Map<String, dynamic>;

    final elements = (raw['elements'] as List? ?? []);
    final places = <Place>[];
    final seenIds = <int>{...excludeIds};

    for (final el in elements) {
      final type = el['type'] as String?;
      if (type != 'node' && type != 'way') continue;

      final tags = ((el['tags'] as Map?) ?? {}).cast<String, dynamic>();
      final name = (tags['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;

      double? eLat, eLng;
      if (type == 'node') {
        eLat = (el['lat'] as num?)?.toDouble();
        eLng = (el['lon'] as num?)?.toDouble();
      } else {
        final center = el['center'] as Map?;
        eLat = (center?['lat'] as num?)?.toDouble();
        eLng = (center?['lon'] as num?)?.toDouble();
      }
      if (eLat == null || eLng == null) continue;

      final id = (el['id'] as num).toInt();
      if (seenIds.contains(id)) continue;
      seenIds.add(id);

      final street = tags['addr:street'] as String? ?? '';
      final houseNum = tags['addr:housenumber'] as String? ?? '';
      final suburb = tags['addr:suburb'] as String? ??
          tags['addr:district'] as String? ?? '';
      final addrParts =
          [street, houseNum, suburb].where((s) => s.isNotEmpty).join(' ').trim();
      final address = addrParts.isNotEmpty ? addrParts : 'Adres bilgisi yok';

      final amenity = tags['amenity'] as String? ?? '';
      final cuisine = tags['cuisine'] as String? ?? '';
      final typeList = [
        if (amenity.isNotEmpty) amenity,
        if (cuisine.isNotEmpty) cuisine,
      ];

      places.add(Place(
        id: id,
        name: name,
        address: address,
        lat: eLat,
        lng: eLng,
        types: typeList.isNotEmpty ? typeList : ['restaurant'],
      ));
    }

    // ignore: avoid_print
    print('[OVERPASS] ${places.length} mekan (${elements.length} element)');
    return places;
  }

  Future<Map<String, dynamic>> getRoom(String code) async {
    final cached = _roomCache[code];
    if (cached != null && DateTime.now().difference(cached.$1).inMilliseconds < 1500) {
      return cached.$2;
    }
    final response = await _dio.get('/api/rooms/$code');
    final data = Map<String, dynamic>.from(response.data);
    _roomCache[code] = (DateTime.now(), data);
    return data;
  }

  void invalidateRoomCache(String code) => _roomCache.remove(code);

  Future<Map<String, dynamic>> rejoinRoom({
    required String code,
    required String token,
  }) async {
    final deviceId = await DeviceService.getDeviceId();
    final response = await _dio.post(
      '/api/rooms/$code/rejoin',
      data: jsonEncode({'token': token, 'device_id': deviceId}),
      options: _plainOpts,
    );
    final data = Map<String, dynamic>.from(response.data);
    if (data['token'] != null) _setToken(data['token']);
    return data;
  }

  Future<Map<String, dynamic>> castVote({
    required String code,
    required int placeId,
    required int value,
  }) async {
    final response = await _dio.post(
      '/api/flutter/room/$code/vote',
      data: _body({'place_id': placeId, 'value': value}),
      options: _plainOpts,
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> finishVoting(String code) async {
    final response = await _dio.post(
      '/api/flutter/room/$code/finish',
      data: _body({}),
      options: _plainOpts,
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> getRoomResults(String code) async {
    final response = await _dio.get('/api/room/$code/results');
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> updateFcmToken(String code, String fcmToken) async {
    try {
      await _dio.post(
        '/api/rooms/$code/fcm-token',
        data: _body({'fcm_token': fcmToken}),
        options: _plainOpts,
      );
    } catch (e) {
      debugPrint('[FCM] Token gönderilemedi: $e');
    }
  }

  // ── Socket.IO ───────────────────────────────────────────────────────────────

  void initSocket({
    required String roomCode,
    required String nickname,
    void Function(List<Map<String, dynamic>>)? onParticipantsUpdate,
    void Function(List<Place>)? onPlacesLoaded,
    void Function(List<Map<String, dynamic>>)? onVoteUpdate,
    void Function(Map<String, dynamic>)? onShowResults,
    void Function(String)? onError,
  }) {
    socket = io.io(baseUrl, {
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
    });

    socket!.onConnect((_) {
      debugPrint('[SOCKET] Connected, joining $roomCode');
      socket!.emit('join_room_ws', {'code': roomCode, 'nickname': nickname});
    });

    socket!.on('participants_update', (data) {
      if (onParticipantsUpdate == null) return;
      final p = (data?['participants'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      onParticipantsUpdate(p);
    });

    socket!.on('places_loaded', (data) {
      debugPrint('[SOCKET] places_loaded: ${(data?["places"] as List?)?.length}');
      if (onPlacesLoaded == null) return;
      final places = (data?['places'] as List? ?? [])
          .map((p) => Place.fromJson(Map<String, dynamic>.from(p)))
          .toList();
      onPlacesLoaded(places);
    });

    socket!.on('vote_update', (data) {
      if (onVoteUpdate == null) return;
      final s = (data?['summary'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      onVoteUpdate(s);
    });

    socket!.on('show_results', (data) {
      debugPrint('[SOCKET] show_results');
      if (onShowResults != null && data is Map) {
        onShowResults(Map<String, dynamic>.from(data));
      }
    });

    socket!.onError((d) {
      debugPrint('[SOCKET] Error: $d');
      onError?.call(d.toString());
    });
    socket!.onConnectError((d) {
      debugPrint('[SOCKET] ConnectError: $d');
      onError?.call('Bağlantı hatası: $d');
    });
    socket!.onDisconnect((_) => debugPrint('[SOCKET] Disconnected'));

    socket!.connect();
  }

  void disposeSocket() {
    socket?.disconnect();
    socket?.dispose();
    socket = null;
  }
}

final apiService = ApiService();
