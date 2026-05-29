import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/place.dart';
import '../theme.dart';

// ── Win reason ────────────────────────────────────────────────────────────────

enum _WinReason { topVotes, tieBreaker, leastNegative, fatePick }

extension on _WinReason {
  String get label => switch (this) {
        _WinReason.topVotes      => 'En çok oy alan',
        _WinReason.tieBreaker    => 'Eşitlik — Kader seçti',
        _WinReason.leastNegative => 'En az olumsuz oy alan',
        _WinReason.fatePick      => 'Kader seçiyor... 🎲',
      };
  IconData get icon => switch (this) {
        _WinReason.topVotes      => Icons.emoji_events,
        _WinReason.tieBreaker    => Icons.casino,
        _WinReason.leastNegative => Icons.military_tech,
        _WinReason.fatePick      => Icons.shuffle,
      };
  bool get isFate => this == _WinReason.tieBreaker || this == _WinReason.fatePick;
}

// ── Confetti particle ─────────────────────────────────────────────────────────

class _Particle {
  final double startX;
  final double startY;
  final double vx;
  final double vy;
  final double size;
  final Color color;
  final double rotation;
  final double rotSpeed;
  final bool isSquare;

  const _Particle({
    required this.startX, required this.startY,
    required this.vx, required this.vy,
    required this.size, required this.color,
    required this.rotation, required this.rotSpeed,
    required this.isSquare,
  });

  static _Particle random(math.Random rng) {
    const colors = [
      Color(0xFF7C3AED), Color(0xFF06B6D4), Color(0xFFEC4899),
      Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFFF97316),
    ];
    return _Particle(
      startX: rng.nextDouble(),
      startY: -0.05 - rng.nextDouble() * 0.3,
      vx: (rng.nextDouble() - 0.5) * 0.8,
      vy: 0.6 + rng.nextDouble() * 1.0,
      size: 5 + rng.nextDouble() * 8,
      color: colors[rng.nextInt(colors.length)],
      rotation: rng.nextDouble() * math.pi * 2,
      rotSpeed: (rng.nextDouble() - 0.5) * 6,
      isSquare: rng.nextBool(),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;

  const _ConfettiPainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final px = (p.startX + p.vx * t) * size.width;
      final py = (p.startY + p.vy * t) * size.height;
      if (py > size.height + 20) continue;

      final fade = (1.0 - (t - 0.6).clamp(0.0, 1.0) / 0.4).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withValues(alpha: 0.85 * fade);

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(p.rotation + p.rotSpeed * t);

      if (p.isSquare) {
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6), paint);
      } else {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

class _ConfettiOverlay extends StatefulWidget {
  const _ConfettiOverlay();

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _particles = List.generate(70, (_) => _Particle.random(rng));
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3500))
      ..forward();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(painter: _ConfettiPainter(_particles, _ctrl.value)),
      ),
    );
  }
}

// ── Result Screen ─────────────────────────────────────────────────────────────

class ResultScreen extends StatefulWidget {
  final List<Place> winners;
  final List<Place> allPlaces;

