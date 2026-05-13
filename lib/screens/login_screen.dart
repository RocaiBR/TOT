// ==========================================
// ARQUIVO: lib/screens/login_screen.dart
// ==========================================
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/sanitizer.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _isLoading = false;

  Future<void> _fazerLogin() async {
    final emailInput = _emailController.text.trim();
    final senhaInput = _senhaController.text;

    // 1. Verificação de Acesso Mestre (Ignora Firebase e validações de formato)
    if (emailInput == 'admin' && senhaInput == '123') {
      Navigator.pushReplacementNamed(context, '/home',
          arguments: 'Administrador');
      return;
    }

    // 2. Validação de formulário padrão
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 3. Sanitização antes de enviar
      final emailSanitizado = sanitize(emailInput);

      // 4. Autenticação no Firebase
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
              email: emailSanitizado, password: senhaInput);

      // 5. Busca o nome do usuário no Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(userCredential.user!.uid)
          .get();

      String nomeUsuario = "Usuário";
      if (userDoc.exists && userDoc.data() != null) {
        nomeUsuario =
            (userDoc.data() as Map<String, dynamic>)['nome'] ?? "Usuário";
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home',
            arguments: nomeUsuario);
      }
    } on FirebaseAuthException catch (e) {
      String mensagemErro = "Erro ao fazer login.";
      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        mensagemErro = "E-mail ou senha incorretos.";
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
      backgroundColor: const Color(0xFF58001D), // Fundo vinho
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bem-vindo ao Tot',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                        labelText: 'E-mail', border: OutlineInputBorder()),
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Informe o e-mail';
                      // Se for admin, pula a validação regex
                      if (value == 'admin') return null;

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
                      if (value == null || value.isEmpty)
                        return 'Informe a senha';
                      if (value == '123' && _emailController.text == 'admin')
                        return null; // Exceção para master
                      return null; // O Firebase cuidará de validar a senha no login
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
                          onPressed: _fazerLogin,
                          child: const Text('ENTRAR',
                              style: TextStyle(fontSize: 16)),
                        ),
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/register'),
                    child: const Text('Não tem uma conta? Cadastre-se'),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
