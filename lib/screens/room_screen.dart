import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/place.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'result_screen.dart';

class RoomScreen extends StatefulWidget {
  final String roomCode;
  final String nickname;
  final bool isHost;
  final String category;
  final List<Map<String, dynamic>> initialParticipants;
  final int maxVotes;

  const RoomScreen({
    super.key,
    required this.roomCode,
    required this.nickname,
    required this.isHost,
    required this.category,
    required this.initialParticipants,
    this.maxVotes = 3,
  });

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen>
    with SingleTickerProviderStateMixin {
  // ── State ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _participants = [];
  List<Place> _places = [];
  Map<int, int> _myVotes = {}; // placeId → +1 / -1
  String? _activeFilter; // null = tümü
  String? _activeFoodFilter; // null = tüm yemek alt kategorileri
  bool _isVoting = false;
  bool _isStarting = false;
  String _startingMessage = 'Mekanlar aranıyor...';
  bool _isFinishing = false;
  bool _isAddingCategory = false;
  final Set<String> _selectedWaitingCategories = {};
  double? _searchLat;
  double? _searchLng;
  Timer? _pollTimer;
  String _lastKnownStatus = 'waiting';
  bool _navigatedToResults = false;
  final MapController _mapController = MapController();
  late TabController _tabController;

  late final int _maxVotes;

  int get _votesUsed => _myVotes.length; // olumlu + olumsuz toplam

  // ── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _participants = widget.initialParticipants;
    _maxVotes = widget.maxVotes;
    _tabController = TabController(length: 2, vsync: this);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ── Polling ──────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollRoom());
  }

  Future<void> _pollRoom() async {
    if (_navigatedToResults) return;
    try {
      final data = await apiService.getRoom(widget.roomCode);
      if (!mounted || _navigatedToResults) return;

      final newParticipants = List<Map<String, dynamic>>.from(data['participants'] ?? []);
      final newStatus       = (data['status'] as String?) ?? 'waiting';

      // Katılımcı listesi değiştiyse güncelle
      if (_participantsChanged(newParticipants)) {
        setState(() => _participants = newParticipants);
      }

      // Durum geçişlerini işle
      if (newStatus != _lastKnownStatus) {
        _lastKnownStatus = newStatus;

        if (newStatus == 'voting' && !_isVoting) {
          final rawPlaces = List<Map<String, dynamic>>.from(data['places'] ?? []);
          if (rawPlaces.isNotEmpty) {
            setState(() {
              _places         = rawPlaces.map((p) => Place.fromJson(p)).toList();
              _isVoting       = true;
              _isStarting     = false;
              _activeFilter   = null;
              _activeFoodFilter = null;
            });
          }
        } else if (newStatus == 'completed') {
          _goToResults(data);
        }
      }
    } catch (_) {
      // Polling hataları sessizce görmezden gel
    }
  }

  bool _participantsChanged(List<Map<String, dynamic>> newP) {
    if (newP.length != _participants.length) return true;
    final oldNames = _participants.map((p) => p['nickname']).toSet();
    final newNames = newP.map((p) => p['nickname']).toSet();
    return !oldNames.containsAll(newNames) || !newNames.containsAll(oldNames);
  }

  void _goToResults(Map<String, dynamic> data) {
    if (_navigatedToResults || !mounted) return;
    _navigatedToResults = true;
    _pollTimer?.cancel();
    final summary   = List<Map<String, dynamic>>.from(data['summary'] ?? []);
    final allPlaces = summary.map((p) => Place.fromJson(p)).toList();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          winners:   allPlaces.where((p) => p.votes > 0).toList(),
          allPlaces: allPlaces,
        ),
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  Future<void> _startVoting() async {
    setState(() {
      _isStarting = true;
      _startingMessage = 'Konum alınıyor...';
    });

    // ── 1. Konum al ──────────────────────────────────────────────────────────
    double lat;
    double lng;
    try {
      // İzin durumunu kontrol et; reddedilmişse hemen manuel girişe geç
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _startingMessage = 'Konum izni bekleniyor...');
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Konum izni reddedildi');
      }
      if (mounted) setState(() => _startingMessage = 'Konum alınıyor...');
      // Tarayıcı izin diyaloğuna cevap için 30 saniye — çok kısa timeout
      // kullanıcının diyaloğu kapatmadan önce zaman aşımına uğramasına neden olur.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 30));
      lat = pos.latitude;
      lng = pos.longitude;
      // ignore: avoid_print
      print('[FARKETMEZ] ✅ Konum alındı: $lat, $lng');
    } catch (e) {
      // ignore: avoid_print
      print('[FARKETMEZ] ❌ Konum alınamadı ($e) → Manuel giriş sunuluyor');
      if (!mounted) return;
      setState(() => _isStarting = false);
      final coords = await _showManualLocationSheet();
      if (!mounted) return;
      if (coords == null) return; // kullanıcı iptal etti
      lat = coords.$1;
      lng = coords.$2;
      setState(() {
        _isStarting = true;
        _startingMessage = 'Mekanlar aranıyor...';
      });
    }

    if (!mounted) return;
    _searchLat = lat;
    _searchLng = lng;

    // ── 2. Mekanları ara ────────────────────────────────────────────────────
    setState(() => _startingMessage = 'Mekanlar aranıyor...');
    try {
      final places = await apiService.searchPlaces(
        code: widget.roomCode,
        lat: lat,
        lng: lng,
        onRetry: (attempt) {
          if (mounted) {
            setState(() =>
                _startingMessage = 'Sunucu uyandırılıyor... ($attempt/3)');
          }
        },
      );

      debugPrint('[Room] ${places.length} mekan geldi');
      if (!mounted) return;

      if (places.isEmpty) {
        setState(() => _isStarting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yakında uygun mekan bulunamadı'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() {
        _places = places;
        _isVoting = true;
        _isStarting = false;
        _activeFilter = null;
        _activeFoodFilter = null;
      });
    } catch (e) {
      debugPrint('[Room] _startVoting error: $e');
      if (!mounted) return;
      setState(() => _isStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mekanlar yüklenemedi: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<(double, double)?> _showManualLocationSheet() {
    return showModalBottomSheet<(double, double)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _ManualLocationSheet(),
    );
  }

  Future<void> _vote(Place place, int value) async {
    if (_myVotes.containsKey(place.id)) {
      // Aynı oya tıklandıysa geri al (toggle) — backend'e -value gönder
      final prev = _myVotes[place.id]!;
      setState(() => _myVotes.remove(place.id));
      try {
        await apiService.castVote(
            code: widget.roomCode, placeId: place.id, value: -prev);
      } catch (_) {}
      return;
    }

    if (_votesUsed >= _maxVotes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_maxVotes oy hakkınızı kullandınız!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _myVotes[place.id] = value);
    try {
      await apiService.castVote(
          code: widget.roomCode, placeId: place.id, value: value);
    } catch (e) {
      setState(() => _myVotes.remove(place.id));
    }
  }

  Future<void> _finishVoting() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Oylamayı Bitir',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Oylama sona erdirilecek ve sonuçlar gösterilecek.',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bitir',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isFinishing = true);
    try {
      // ignore: avoid_print
      print('[FARKETMEZ] POST /api/room/${widget.roomCode}/finish');
      final data = await apiService.finishVoting(widget.roomCode)
          .timeout(const Duration(seconds: 30));
      // ignore: avoid_print
      print('[FARKETMEZ] finishVoting -> ok=${data["ok"]} summary_count=${(data["summary"] as List?)?.length}');

      if (!mounted) return;

      final summary = List<Map<String, dynamic>>.from(data['summary'] ?? []);

      final List<Place> allPlaces;
      if (widget.category == 'food' && _places.isNotEmpty) {
        // net skor haritası ve olumlu oy haritası
        final netMap = <int, int>{};
        final posMap = <int, int>{};

        for (final s in summary) {
          final id = (s['id'] as num?)?.toInt();
          if (id == null) continue;
          netMap[id] = ((s['total_score'] ?? s['votes'] ?? 0) as num).toInt();
          posMap[id] = ((s['positive_votes'] ?? s['likes'] ?? 0) as num).toInt();
        }

        // Backend Overpass ID'lerini tanımıyorsa yerel oylardan hesapla
        if (netMap.isEmpty) {
          for (final entry in _myVotes.entries) {
            // net skor: +1 veya -1 değerini doğrudan topla
            netMap[entry.key] = (netMap[entry.key] ?? 0) + entry.value;
            if (entry.value == 1) {
              posMap[entry.key] = (posMap[entry.key] ?? 0) + 1;
            }
          }
        }

        // Sadece en az bir oy almış mekanları dahil et
        final votedPlaces = _places.where((p) => netMap.containsKey(p.id)).toList();
        for (final p in votedPlaces) {
          p.votes = netMap[p.id]!;
          p.positiveVotes = posMap[p.id] ?? 0;
        }
        allPlaces = [...votedPlaces]..sort((a, b) => b.votes.compareTo(a.votes));
      } else {
        // Backend summary: sıfır oyu olan mekanları çıkar
        final all = summary.map((p) => Place.fromJson(p)).toList();
        final voted = all.where((p) => p.votes != 0 || p.positiveVotes > 0).toList();
        allPlaces = voted.isNotEmpty ? voted : all;
      }

      _navigatedToResults = true;
      _pollTimer?.cancel();
      final winners = allPlaces.where((p) => p.votes > 0).toList();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(winners: winners, allPlaces: allPlaces),
        ),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[FARKETMEZ] finishVoting HATA: $e');
      if (!mounted) return;
      setState(() => _isFinishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  List<String> get _categories {
    final cats = _places.map((p) => p.types.isNotEmpty ? p.types.first : '').where((c) => c.isNotEmpty).toSet().toList();
    cats.sort();
    return cats;
  }

  // key → (emoji, displayLabel, keywords)
  static final _foodCategoryList = <(String, String, String, List<String>)>[
    ('Pizza',    '🍕', 'Pizza',       ['pizza']),
    ('Burger',   '🍔', 'Burger',      ['burger', 'hamburger']),
    ('Kebap',    '🥙', 'Kebap',       ['kebap', 'kebab', 'döner', 'doner']),
    ('Kafe',     '☕', 'Kafe',        ['kafe', 'cafe', 'kahve', 'coffee']),
    ('Steak',    '🥩', 'Steak House', ['steak', 'steakhouse', 'et lokant']),
    ('Fastfood', '🍟', 'Fast Food',   ['fast food', 'fastfood', 'mcdonald', 'kfc', 'burger king', 'popeyes', 'subway']),
  ];

  static Map<String, List<String>> get _foodSubcategories => {
    for (final c in _foodCategoryList) c.$1: c.$4,
  };

  List<Place> get _filteredPlaces {
    var places = _activeFilter == null
        ? _places
        : _places
            .where((p) => p.types.isNotEmpty && p.types.first == _activeFilter)
            .toList();

    if (widget.category == 'food' && _activeFoodFilter != null) {
      final keywords = _foodSubcategories[_activeFoodFilter] ?? [];
      places = places.where((p) {
        final name = p.name.toLowerCase();
        return keywords.any((k) => name.contains(k));
      }).toList();
    }

    return places;
  }

  static Color _avatarColor(String name) {
    const colors = [
      Color(0xFF7C3AED), Color(0xFF06B6D4), Color(0xFF10B981),
      Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF6366F1),
    ];
    final idx = name.codeUnits.fold(0, (a, b) => a + b) % colors.length;
    return colors[idx];
  }

  String _categoryLabel(String raw) {
    const labels = {
      'restaurant': 'Restoran',
      'cafe': 'Kafe',
      'fast_food': 'Fast Food',
      'bakery': 'Pastane',
      'bar': 'Bar',
      'pub': 'Pub',
      'ice_cream': 'Dondurma',
      'cinema': 'Sinema',
      'theatre': 'Tiyatro',
      'park': 'Park',
    };
    return labels[raw] ?? raw;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration:
            const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: _isVoting ? _buildVotingView() : _buildWaitingView(),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // WAITING VIEW
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildWaitingView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildRoomCode(),
          if (widget.isHost && widget.category == 'food') ...[
            const SizedBox(height: 20),
            _buildWaitingCategoryPicker(),
          ],
          const SizedBox(height: 20),
          Expanded(child: _buildMembersList()),
          const SizedBox(height: 16),
          if (widget.isHost) _buildStartButton() else _buildWaitingForHost(),
        ],
      ),
    );
  }

  Widget _buildWaitingCategoryPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hangi kategorilerde arama yapılsın?',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _EmojiFilterChip(
                emoji: '🍽️',
                label: 'Tümü',
                isSelected: _selectedWaitingCategories.isEmpty,
                onTap: () =>
                    setState(() => _selectedWaitingCategories.clear()),
              ),
              ..._foodCategoryList.map((c) {
                final selected = _selectedWaitingCategories.contains(c.$1);
                return _EmojiFilterChip(
                  emoji: c.$2,
                  label: c.$3,
                  isSelected: selected,
                  onTap: () => setState(() {
                    if (selected) {
                      _selectedWaitingCategories.remove(c.$1);
                    } else {
                      _selectedWaitingCategories.add(c.$1);
                    }
                  }),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios,
              color: AppTheme.textPrimary),
        ),
        const Spacer(),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              Icon(
                widget.category == 'food'
                    ? Icons.restaurant
                    : Icons.local_activity,
                color: AppTheme.primary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                widget.category == 'food' ? 'Yemek' : 'Etkinlik',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoomCode() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Text('Oda Kodu',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          ShaderMask(
            shaderCallback: (b) =>
                AppTheme.primaryGradient.createShader(b),
            child: Text(
              widget.roomCode,
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 8,
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Clipboard.setData(
                  ClipboardData(text: widget.roomCode));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Kod kopyalandı!'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.copy, color: AppTheme.secondary, size: 16),
                SizedBox(width: 6),
                Text('Kopyala',
                    style: TextStyle(
                        color: AppTheme.secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.people_outline,
                color: AppTheme.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Katılımcılar (${_participants.length})',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _participants.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = _participants[i];
              final name = p['nickname'] ?? '?';
              final isOwner = p['is_owner'] == 1 || p['is_owner'] == true;
              final avatarColor = _avatarColor(name);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: isOwner
                      ? Border.all(color: AppTheme.primary.withValues(alpha: 0.35), width: 1.5)
                      : Border.all(color: AppTheme.border.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: avatarColor.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: avatarColor.withValues(alpha: 0.5), width: 2),
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(color: avatarColor, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
                    ),
                    if (isOwner)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.star, color: Colors.white, size: 11),
                          SizedBox(width: 3),
                          Text('Host', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    return GestureDetector(
      onTap: _isStarting ? null : _startVoting,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: _isStarting ? null : AppTheme.primaryGradient,
          color: _isStarting ? AppTheme.surface : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: _isStarting
              ? null
              : [
                  BoxShadow(
                    color:
                        AppTheme.primary.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ],
        ),
        child: Center(
          child: _isStarting
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text(_startingMessage,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15)),
                  ],
                )
              : const Text(
                  'Oylamayı Başlat',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
        ),
      ),
    );
  }

  Widget _buildWaitingForHost() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16)),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.secondary),
          ),
          SizedBox(width: 12),
          Text('Host oylamayı başlatmasını bekliyor...',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // VOTING VIEW
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildVotingView() {
    return Column(
      children: [
        _buildVotingHeader(),
        _buildVoteCounter(),
        _buildCategoryFilters(),
        TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Liste'),
            Tab(icon: Icon(Icons.map_outlined), text: 'Harita'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPlacesList(),
              _buildMap(),
            ],
          ),
        ),
        if (widget.isHost) _buildFinishButton(),
      ],
    );
  }

  Widget _buildVotingHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios,
                color: AppTheme.textPrimary, size: 18),
          ),
          ShaderMask(
            shaderCallback: (b) =>
                AppTheme.primaryGradient.createShader(b),
            child: const Text(
              'Oylama',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12)),
            child: Text(
              '${_places.length} mekan',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          if (widget.isHost && widget.category == 'food') ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isAddingCategory ? null : _showAddCategorySheet,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: _isAddingCategory ? null : AppTheme.primaryGradient,
                  color: _isAddingCategory ? AppTheme.surface : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isAddingCategory
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Kategori Ekle',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoteCounter() {
    final remaining = _maxVotes - _votesUsed;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: remaining > 0
                ? AppTheme.primary.withValues(alpha: 0.4)
                : AppTheme.error.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.how_to_vote_outlined,
              color:
                  remaining > 0 ? AppTheme.primary : AppTheme.error,
              size: 18,
            ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Text(
                remaining > 0 ? '$remaining oy hakkı kaldı' : 'Tüm oyları kullandınız',
                key: ValueKey(remaining),
                style: TextStyle(color: remaining > 0 ? AppTheme.textPrimary : AppTheme.error, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const Spacer(),
            Row(
              children: List.generate(
                _maxVotes,
                (i) => Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    i < _votesUsed
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: i < _votesUsed
                        ? AppTheme.success
                        : AppTheme.textSecondary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    final cats = _categories;

    return Column(
      children: [
        if (cats.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _FilterChip(
                  label: 'Tümü',
                  isSelected: _activeFilter == null,
                  onTap: () => setState(() => _activeFilter = null),
                ),
                ...cats.map((c) => _FilterChip(
                      label: _categoryLabel(c),
                      isSelected: _activeFilter == c,
                      onTap: () => setState(() => _activeFilter = c),
                    )),
              ],
            ),
          ),
        if (widget.category == 'food') ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _EmojiFilterChip(
                  emoji: '🍽️',
                  label: 'Hepsi',
                  isSelected: _activeFoodFilter == null,
                  onTap: () => setState(() => _activeFoodFilter = null),
                ),
                ..._foodCategoryList.map((c) => _EmojiFilterChip(
                      emoji: c.$2,
                      label: c.$3,
                      isSelected: _activeFoodFilter == c.$1,
                      onTap: () => setState(() => _activeFoodFilter = c.$1),
                    )),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildPlacesList() {
    final places = _filteredPlaces;
    if (places.isEmpty) {
      return Center(
        child: Text(
          'Bu kategoride mekan yok',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: places.length,
      itemBuilder: (_, i) => _PlaceListItem(
        place: places[i],
        myVote: _myVotes[places[i].id],
        votesUsed: _votesUsed,
        maxVotes: _maxVotes,
        onVote: (value) => _vote(places[i], value),
      ),
    );
  }

  Widget _buildMap() {
    final places = _filteredPlaces;
    final center = _searchLat != null
        ? LatLng(_searchLat!, _searchLng!)
        : places.isNotEmpty
            ? LatLng(places.first.lat, places.first.lng)
            : const LatLng(41.0082, 28.9784);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: center, initialZoom: 14),
      children: [
        TileLayer(
          urlTemplate:
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.farketmez_app',
        ),
        MarkerLayer(
          markers: places.map((place) {
            final voted = _myVotes.containsKey(place.id);
            final liked = _myVotes[place.id] == 1;
            return Marker(
              point: LatLng(place.lat, place.lng),
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => _showPlacePopup(place),
                child: Container(
                  decoration: BoxDecoration(
                    color: voted
                        ? (liked ? AppTheme.success : AppTheme.error)
                        : AppTheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                  child: Icon(
                    voted
                        ? (liked ? Icons.favorite : Icons.close)
                        : Icons.location_on,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showPlacePopup(Place place) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(place.name,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.location_on,
                  color: AppTheme.secondary, size: 16),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(place.address,
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13))),
            ]),
            if (place.types.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_categoryLabel(place.types.first),
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _VoteActionButton(
                    icon: Icons.close,
                    label: 'Beğenme',
                    color: AppTheme.error,
                    isActive: _myVotes[place.id] == -1,
                    onTap: () {
                      Navigator.pop(context);
                      _vote(place, -1);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _VoteActionButton(
                    icon: Icons.favorite,
                    label: 'Beğen',
                    color: AppTheme.success,
                    isActive: _myVotes[place.id] == 1,
                    onTap: () {
                      Navigator.pop(context);
                      _vote(place, 1);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCategorySheet() {
    final tempSelected = <String>{};
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Kategori Ekle',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Mevcut listeye yeni mekanlar eklenecek',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _foodCategoryList.map((c) {
                  final sel = tempSelected.contains(c.$1);
                  return GestureDetector(
                    onTap: () => setSheetState(() {
                      if (sel) {
                        tempSelected.remove(c.$1);
                      } else {
                        tempSelected.add(c.$1);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: sel ? AppTheme.primaryGradient : null,
                        color: sel ? null : const Color(0xFF1A1A35),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: sel
                              ? Colors.transparent
                              : AppTheme.border.withValues(alpha: 0.5),
                        ),
                        boxShadow: sel
                            ? [
                                BoxShadow(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(c.$2,
                              style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Text(
                            c.$3,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: sel
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: sel
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: tempSelected.isEmpty
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _addCategoryPlaces(tempSelected.toList());
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: tempSelected.isNotEmpty
                        ? AppTheme.primaryGradient
                        : null,
                    color: tempSelected.isEmpty ? AppTheme.surface : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      tempSelected.isEmpty
                          ? 'Kategori seçin'
                          : '${tempSelected.length} kategori ekle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addCategoryPlaces(List<String> categories) async {
    if (_searchLat == null || _searchLng == null) return;
    setState(() => _isAddingCategory = true);
    try {
      final existingIds = _places.map((p) => p.id).toSet();
      final allPlaces = await apiService.searchPlaces(
        code: widget.roomCode,
        lat: _searchLat!,
        lng: _searchLng!,
      );
      final newPlaces = allPlaces.where((p) => !existingIds.contains(p.id)).toList();
      if (!mounted) return;
      setState(() {
        _places = [..._places, ...newPlaces];
        _isAddingCategory = false;
      });
      if (newPlaces.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu kategorilerde yeni mekan bulunamadı'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${newPlaces.length} yeni mekan eklendi'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAddingCategory = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mekanlar yüklenemedi: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildFinishButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: GestureDetector(
        onTap: _isFinishing ? null : _finishVoting,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient:
                _isFinishing ? null : AppTheme.primaryGradient,
            color: _isFinishing ? AppTheme.surface : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _isFinishing
                ? null
                : [
                    BoxShadow(
                      color:
                          AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    )
                  ],
          ),
          child: Center(
            child: _isFinishing
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white)),
                      SizedBox(width: 10),
                      Text('Sonuçlar hesaplanıyor...',
                          style: TextStyle(
                              color: Colors.white, fontSize: 14)),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text('Oylamayı Bitir',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: isSelected ? AppTheme.primaryGradient : null,
          color: isSelected ? null : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _PlaceListItem extends StatelessWidget {
  final Place place;
  final int? myVote;
  final int votesUsed;
  final int maxVotes;
  final void Function(int value) onVote;

  const _PlaceListItem({
    required this.place,
    required this.myVote,
    required this.votesUsed,
    required this.maxVotes,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    final liked = myVote == 1;
    final disliked = myVote == -1;
    final hasSlot = votesUsed < maxVotes;
    final canLike = liked || hasSlot;
    final canDislike = disliked || hasSlot;
    final accentColor = liked ? AppTheme.success : disliked ? AppTheme.error : AppTheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: liked
              ? AppTheme.success.withValues(alpha: 0.55)
              : disliked
                  ? AppTheme.error.withValues(alpha: 0.4)
                  : AppTheme.border,
          width: liked || disliked ? 1.5 : 1,
        ),
        boxShadow: liked || disliked
            ? [BoxShadow(color: accentColor.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Colored accent bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 5,
                color: accentColor.withValues(alpha: liked || disliked ? 0.85 : 0.25),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      // Icon box
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          liked ? Icons.favorite : disliked ? Icons.close : Icons.restaurant,
                          color: accentColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Name & address
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              place.name,
                              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(children: [
                              Icon(Icons.location_on, size: 12, color: AppTheme.textSecondary),
                              const SizedBox(width: 3),
                              Expanded(child: Text(place.address,
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                  maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ]),
                            if (place.types.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(place.types.first,
                                    style: const TextStyle(color: AppTheme.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Vote buttons
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _SmallVoteButton(
                          icon: Icons.favorite_rounded,
                          color: AppTheme.success,
                          isActive: liked,
                          isDisabled: !canLike && !liked,
                          onTap: () => onVote(1),
                        ),
                        const SizedBox(height: 8),
                        _SmallVoteButton(
                          icon: Icons.close_rounded,
                          color: AppTheme.error,
                          isActive: disliked,
                          isDisabled: !canDislike,
                          onTap: () => onVote(-1),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallVoteButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isActive;
  final bool isDisabled;
  final VoidCallback onTap;

  const _SmallVoteButton({
    required this.icon,
    required this.color,
    required this.isActive,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isDisabled ? AppTheme.textSecondary : color;
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.2) : color.withValues(alpha: 0.06),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive ? color : effectiveColor.withValues(alpha: 0.35),
            width: isActive ? 2 : 1.5,
          ),
          boxShadow: isActive ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Icon(icon, color: isActive ? color : effectiveColor, size: 18),
      ),
    );
  }
}

class _VoteActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  const _VoteActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.2)
              : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isActive ? color : color.withValues(alpha: 0.3),
              width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _EmojiFilterChip extends StatelessWidget {
  final String emoji;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _EmojiFilterChip({
    required this.emoji,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: isSelected ? AppTheme.primaryGradient : null,
          color: isSelected ? null : const Color(0xFF1A1A35),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : AppTheme.border.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Manuel konum girişi ───────────────────────────────────────────────────────

class _ManualLocationSheet extends StatefulWidget {
  const _ManualLocationSheet();

  @override
  State<_ManualLocationSheet> createState() => _ManualLocationSheetState();
}

class _ManualLocationSheetState extends State<_ManualLocationSheet> {
  final _ctrl = TextEditingController();
  bool _searching = false;
  String? _error;
  String? _foundName;
  (double, double)? _coords;

  static const _quickCities = [
    ('İstanbul',   41.0082, 28.9784),
    ('Ankara',     39.9334, 32.8597),
    ('İzmir',      38.4192, 27.1287),
    ('Bursa',      40.1885, 29.0610),
    ('Antalya',    36.8969, 30.7133),
    ('Adana',      37.0000, 35.3213),
    ('Konya',      37.8667, 32.4833),
    ('Gaziantep',  37.0662, 37.3833),
    ('Mersin',     36.8000, 34.6333),
    ('Kocaeli',    40.7654, 29.9408),
    ('Diyarbakır', 37.9144, 40.2306),
    ('Hatay',      36.4018, 36.3498),
    ('Manisa',     38.6191, 27.4289),
    ('Balıkesir',  39.6484, 27.8826),
    ('Kayseri',    38.7312, 35.4787),
    ('Samsun',     41.2867, 36.3300),
    ('Trabzon',    41.0015, 39.7178),
    ('Eskişehir',  39.7767, 30.5206),
    ('Şanlıurfa',  37.1591, 38.7969),
    ('Malatya',    38.3552, 38.3095),
  ];

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _coords = null;
    });
    try {
      final dio = Dio();
      final resp = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': q,
          'format': 'json',
          'limit': '1',
          'accept-language': 'tr',
        },
        options: Options(headers: {'Accept': 'application/json'}),
      ).timeout(const Duration(seconds: 10));

      final list = resp.data as List?;
      if (list == null || list.isEmpty) {
        setState(() {
          _error = '"$q" bulunamadı';
          _searching = false;
        });
        return;
      }
      final first = list.first as Map;
      final lat = double.parse(first['lat'].toString());
      final lng = double.parse(first['lon'].toString());
      final name = (first['display_name'] as String? ?? q)
          .split(',')
          .first
          .trim();
      setState(() {
        _coords = (lat, lng);
        _foundName = name;
        _searching = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Arama başarısız: $e';
        _searching = false;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Başlık
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_off,
                    color: AppTheme.error, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Konum Alınamadı',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text('Şehir veya ilçe seçerek devam edin',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Arama alanı
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 15),
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Şehir veya ilçe adı...',
                    hintStyle:
                        const TextStyle(color: AppTheme.textSecondary),
                    filled: true,
                    fillColor: const Color(0xFF1A1A35),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                    errorText: _error,
                    errorMaxLines: 2,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _searching ? null : _search,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: _searching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.search,
                            color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),

          // Bulunan sonuç
          if (_coords != null && _foundName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AppTheme.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _foundName!,
                      style: const TextStyle(
                          color: AppTheme.success,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          // Hızlı şehir seçimi
          Text(
            'Hızlı Seçim',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickCities.map((c) {
              final sel = _coords != null &&
                  (_coords!.$1 - c.$2).abs() < 0.1 &&
                  (_coords!.$2 - c.$3).abs() < 0.1;
              return GestureDetector(
                onTap: () => setState(() {
                  _coords = (c.$2, c.$3);
                  _foundName = c.$1;
                  _error = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: sel ? AppTheme.primaryGradient : null,
                    color: sel ? null : const Color(0xFF1A1A35),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel
                          ? Colors.transparent
                          : AppTheme.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    c.$1,
                    style: TextStyle(
                        color: sel
                            ? Colors.white
                            : AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 22),

          // Butonlar
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('İptal'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _coords == null
                      ? null
                      : () => Navigator.pop(context, _coords),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: _coords != null
                          ? AppTheme.primaryGradient
                          : null,
                      color:
                          _coords == null ? AppTheme.surface : null,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _coords != null
                          ? [
                              BoxShadow(
                                color: AppTheme.primary
                                    .withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        _coords != null
                            ? 'Bu Konumu Kullan'
                            : 'Konum seçin',
                        style: TextStyle(
                          color: _coords != null
                              ? Colors.white
                              : AppTheme.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