  const ResultScreen({super.key, required this.winners, required this.allPlaces});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with TickerProviderStateMixin {
  late final Place _winner;
  late final _WinReason _reason;
  late final AnimationController _fadeCtrl;
  late final AnimationController _glowCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.82, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.elasticOut));

    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    if (widget.allPlaces.isEmpty) {
      _winner = Place(id: 0, name: '—', address: '', lat: 0, lng: 0, types: []);
      _reason = _WinReason.fatePick;
    } else {
      final result = _pick(widget.allPlaces);
      _winner = result.$1;
      _reason = result.$2;
    }

    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  /// Kazanan seçim algoritması:
  /// 1. En yüksek net skor (olumlu - olumsuz) → winner
  /// 2. Net skor eşitliğinde → en yüksek olumlu oy sayısı → winner
  /// 3. Hâlâ eşit → rastgele
  /// 4. Hiç olumlu oy yoksa → en az olumsuz (en yüksek net, negatif) → winner
  /// 5. Tamamen eşit → rastgele (kader)
  static (Place, _WinReason) _pick(List<Place> places) {
    final rng = math.Random();
    final sorted = [...places]..sort((a, b) => b.votes.compareTo(a.votes));
    final maxNet = sorted.first.votes;

    // Grup: en yüksek net skora sahip mekanlar
    final topNet = sorted.where((p) => p.votes == maxNet).toList();

    if (maxNet > 0) {
      // Olumlu net skor var — olumlu oy sayısıyla eşitliği boz
      final winner = _breakTie(topNet, rng);
      final reason = winner.$2 == _WinReason.tieBreaker
          ? _WinReason.tieBreaker
          : _WinReason.topVotes;
      return (winner.$1, reason);
    }

    // Net skor 0 veya negatif
    final minNet = sorted.last.votes;
    if (maxNet == minNet) {
      // Herkes eşit — kader seçiyor
      return (sorted[rng.nextInt(sorted.length)], _WinReason.fatePick);
    }

    // En az olumsuz grup (maxNet en yüksek negatif veya 0) — olumlu oyla eşitliği boz
    final winner = _breakTie(topNet, rng);
    final reason = winner.$2 == _WinReason.tieBreaker
        ? _WinReason.tieBreaker
        : _WinReason.leastNegative;
    return (winner.$1, reason);
  }

  /// topNet içinden olumlu oy sayısına göre kazananı seç; hâlâ eşitse rastgele.
  static (Place, _WinReason) _breakTie(List<Place> group, math.Random rng) {
    if (group.length == 1) return (group.first, _WinReason.topVotes);
    final maxPos = group.map((p) => p.positiveVotes).reduce((a, b) => a > b ? a : b);
    final topPos = group.where((p) => p.positiveVotes == maxPos).toList();
    if (topPos.length == 1) return (topPos.first, _WinReason.topVotes);
    return (topPos[rng.nextInt(topPos.length)], _WinReason.tieBreaker);
  }

  List<Place> get _sortedAll => [...widget.allPlaces]..sort((a, b) => b.votes.compareTo(a.votes));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient)),
          SafeArea(
            child: Column(children: [
              _buildAppBar(context),
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      ScaleTransition(scale: _scaleAnim, child: _buildWinnerSection()),
                      const SizedBox(height: 24),
                      if (_winner.lat != 0 && _winner.lng != 0) ...[
                        _buildMap(),
                        const SizedBox(height: 24),
                      ],
                      _buildScoreboard(),
                      const SizedBox(height: 20),
                      _buildHomeButton(context),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
          const _ConfettiOverlay(),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          icon: const Icon(Icons.home_outlined, color: AppTheme.textPrimary),
        ),
        const Spacer(),
        ShaderMask(
          shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
          child: const Text('Karar Verildi!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const Spacer(),
        const SizedBox(width: 48),
      ]),
    );
  }

  Widget _buildWinnerSection() {
    final isFate = _reason.isFate;
    final badgeGradient = isFate
        ? const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF7C3AED)], begin: Alignment.topLeft, end: Alignment.bottomRight)
        : AppTheme.primaryGradient;
    final badgeColor = isFate ? AppTheme.secondary : AppTheme.primary;

    return Column(children: [
      // Reason badge
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          decoration: BoxDecoration(
            gradient: badgeGradient,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: badgeColor.withValues(alpha: 0.5), blurRadius: 22, offset: const Offset(0, 6))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_reason.icon, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(_reason.label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      const SizedBox(height: 18),

      // Winner card with animated glow
      AnimatedBuilder(
        animation: _glowAnim,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: badgeColor.withValues(alpha: 0.55 + _glowAnim.value * 0.2), width: 2),
            boxShadow: [
              BoxShadow(color: badgeColor.withValues(alpha: 0.15 + _glowAnim.value * 0.15), blurRadius: 28 + _glowAnim.value * 16, offset: const Offset(0, 10)),
              BoxShadow(color: AppTheme.secondary.withValues(alpha: 0.07 + _glowAnim.value * 0.06), blurRadius: 60, offset: const Offset(0, 20)),
            ],
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(gradient: badgeGradient, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: badgeColor.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))]),
                child: Center(
                  child: isFate
                      ? const Text('🎲', style: TextStyle(fontSize: 30))
                      : const Icon(Icons.restaurant, color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_winner.name,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                  if (_winner.types.isNotEmpty)
                    Text(_winner.types.first, style: TextStyle(color: badgeColor, fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.location_on, color: AppTheme.secondary, size: 16),
              const SizedBox(width: 6),
              Expanded(child: Text(_winner.address, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
            ]),
            const SizedBox(height: 16),
            _buildVoteBadge(),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildVoteBadge() {
    if (_winner.votes > 0) {
      return _StatBadge(icon: Icons.thumb_up, label: '${_winner.votes} beğeni', color: AppTheme.success);
    }
    if (_winner.votes == 0) {
      return _StatBadge(icon: Icons.remove_circle_outline, label: 'Oy kullanılmadı', color: AppTheme.textSecondary);
    }
    return _StatBadge(icon: Icons.shield_outlined, label: 'En az olumsuz (${_winner.votes.abs()} olumsuz)', color: AppTheme.secondary);
  }

  Widget _buildMap() {
    final center = LatLng(_winner.lat, _winner.lng);
    return Container(
      height: 200,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
      clipBehavior: Clip.hardEdge,
      child: FlutterMap(
        options: MapOptions(initialCenter: center, initialZoom: 15),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.farketmez_app'),
          MarkerLayer(markers: [
            Marker(
              point: center,
              child: ShaderMask(
                shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
                child: const Icon(Icons.location_pin, color: Colors.white, size: 48),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildScoreboard() {
    final sorted = _sortedAll;
    if (sorted.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ShaderMask(
            shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
            child: const Icon(Icons.leaderboard, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 8),
          const Text('Puan Tablosu',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        ...sorted.asMap().entries.map((e) => _ScoreRow(
              rank: e.key + 1,
              place: e.value,
              isWinner: e.value.id == _winner.id,
            )),
      ]),
    );
  }

  Widget _buildHomeButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.home_outlined, color: AppTheme.textPrimary),
          SizedBox(width: 8),
          Text('Ana Sayfaya Dön', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatBadge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final int rank;
  final Place place;
  final bool isWinner;

  const _ScoreRow({required this.rank, required this.place, required this.isWinner});

  @override
  Widget build(BuildContext context) {
    const medals = {1: '🥇', 2: '🥈', 3: '🥉'};
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isWinner
            ? AppTheme.primary.withValues(alpha: 0.08)
            : AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWinner ? AppTheme.primary.withValues(alpha: 0.4) : AppTheme.border.withValues(alpha: 0.4),
        ),
      ),
      child: Row(children: [
        SizedBox(
          width: 32,
          child: Text(
            medals[rank] ?? '$rank.',
            style: TextStyle(fontSize: rank <= 3 ? 20 : 14, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(place.name,
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: isWinner ? FontWeight.w700 : FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(place.address,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        _VoteChip(votes: place.votes),
      ]),
    );
  }
}

class _VoteChip extends StatelessWidget {
  final int votes;
  const _VoteChip({required this.votes});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String text;
    if (votes > 0) {
      color = AppTheme.success; icon = Icons.thumb_up; text = '+$votes';
    } else if (votes < 0) {
      color = AppTheme.error.withValues(alpha: 0.7); icon = Icons.thumb_down; text = '$votes';
    } else {
      color = AppTheme.textSecondary; icon = Icons.remove; text = '0';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
