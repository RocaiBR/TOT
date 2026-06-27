import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../app_theme.dart';

class _ImageCard extends StatefulWidget {
  final Map<String, dynamic> img;
  final VoidCallback onRemove;

  const _ImageCard({required this.img, required this.onRemove});

  @override
  State<_ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<_ImageCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _shadow;
  late Animation<double> _overlayOpacity;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic),
    );
    _shadow = Tween<double>(begin: 12.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic),
    );
    _overlayOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _pressIn() {
    setState(() => _hovered = true);
    _ctrl.forward();
  }

  void _pressOut() {
    setState(() => _hovered = false);
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final rawNome = (widget.img['nome'] as String?) ?? '';
    final label = rawNome.isNotEmpty
        ? rawNome.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '').toUpperCase()
        : 'SEM NOME';

    return MouseRegion(
      onEnter: (_) => _pressIn(),
      onExit: (_) => _pressOut(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => _pressIn(),
        onTapUp: (_) => _pressOut(),
        onTapCancel: _pressOut,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            return Transform.scale(
              scale: _scale.value,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hovered
                        ? AppColors.accent.withValues(alpha: 0.7)
                        : AppColors.cardBorder.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent
                          .withValues(alpha: _hovered ? 0.35 : 0.12),
                      blurRadius: _shadow.value * 2.5,
                      spreadRadius: _hovered ? 1 : 0,
                      offset: Offset(0, _shadow.value * 0.5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ── IMAGEM ──────────────────────────────────────
                      Image.network(
                        widget.img['imageUrl'],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.cardDark,
                          child: const Icon(Icons.broken_image_rounded,
                              color: AppColors.textMuted, size: 32),
                        ),
                      ),

                      // ── OVERLAY PERMANENTE (gradiente base) ─────────
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.45, 1.0],
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.82),
                            ],
                          ),
                        ),
                      ),

                      // ── OVERLAY HOVER (vinho brilhante) ─────────────
                      Opacity(
                        opacity: _overlayOpacity.value * 0.25,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment.center,
                              radius: 1.0,
                              colors: [
                                AppColors.crimson.withValues(alpha: 0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      // ── LABEL (sobreposição inferior) ────────────────
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Linha decorativa acima do texto
                              Container(
                                height: 1.5,
                                margin: const EdgeInsets.only(bottom: 5),
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
                              Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.accentGlow,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.8,
                                  shadows: [
                                    Shadow(
                                      color: AppColors.crimson,
                                      blurRadius: 10,
                                    ),
                                    Shadow(
                                      color: Colors.black,
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── BOTÃO REMOVER ────────────────────────────────
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: widget.onRemove,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.6),
                                  width: 1),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.close_rounded,
                                color: Colors.red, size: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class AdminBancoPage extends StatefulWidget {
  const AdminBancoPage({super.key});

  @override
  State<AdminBancoPage> createState() => _AdminBancoPageState();
}

class _AdminBancoPageState extends State<AdminBancoPage> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  List<Map<String, dynamic>> _imagensBanco = [];

  @override
  void initState() {
    super.initState();
    _carregarBanco();
  }

  Future<void> _carregarBanco() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('banco_imagens').get();
    setState(() {
      _imagensBanco =
          snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    });
  }

  /// Deduz o content-type a partir da extensão do arquivo.
  String _contentTypeFromName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _adicionarImagem() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => _isUploading = true);

    try {
      // Lê os bytes da imagem
      final bytes = kIsWeb
          ? await image.readAsBytes()
          : await File(image.path).readAsBytes();

      // Sobe para o Firebase Storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'banco_imagens/${timestamp}_${image.name}';

      final ref = FirebaseStorage.instance.ref(storagePath);
      final uploadTask = await ref.putData(
        bytes,
        SettableMetadata(contentType: _contentTypeFromName(image.name)),
      );

      // URL pública (com token) que serve para <Image.network>
      final imageUrl = await uploadTask.ref.getDownloadURL();

      // Salva no Firestore.
      // baixar via SDK do Firebase (sem problemas de CORS no web).
      await FirebaseFirestore.instance.collection('banco_imagens').add({
        'imageUrl': imageUrl,
        'storagePath': storagePath,
        'nome': image.name,
        'adicionadoEm': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 10),
                Text('Imagem adicionada ao banco com sucesso!'),
              ],
            ),
            backgroundColor: AppColors.primaryLight,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }

      await _carregarBanco();
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro Firebase Storage: ${e.code} — ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _removerImagem(Map<String, dynamic> img) async {
    final docId = img['id'] as String;

    // Tenta apagar o arquivo do Storage também (se houver storagePath salvo)
    final storagePath = img['storagePath'] as String?;
    if (storagePath != null && storagePath.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(storagePath).delete();
      } catch (e) {
        // O arquivo pode não existir mais — não bloqueia a remoção do doc
        debugPrint('[banco_imagens] aviso ao remover do Storage: $e');
      }
    }

    await FirebaseFirestore.instance
        .collection('banco_imagens')
        .doc(docId)
        .delete();
    await _carregarBanco();
  }

  // ── Header de seção ────────────────────────────────────────────
  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          // Ícone decorativo
          Container(
            width: 3,
            height: 22,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.accentGlow, AppColors.primaryDark],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${_imagensBanco.length} ',
                  style: const TextStyle(
                    color: AppColors.accentGlow,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
                TextSpan(
                  text: _imagensBanco.length == 1
                      ? 'IMAGEM NO BANCO'
                      : 'IMAGENS NO BANCO',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: buildGradientAppBar(title: 'BANCO DE IMAGENS'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── BOTÃO ADICIONAR ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: GestureDetector(
              onTap: _isUploading ? null : _adicionarImagem,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  gradient: _isUploading
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.primaryDark, AppColors.crimson],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  color: _isUploading ? AppColors.cardMid : null,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isUploading
                        ? AppColors.cardBorder
                        : AppColors.crimson.withValues(alpha: 0.4),
                    width: 1,
                  ),
                  boxShadow: _isUploading
                      ? null
                      : [
                          const BoxShadow(
                            color: Color(0x44B91C4A),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isUploading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent),
                      )
                    else
                      const Icon(Icons.add_photo_alternate_outlined,
                          color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      _isUploading
                          ? 'ENVIANDO...'
                          : 'ADICIONAR IMAGEM DE REFERÊNCIA',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── CONTADOR ─────────────────────────────────────────────
          _buildSectionHeader(),

          // Linha divisória
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    AppColors.cardBorder,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── GRID DE IMAGENS ──────────────────────────────────────
          Expanded(
            child: _imagensBanco.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 56,
                          color: AppColors.textMuted.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'BANCO VAZIO',
                          style: TextStyle(
                            color: AppColors.accentGlow,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Adicione imagens de referência\npara ativar a análise preditiva',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _imagensBanco.length,
                    itemBuilder: (context, index) {
                      final img = _imagensBanco[index];
                      return _ImageCard(
                        img: img,
                        onRemove: () => _removerImagem(img),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
