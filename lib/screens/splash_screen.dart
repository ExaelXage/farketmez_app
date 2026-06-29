import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final Animation<double> _textFade;

  bool _showWarmup = false;
  bool _warmupDone = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _scale = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.55)),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.4, 0.9)),
    );

    _ctrl.forward();
    _startup();
  }

  Future<void> _startup() async {
    // Minimum 2 saniye splash göster; aynı anda backend'i uyandır
    Timer(const Duration(seconds: 2), () {
      if (mounted && !_warmupDone) setState(() => _showWarmup = true);
    });

    await Future.wait([
      _pingBackend(),
      Future<void>.delayed(const Duration(milliseconds: 2000)),
    ]);

    if (mounted) _goHome();
  }

  Future<void> _pingBackend() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ));
      await dio.get('${ApiService.baseUrl}/api/health');
    } catch (_) {}
    _warmupDone = true;
    if (mounted) setState(() => _showWarmup = false);
  }

  Future<void> _goHome() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') ?? false;
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            done ? const HomeScreen() : const OnboardingScreen(),
        transitionDuration: const Duration(milliseconds: 450),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Glow halo
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              AppTheme.primary.withValues(alpha: 0.25),
                              AppTheme.secondary.withValues(alpha: 0.10),
                              Colors.transparent,
                            ]),
                          ),
                        ),
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.6),
                                blurRadius: 50,
                                offset: const Offset(0, 18),
                              ),
                              BoxShadow(
                                color: AppTheme.secondary.withValues(alpha: 0.28),
                                blurRadius: 90,
                                offset: const Offset(0, 32),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'F',
                              style: TextStyle(
                                fontSize: 66,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    FadeTransition(
                      opacity: _textFade,
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (b) =>
                                AppTheme.primaryGradient.createShader(b),
                            child: const Text(
                              'Farketmez',
                              style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Nereye gidilir karar verelim',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 32),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: _showWarmup
                                ? _WarmupIndicator(key: const ValueKey('warmup'))
                                : const SizedBox(key: ValueKey('empty'), height: 36),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WarmupIndicator extends StatelessWidget {
  const _WarmupIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              AppTheme.secondary.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Sunucu uyandırılıyor...',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary.withValues(alpha: 0.8),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
