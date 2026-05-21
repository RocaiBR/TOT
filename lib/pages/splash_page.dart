import 'package:flutter/material.dart';
import '../app_theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late AnimationController _logoController;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;

  late AnimationController _nomeController;
  late Animation<double> _nomeFade;
  late Animation<Offset> _nomeSlide;

  @override
  void initState() {
    super.initState();

    // Animação do logo (igual antes)
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeIn);
    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    // Animação do nome da empresa (entra logo depois do logo)
    _nomeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _nomeFade = CurvedAnimation(parent: _nomeController, curve: Curves.easeIn);
    _nomeSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _nomeController, curve: Curves.easeOut),
    );

    _logoController.forward();
    // Pequeno atraso pra o nome aparecer depois do logo
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _nomeController.forward();
    });

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _nomeController.dispose();
    super.dispose();
  }

  Widget _buildLogoCard() {
    return ScaleTransition(
      scale: _logoScale,
      child: FadeTransition(
        opacity: _logoFade,
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7B1C3D).withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/logo.png',
            height: 90,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Text(
                'PINHALENSE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF7B1C3D),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNomeEmpresa() {
    return SlideTransition(
      position: _nomeSlide,
      child: FadeTransition(
        opacity: _nomeFade,
        child: Column(
          children: const [
            Text(
              'PINHALENSE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Auxílio de pesquisa e automatização',
              style: TextStyle(
                color: Color(0xFFBFA0AD),
                fontSize: 13,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLogoCard(),
            const SizedBox(height: 28),
            _buildNomeEmpresa(),
            const SizedBox(height: 40),
            const SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                color: Color(0xFF7B1C3D),
                backgroundColor: Color(0xFF2A2A30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
