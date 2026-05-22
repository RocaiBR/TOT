import 'package:flutter/material.dart';
import '../app_theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  // Logo
  late AnimationController _logoCtrl;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _logoY;

  // Textos / tagline
  late AnimationController _textCtrl;
  late Animation<double> _textFade;

  // Linha brilhante
  late AnimationController _lineCtrl;
  late Animation<double> _lineWidth;

  // Brilho pulsante
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    // 1. Logo
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOut);
    _logoScale = Tween<double>(begin: 0.75, end: 1.0)
        .animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));
    _logoY = Tween<double>(begin: 24.0, end: 0.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic));

    // 2. Texto
    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn);

    // 3. Linha
    _lineCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _lineWidth = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _lineCtrl, curve: Curves.easeOutCubic));

    // 4. Pulso (loop infinito)
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.55, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Sequência de entrada: logo → linha → texto
    _logoCtrl.forward().then((_) async {
      await Future.delayed(const Duration(milliseconds: 80));
      if (mounted) _lineCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) _textCtrl.forward();
    });

    // Navegar para login após 2,5 s (mantém o tempo original)
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _lineCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── FUNDO: grade de pontos ──────────────────────────────
          CustomPaint(painter: _DotGridPainter()),

          // ── BRILHO CENTRAL PULSANTE ─────────────────────────────
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Center(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.08 * _pulse.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── CONTEÚDO CENTRAL ────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo card animado
                AnimatedBuilder(
                  animation: _logoCtrl,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, _logoY.value),
                    child: FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(scale: _logoScale, child: child),
                    ),
                  ),
                  child: _buildLogoCard(),
                ),

                const SizedBox(height: 28),

                // Linha decorativa com gradiente
                AnimatedBuilder(
                  animation: _lineWidth,
                  builder: (_, __) => SizedBox(
                    width: 200 * _lineWidth.value,
                    child: Container(
                      height: 1.5,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            AppColors.accent,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // Tagline + subtítulo
                FadeTransition(
                  opacity: _textFade,
                  child: Column(
                    children: [
                      const Text(
                        'PINHALENSE',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 5.0,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Auxílio de pesquisa e automatização',
                        style: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.8),
                          fontSize: 12,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 52),

                // Barra de progresso estilizada
                SizedBox(
                  width: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: const LinearProgressIndicator(
                      value: null,
                      minHeight: 2,
                      backgroundColor: Color(0xFF2A2A30),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── VERSÃO (canto inferior) ─────────────────────────────
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _textFade,
              child: Text(
                'v1.0.0 · PINHALENSE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary.withOpacity(0.5),
                  fontSize: 10,
                  letterSpacing: 2.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoCard() {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.28),
            blurRadius: 48,
            spreadRadius: 4,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Image.asset(
        'assets/images/logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Text(
            'PINHALENSE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

// Pintor de grade de pontos (fundo atmosférico)
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textSecondary.withOpacity(0.12)
      ..strokeCap = StrokeCap.round;

    const spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
