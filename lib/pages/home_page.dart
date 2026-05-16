import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatMessage {
  final String sender;
  final String text;
  final String? imageUrl;

  ChatMessage({
    required this.sender,
    required this.text,
    this.imageUrl,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _chatController = TextEditingController();

  final List<ChatMessage> _messages = [
    ChatMessage(
      sender: 'TOT',
      text: 'Olá! Sou o TOT, o seu assistente preditivo. Como posso ajudar?',
    )
  ];

  bool _isDark = true;

  XFile? _selectedImage;
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return;
      setState(() {
        _selectedImage = image;
      });
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erro ao escolher imagem: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  void _showAttachmentModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Anexar Arquivo', textAlign: TextAlign.center),
          content: Container(
            height: 200,
            width: double.maxFinite,
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.3), width: 2),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pickImage(ImageSource.gallery),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.drive_folder_upload, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Clique para selecionar ou arraste para cá',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('Formatos: PNG, JPG, GIF',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    String? uploadedImageUrl;

    if (_selectedImage != null) {
      setState(() => _isUploading = true);

      try {
        const String cloudName = 'dn2vlkwuf';
        const String uploadPreset = 'TOT_CHAT';

        final url = Uri.parse(
            'https://api.cloudinary.com/v1_1/$cloudName/image/upload');

        final request = http.MultipartRequest('POST', url);
        request.fields['upload_preset'] = uploadPreset;

        if (kIsWeb) {
          final bytes = await _selectedImage!.readAsBytes();
          request.files.add(http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: _selectedImage!.name,
          ));
        } else {
          request.files.add(await http.MultipartFile.fromPath(
            'file',
            _selectedImage!.path,
          ));
        }

        final response = await request.send();

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = await response.stream.bytesToString();
          final jsonMap = jsonDecode(responseData);
          uploadedImageUrl = jsonMap['secure_url'];
        } else {
          throw Exception(
              'Código de erro do Cloudinary: ${response.statusCode}');
        }

        await FirebaseFirestore.instance.collection('chats').add({
          'text': text,
          'imageUrl': uploadedImageUrl,
          'senderId': FirebaseAuth.instance.currentUser?.uid ?? 'anonimo',
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao enviar imagem para o Cloudinary: $e'),
              backgroundColor: Colors.red),
        );
        setState(() => _isUploading = false);
        return;
      }
    }

    setState(() {
      _messages.add(ChatMessage(
        sender: 'Você',
        text: text,
        imageUrl: uploadedImageUrl,
      ));
      _selectedImage = null;
      _isUploading = false;
      _chatController.clear();
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      setState(() {
        _messages.add(ChatMessage(
          sender: 'TOT',
          text: 'Imagem recebida com sucesso',
        ));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // ── Cores adaptadas ao modo ──────────────────────────────────────────────
    final bgColor = _isDark ? AppColors.surface : const Color(0xFFF7F3F5);
    final textColor = _isDark ? AppColors.textPrimary : const Color(0xFF1C0F18);

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: bgColor,
      ),
      child: Scaffold(
        appBar: buildGradientAppBar(title: 'CHAT'),
        drawer: Drawer(
          backgroundColor: AppColors.cardDark,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: AppColors.primaryDark),
                child: Text('TOT Menu',
                    style: TextStyle(color: Colors.white, fontSize: 24)),
              ),
              ListTile(
                leading: const Icon(Icons.chat, color: AppColors.textPrimary),
                title: const Text('Novo Chat',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  setState(() => _messages.clear());
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline,
                    color: AppColors.textPrimary),
                title: const Text('FAQ',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.pushNamed(context, '/faq'),
              ),
              SwitchListTile(
                title: const Text('Modo Escuro',
                    style: TextStyle(color: AppColors.textPrimary)),
                value: _isDark,
                activeColor: AppColors.accent,
                onChanged: (val) => setState(() => _isDark = val),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isUser = msg.sender == 'Você';

                  // ── Cor das bolhas adaptada ao modo ──────────────────────
                  final bubbleColor = isUser
                      ? (_isDark
                          ? AppColors.primaryLight.withOpacity(0.2)
                          : AppColors.primary.withOpacity(0.12))
                      : (_isDark
                          ? AppColors.cardDark
                          : const Color(0xFFEDE0E5));

                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: bubbleColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isUser
                                ? AppColors.primary.withOpacity(0.5)
                                : Colors.transparent),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msg.imageUrl != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  msg.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Text('[Erro ao carregar imagem]',
                                          style: TextStyle(color: Colors.red)),
                                ),
                              ),
                            ),
                          if (msg.text.isNotEmpty)
                            Text(
                              "${msg.sender}: ${msg.text}",
                              style: TextStyle(color: textColor),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Preview da imagem selecionada ────────────────────────────────
            if (_selectedImage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isDark ? AppColors.cardDark : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      height: 60,
                      width: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb
                            ? Image.network(_selectedImage!.path,
                                fit: BoxFit.cover, height: 60, width: 60)
                            : Image.file(File(_selectedImage!.path),
                                fit: BoxFit.cover, height: 60, width: 60),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pronto para enviar',
                              style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text('Imagem anexada',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
                      onPressed: () => setState(() => _selectedImage = null),
                    ),
                  ],
                ),
              ),

            // ── Campo de texto ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary),
                          )
                        : const Icon(Icons.attach_file,
                            color: AppColors.primary),
                    onPressed: _isUploading ? null : _showAttachmentModal,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Digite a sua dúvida...',
                        hintStyle: TextStyle(
                            color: _isDark
                                ? AppColors.textSecondary
                                : const Color(0xFF7A5566)),
                        filled: true,
                        fillColor: _isDark ? AppColors.cardDark : Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                                color: _isDark
                                    ? Colors.transparent
                                    : AppColors.primary.withOpacity(0.25))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                                color: _isDark
                                    ? Colors.transparent
                                    : AppColors.primary.withOpacity(0.25))),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: AppColors.primary),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
