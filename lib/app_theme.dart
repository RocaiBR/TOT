import 'package:flutter/material.dart';

class AppColors {
  // Cores principais — vinho profundo
  static const Color primary = Color(0xFF8B1A3A);
  static const Color primaryDark = Color(0xFF4A0E1F);
  static const Color primaryLight = Color(0xFFA82248);
  static const Color crimson = Color(0xFFB91C4A); // vinho vibrante
  static const Color wine = Color(0xFF8B1A3A); // alias de primary

  // Acentos que "saltam" no fundo preto
  static const Color accent = Color(0xFFE8345C); // rosa-carmim neon
  static const Color accentGlow = Color(0xFFFF5A7E); // versão brilhante
  static const Color glow = Color(0xFFFF5A7E); // alias de accentGlow
  static const Color accentSoft =
      Color(0xFFD4688A); // vinho suave (ícones/decorações)
  static const Color gold = Color(0xFFD4A847); // dourado premium

  // Superfícies escuras
  static const Color surface = Color(0xFF0D0608); // preto quase puro
  static const Color bg = Color(0xFF110709);
  static const Color cardDark = Color(0xFF1A0C10);
  static const Color cardMid = Color(0xFF240F16);
  static const Color cardBorder = Color(0xFF3D1525);

  // Texto
  static const Color textPrimary = Color(0xFFF5E6EC);
  static const Color textSecondary = Color(0xFF9E7080);
  static const Color textMuted = Color(0xFF5C3344);

  // Gradiente de borda (efeito premium)
  static const List<Color> borderGradient = [
    Color(0xFFB91C4A),
    Color(0xFF4A0E1F),
    Color(0xFFB91C4A),
  ];
}

// ── AppBar com gradiente e linha brilhante no fundo ──────────────────────────
PreferredSizeWidget buildGradientAppBar({
  required String title,
  List<Widget>? actions,
  Widget? leading,
}) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(60),
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryDark,
            AppColors.primary,
            AppColors.primaryDark
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x66B91C4A),
            blurRadius: 20,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: leading,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 3.0,
          ),
        ),
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.accentGlow,
                  Colors.transparent
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Botão com animação de press ───────────────────────────────────────────────
class AnimatedPressButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  final bool isOutlined;

  const AnimatedPressButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isOutlined = false,
  });

  @override
  State<AnimatedPressButton> createState() => _AnimatedPressButtonState();
}

class _AnimatedPressButtonState extends State<AnimatedPressButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 130));
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onPressed();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            gradient: widget.isOutlined
                ? null
                : const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.crimson],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: widget.isOutlined ? Colors.transparent : null,
            border: widget.isOutlined
                ? Border.all(color: AppColors.crimson, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(10),
            boxShadow: widget.isOutlined
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x55B91C4A),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
