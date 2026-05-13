// ==========================================
// ARQUIVO: lib/register_page.dart
// ==========================================
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/sanitizer.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _isLoading = false;

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. Sanitização dos dados antes de criar a conta
      final nomeSanitizado = sanitize(_nomeController.text);
      final emailSanitizado = sanitize(_emailController.text);
      final senha = _senhaController.text;

      // 2. Criação do usuário no Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
              email: emailSanitizado, password: senha);

      // 3. Salvamento dos dados complementares no Cloud Firestore
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userCredential.user!.uid)
          .set({
        'nome': nomeSanitizado,
        'email': emailSanitizado,
        'dataCriacao': FieldValue.serverTimestamp(),
        'tipo': 'usuario',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conta criada com sucesso!')),
        );
        Navigator.pop(context); // Volta para a tela de login
      }
    } on FirebaseAuthException catch (e) {
      String mensagemErro = "Erro ao registrar.";
      if (e.code == 'email-already-in-use') {
        mensagemErro = "Este e-mail já está em uso.";
      } else if (e.code == 'invalid-email') {
        mensagemErro = "E-mail inválido.";
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagemErro)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastro', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF58001D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(
                    labelText: 'Nome Completo', border: OutlineInputBorder()),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Informe seu nome' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                    labelText: 'E-mail', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Informe o e-mail';
                  final emailRegex =
                      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                  if (!emailRegex.hasMatch(value))
                    return 'Formato de e-mail inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _senhaController,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Senha', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Informe a senha';
                  // Validação: Mínimo 6 caracteres, pelo menos 1 letra e 1 número
                  final senhaRegex =
                      RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d@$!%*?&]{6,}$');
                  if (!senhaRegex.hasMatch(value)) {
                    return 'A senha deve ter no mínimo 6 caracteres, 1 letra e 1 número';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF58001D),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: _registrar,
                      child: const Text('CADASTRAR',
                          style: TextStyle(fontSize: 16)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
