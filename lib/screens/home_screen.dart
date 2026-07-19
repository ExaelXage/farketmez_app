import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../services/session_service.dart';
import '../theme.dart';
import '../utils/error_utils.dart';
import 'profile_screen.dart';
import 'room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _nicknameController = TextEditingController();
  final _roomCodeController = TextEditingController();
  String _selectedCategory = 'food';
  int _selectedVoteCount = 3;
  bool _isLoading = false;
  bool _isOffline = false;
  Position? _position;

  late final AnimationController _logoEntryCtrl;
  late final AnimationController _logoPulseCtrl;
  late final AnimationController _orbCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoPulse;

  @override
  void initState() {
    super.initState();

    _logoEntryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));
    _logoScale = CurvedAnimation(parent: _logoEntryCtrl, curve: Curves.elasticOut);
    _logoEntryCtrl.forward();

    _logoPulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _logoPulse = Tween<double>(begin: 0.97, end: 1.04)
        .animate(CurvedAnimation(parent: _logoPulseCtrl, curve: Curves.easeInOut));

    _orbCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))
      ..repeat(reverse: true);

    _requestLocation();
    NotificationService.init();
    _loadSavedNickname();
  }

  Future<void> _loadSavedNickname() async {
    final nick = await ProfileService.getNickname();
    if (nick != null && nick.isNotEmpty && mounted) {
      _nicknameController.text = nick;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _roomCodeController.dispose();
    _logoEntryCtrl.dispose();
    _logoPulseCtrl.dispose();
    _orbCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      setState(() => _position = pos);
    } catch (_) {}
  }

  String get _nickname => _nicknameController.text.trim();

  Future<void> _createRoom() async {
    if (_nickname.isEmpty) { _showError('Lütfen bir takma ad girin'); return; }
    setState(() => _isLoading = true);
    try {
      final data = await apiService.createRoom(
        nickname: _nickname,
        category: _selectedCategory,
        lat: _position?.latitude,
        lng: _position?.longitude,
      );
      if (!mounted) return;
      setState(() => _isOffline = false);
      final code = data['code'] ?? '';
      ProfileService.saveNickname(_nickname);
      await SessionService.save(
        roomCode: code,
        token: data['token'] ?? '',
        nickname: _nickname,
        isHost: true,
        category: data['category'] ?? _selectedCategory,
      );
      // Register FCM token with backend in background
      NotificationService.getToken().then((fcmToken) {
        if (fcmToken != null) apiService.updateFcmToken(code, fcmToken);
      });
      Navigator.push(context, _FadeSlideRoute(child: RoomScreen(
        roomCode: code,
        nickname: _nickname,
        isHost: true,
        category: data['category'] ?? _selectedCategory,
        initialParticipants: List<Map<String, dynamic>>.from(data['participants'] ?? []),
        maxVotes: _selectedVoteCount,
      )));
    } catch (e) {
      if (isConnectionError(e)) setState(() => _isOffline = true);
      _showError(toTurkishError(e));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _joinRoom() async {
    final code = _roomCodeController.text.trim().toUpperCase();
    if (_nickname.isEmpty) { _showError('Lütfen bir takma ad girin'); return; }
    if (code.isEmpty) { _showError('Lütfen oda kodunu girin'); return; }
    setState(() => _isLoading = true);
    try {
      // Önce kaydedilmiş session varsa rejoin dene
      final saved = await SessionService.load(code);
      if (saved != null && saved['token'] != null) {
        try {
          final data = await apiService.rejoinRoom(code: code, token: saved['token']);
          if (!mounted) return;
          _navigateToRoom(
            code: code,
            nickname: saved['nickname'] ?? _nickname,
            isHost: saved['isHost'] == true,
            category: data['category'] ?? saved['category'] ?? 'food',
            participants: List<Map<String, dynamic>>.from(data['participants'] ?? []),
          );
          return;
        } on DioException catch (e) {
          if (e.response?.statusCode == 403 || e.response?.statusCode == 404) {
            await SessionService.clear(code);
          } else {
            rethrow;
          }
        }
      }

      // Normal katılım
      final data = await apiService.joinRoom(code: code, nickname: _nickname);
      if (!mounted) return;
      setState(() => _isOffline = false);
      ProfileService.saveNickname(_nickname);
      await SessionService.save(
        roomCode: code,
        token: data['token'] ?? '',
        nickname: _nickname,
        isHost: false,
        category: data['category'] ?? 'food',
      );
      // Register FCM token with backend in background
      NotificationService.getToken().then((fcmToken) {
        if (fcmToken != null) apiService.updateFcmToken(code, fcmToken);
      });
      _navigateToRoom(
        code: code,
        nickname: _nickname,
        isHost: false,
        category: data['category'] ?? 'food',
        participants: List<Map<String, dynamic>>.from(data['participants'] ?? []),
      );
    } catch (e) {
      if (isConnectionError(e)) setState(() => _isOffline = true);
      _showError(toTurkishError(e));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToRoom({
    required String code,
    required String nickname,
    required bool isHost,
    required String category,
    required List<Map<String, dynamic>> participants,
  }) {
    Navigator.push(context, _FadeSlideRoute(child: RoomScreen(
      roomCode: code,
      nickname: nickname,
      isHost: isHost,
      category: category,
      initialParticipants: participants,
      maxVotes: 3,
    )));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error, behavior: SnackBarBehavior.floating),
    );
  }

  void _showJoinDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            const Text('Odaya Katıl', style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _buildTextField(controller: _roomCodeController, hint: 'Oda Kodu (örn: ABC123)', icon: Icons.meeting_room_outlined, textCapitalization: TextCapitalization.characters),
            const SizedBox(height: 20),
            _GradientButton(label: 'Katıl', icon: Icons.login, onPressed: () { Navigator.pop(ctx); _joinRoom(); }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient)),
          // Offline banner
          if (_isOffline)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: const Color(0xFFB91C1C).withValues(alpha: 0.92),
                    child: Row(children: [
                      const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'İnternet bağlantısı yok — bağlantınızı kontrol edin',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _isOffline = false),
                        child: const Icon(Icons.close, color: Colors.white70, size: 18),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          AnimatedBuilder(
            animation: _orbCtrl,
            builder: (_, __) {
              final t = _orbCtrl.value;
              return Stack(children: [
                Positioned(top: -100 + t * 45, left: -80 + t * 30,
                  child: _GlowOrb(size: 320, color: AppTheme.primary.withValues(alpha: 0.12))),
                Positioned(bottom: 60 - t * 50, right: -80 + t * 30,
                  child: _GlowOrb(size: 280, color: AppTheme.secondary.withValues(alpha: 0.09))),
                Positioned(top: 360 + t * 30, left: 10 - t * 20,
                  child: _GlowOrb(size: 180, color: AppTheme.primary.withValues(alpha: 0.06))),
              ]);
            },
          ),
          // Profile button top-right
          Positioned(
            top: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 12),
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ).then((_) => _loadSavedNickname()),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      color: AppTheme.textSecondary,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  _buildLogo(),
                  const SizedBox(height: 44),
                  _buildTextField(controller: _nicknameController, hint: 'Takma Adın', icon: Icons.person_outline),
                  const SizedBox(height: 20),
                  _buildCategorySelector(),
                  const SizedBox(height: 20),
                  _buildVoteSelector(),
                  const SizedBox(height: 32),
                  _GradientButton(label: 'Oda Oluştur', icon: Icons.add_circle_outline, isLoading: _isLoading, onPressed: _isLoading ? null : _createRoom),
                  const SizedBox(height: 14),
                  _buildJoinButton(),
                  const SizedBox(height: 28),
                  if (_position != null)
                    Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.location_on, size: 13, color: AppTheme.success.withValues(alpha: 0.8)),
                      const SizedBox(width: 4),
                      Text('Konum alındı', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        ScaleTransition(
          scale: _logoScale,
          child: AnimatedBuilder(
            animation: _logoPulse,
            builder: (_, child) => Transform.scale(scale: _logoPulse.value, child: child),
            child: SizedBox(
              width: 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(color: AppTheme.primary.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 14)),
                    BoxShadow(color: AppTheme.secondary.withValues(alpha: 0.28), blurRadius: 70, offset: const Offset(0, 24)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 720 / 260,
                    child: SvgPicture.asset('assets/logo.svg', fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Nereye gidilir karar verelim',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary, letterSpacing: 0.2)),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textSecondary),
        prefixIcon: Icon(icon, color: AppTheme.primary),
        filled: true,
        fillColor: AppTheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
    );
  }

  Widget _buildCategorySelector() {
    const cats = [
      ('food',     'Yemek',   '🍽️'),
      ('activity', 'Etkinlik', '🎯'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ne arıyorsunuz?', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Row(
          children: cats.asMap().entries.map((e) {
            final idx = e.key; final c = e.value;
            final sel = _selectedCategory == c.$1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: idx == 0 ? 8 : 0),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedCategory = c.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    decoration: BoxDecoration(
                      gradient: sel ? AppTheme.primaryGradient : null,
                      color: sel ? null : AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: sel ? Colors.transparent : AppTheme.border, width: 1.5),
                      boxShadow: sel ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))] : null,
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(c.$3, style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Text(c.$2, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: sel ? Colors.white : AppTheme.textSecondary)),
                    ]),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildVoteSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Oy hakkı sayısı', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Row(
          children: [3, 5, 7].asMap().entries.map((e) {
            final count = e.value;
            final sel = _selectedVoteCount == count;
            final last = count == 7;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: last ? 0 : 10),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedVoteCount = count),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: sel ? AppTheme.primaryGradient : null,
                      color: sel ? null : AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sel ? Colors.transparent : AppTheme.border, width: 1.5),
                      boxShadow: sel ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] : null,
                    ),
                    child: Column(children: [
                      Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: sel ? Colors.white : AppTheme.textPrimary)),
                      Text('oy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: sel ? Colors.white.withValues(alpha: 0.8) : AppTheme.textSecondary)),
                    ]),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildJoinButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _showJoinDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.5), width: 1.5),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.group_add_outlined, color: AppTheme.secondary, size: 22),
          SizedBox(width: 10),
          Text('Mevcut Odaya Katıl', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.secondary)),
        ]),
      ),
    );
  }
}

// ── Shared utilities ─────────────────────────────────────────────────────────

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _FadeSlideRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  _FadeSlideRoute({required this.child})
      : super(
          pageBuilder: (_, __, ___) => child,
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
                  .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
              child: child,
            ),
          ),
        );
}

class _GradientButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _GradientButton({required this.label, this.icon, this.isLoading = false, this.onPressed});

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) { setState(() => _pressed = false); widget.onPressed?.call(); } : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: enabled ? AppTheme.primaryGradient : null,
            color: enabled ? null : AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: enabled && !_pressed
                ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 10))]
                : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (widget.isLoading)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            else ...[
              if (widget.icon != null) ...[Icon(widget.icon, color: Colors.white, size: 22), const SizedBox(width: 10)],
              Text(widget.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3)),
            ],
          ]),
        ),
      ),
    );
  }
}
