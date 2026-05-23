import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../app_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _dataNascimentoController = TextEditingController();

  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;

  Uint8List? _novaImagemBytes; // bytes da imagem selecionada
  XFile? _novaImagemXFile; // XFile para upload no Storage
  String? _photoURL;
  String _email = '';

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _dataNascimentoController.dispose();
    super.dispose();
  }

  // Carrega dados do Firestore e Firebase Auth
  Future<void> _carregarDados() async {
    if (_user == null) return;
    setState(() => _isLoading = true);

    try {
      await _user!.reload();
      final freshUser = FirebaseAuth.instance.currentUser!;

      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(freshUser.uid)
          .get();

      final data = doc.data() ?? {};

      setState(() {
        _email = freshUser.email ?? '';
        _nomeController.text = data['nome'] ?? freshUser.displayName ?? '';
        _telefoneController.text = data['telefone'] ?? '';
        _dataNascimentoController.text = data['dataNascimento'] ?? '';
        _photoURL = data['photoURL'] ?? freshUser.photoURL;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  //  Seleciona imagem da galeria
  Future<void> _selecionarImagem() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _novaImagemBytes = bytes;
        _novaImagemXFile = picked;
      });
    }
  }

  //  Faz upload da imagem para o Firebase Storage
  Future<String?> _uploadImagem() async {
    if (_novaImagemBytes == null) return _photoURL;

    final ref = FirebaseStorage.instance
        .ref()
        .child('usuarios/${_user!.uid}/profile.jpg');

    // putData funciona tanto na web quanto em mobile/desktop
    await ref.putData(
      _novaImagemBytes!,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await ref.getDownloadURL();
  }

  // Salva alterações no Firestore e Firebase Auth
  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final newPhotoURL = await _uploadImagem();

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(_user!.uid)
          .set({
        'nome': _nomeController.text.trim(),
        'email': _email,
        'telefone': _telefoneController.text.trim(),
        'dataNascimento': _dataNascimentoController.text.trim(),
        'photoURL': newPhotoURL ?? '',
      }, SetOptions(merge: true));

      await _user!.updateDisplayName(_nomeController.text.trim());
      if (newPhotoURL != null && newPhotoURL.isNotEmpty) {
        await _user!.updatePhotoURL(newPhotoURL);
      }

      setState(() {
        _photoURL = newPhotoURL;
        _novaImagemBytes = null;
        _novaImagemXFile = null;
        _isEditing = false;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil atualizado com sucesso! ✓'),
            backgroundColor: Color(0xFF1B7A3E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  //  Cancela edição e recarrega dados originais
  Future<void> _cancelarEdicao() async {
    setState(() {
      _isEditing = false;
      _novaImagemBytes = null;
      _novaImagemXFile = null;
    });
    await _carregarDados();
  }

  //  Abre seletor de data
  Future<void> _selecionarData() async {
    final parts = _dataNascimentoController.text.split('/');
    DateTime initial = DateTime(1990, 1, 1);
    if (parts.length == 3) {
      try {
        initial = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      } catch (_) {}
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.cardDark,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      _dataNascimentoController.text =
          '${picked.day.toString().padLeft(2, '0')}/'
          '${picked.month.toString().padLeft(2, '0')}/'
          '${picked.year}';
    }
  }

  //  Avatar com botão de câmera no modo edição
  Widget _buildAvatar() {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.wine, AppColors.crimson],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: AppColors.accent.withOpacity(0.5),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.crimson.withOpacity(0.4),
                blurRadius: 24,
              ),
            ],
          ),
          child: ClipOval(
            child: _novaImagemBytes != null
                ? Image.memory(_novaImagemBytes!, fit: BoxFit.cover)
                : (_photoURL != null && _photoURL!.isNotEmpty)
                    ? Image.network(
                        _photoURL!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.white,
                      ),
          ),
        ),
        if (_isEditing)
          GestureDetector(
            onTap: _selecionarImagem,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.crimson,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.crimson.withOpacity(0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  //Campo de informação (visualização ou edição)
  Widget _buildInfoField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    bool readOnly = false,
    VoidCallback? onTap,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    if (!_isEditing) {
      return Material(
        color: AppColors.cardDark,
        child: ListTile(
          leading: Icon(icon, color: AppColors.primary),
          title: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          subtitle: Text(
            controller.text.isEmpty ? '—' : controller.text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon: Icon(icon, color: AppColors.primary),
          suffixIcon: readOnly
              ? const Icon(
                  Icons.calendar_today,
                  color: AppColors.textSecondary,
                  size: 18,
                )
              : null,
          filled: true,
          fillColor: AppColors.cardDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 1.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildGradientAppBar(
        title: 'Meu Perfil',
        actions: _isEditing
            ? [
                if (_isSaving)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: _salvar,
                    icon:
                        const Icon(Icons.check, color: Colors.white, size: 18),
                    label: const Text(
                      'SALVAR',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
              ]
            : null,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 24),

                    // Avatar
                    _buildAvatar(),
                    const SizedBox(height: 16),

                    // Nome e email (cabeçalho)
                    Text(
                      _nomeController.text.isEmpty
                          ? 'Usuário TOT'
                          : _nomeController.text,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _email,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Card de informações
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.cardBorder,
                          width: 0.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: EdgeInsets.all(_isEditing ? 16.0 : 0),
                        child: Column(
                          children: [
                            _buildInfoField(
                              icon: Icons.person_outline,
                              label: 'Nome',
                              controller: _nomeController,
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Informe seu nome'
                                  : null,
                            ),
                            if (!_isEditing)
                              const Divider(
                                height: 1,
                                color: AppColors.cardBorder,
                              ),
                            _buildInfoField(
                              icon: Icons.phone_outlined,
                              label: 'Telefone',
                              controller: _telefoneController,
                              keyboardType: TextInputType.phone,
                            ),
                            if (!_isEditing)
                              const Divider(
                                height: 1,
                                color: AppColors.cardBorder,
                              ),
                            _buildInfoField(
                              icon: Icons.cake_outlined,
                              label: 'Data de Nascimento',
                              controller: _dataNascimentoController,
                              readOnly: _isEditing,
                              onTap: _isEditing ? _selecionarData : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    //  Botão principal
                    if (!_isEditing)
                      AnimatedPressButton(
                        onPressed: () => setState(() => _isEditing = true),
                        isOutlined: true,
                        child: const Text(
                          'EDITAR PERFIL',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      )
                    else
                      AnimatedPressButton(
                        onPressed: _cancelarEdicao,
                        isOutlined: true,
                        child: const Text(
                          'CANCELAR',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Botão de logout
                    GestureDetector(
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.cardDark,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(
                                  color: AppColors.cardBorder, width: 0.5),
                            ),
                            title: const Text('Sair da conta',
                                style: TextStyle(color: AppColors.textPrimary)),
                            content: const Text(
                              'Tem certeza que deseja sair?',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('CANCELAR',
                                    style: TextStyle(
                                        color: AppColors.textSecondary)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('SAIR',
                                    style: TextStyle(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && mounted) {
                          await FirebaseAuth.instance.signOut();
                          Navigator.pushNamedAndRemoveUntil(
                              context, '/', (_) => false);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.red.withOpacity(0.5), width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.logout,
                                color: Colors.redAccent, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'SAIR DA CONTA',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }
}
