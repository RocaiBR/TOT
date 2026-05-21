import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/ia_service.dart';
import '../utils/chat_storage.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _chatController = TextEditingController();

  static ChatMessage _mensagemBoasVindas() => ChatMessage(
        sender: 'TOT',
        text: 'Olá! Sou o TOT, o seu assistente preditivo. Como posso ajudar?',
      );

  final List<ChatMessage> _messages = [_mensagemBoasVindas()];

  String? _currentChatId;

  bool _isDark = true;
  XFile? _selectedImage;
  bool _isUploading = false;
  bool _isCarregandoConversa = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return;
      setState(() => _selectedImage = image);
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

  Future<void> _garantirConversa({String? tituloInicial}) async {
    if (!ChatStorage.usuarioLogado) return;
    if (_currentChatId != null) return;
    final novoId = await ChatStorage.criarConversa(
      titulo: (tituloInicial == null || tituloInicial.trim().isEmpty)
          ? 'Nova conversa'
          : tituloInicial.trim(),
    );
    if (mounted) {
      setState(() => _currentChatId = novoId);
    } else {
      _currentChatId = novoId;
    }
  }

  Future<void> _persistirMensagem(ChatMessage msg) async {
    if (!ChatStorage.usuarioLogado || _currentChatId == null) return;
    try {
      await ChatStorage.adicionarMensagem(_currentChatId!, msg);
    } catch (e) {
      debugPrint('[ChatStorage] Erro ao salvar mensagem: $e');
    }
  }

  void _iniciarNovoChat() {
    setState(() {
      _currentChatId = null;
      _messages
        ..clear()
        ..add(_mensagemBoasVindas());
      _selectedImage = null;
      _chatController.clear();
    });
  }

  Future<void> _abrirConversa(ConversaSalva conv) async {
    Navigator.pop(context);
    setState(() {
      _isCarregandoConversa = true;
      _messages.clear();
      _currentChatId = conv.id;
    });
    try {
      final msgs = await ChatStorage.carregarMensagens(conv.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs.isEmpty ? [_mensagemBoasVindas()] : msgs);
        _isCarregandoConversa = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..add(_mensagemBoasVindas());
        _isCarregandoConversa = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erro ao carregar conversa: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _alternarFixar(ConversaSalva conv) async {
    try {
      await ChatStorage.alternarFixar(conv.id, !conv.fixado);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível alterar: $e')),
        );
      }
    }
  }

  Future<void> _renomearConversa(ConversaSalva conv) async {
    final controller = TextEditingController(text: conv.titulo);
    final novoTitulo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Renomear conversa',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Novo título',
            hintStyle: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child:
                const Text('SALVAR', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );

    if (novoTitulo != null && novoTitulo.isNotEmpty) {
      try {
        await ChatStorage.renomearConversa(conv.id, novoTitulo);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao renomear: $e')),
          );
        }
      }
    }
  }

  Future<void> _confirmarExclusao(ConversaSalva conv) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Excluir conversa',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Tem certeza que deseja excluir "${conv.titulo}"? '
          'Esta ação não pode ser desfeita.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('EXCLUIR',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirma != true) return;
    try {
      await ChatStorage.excluirConversa(conv.id);
      if (mounted && conv.id == _currentChatId) {
        _iniciarNovoChat();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e')),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    String? uploadedImageUrl;
    Uint8List? imageBytesToIA;

    final ehPrimeiraMensagemDoUsuario =
        !_messages.any((m) => m.sender == 'Você');
    final tituloInicial = ehPrimeiraMensagemDoUsuario
        ? (text.isNotEmpty ? text : 'Imagem enviada')
        : null;

    await _garantirConversa(tituloInicial: tituloInicial);

    final msgUsuario = ChatMessage(
      sender: 'Você',
      text: text,
      imageUrl: _selectedImage?.path,
    );

    setState(() {
      _messages.add(msgUsuario);
      _isUploading = true;
    });

    if (_selectedImage != null) {
      try {
        if (kIsWeb) {
          imageBytesToIA = await _selectedImage!.readAsBytes();
        } else {
          imageBytesToIA = await File(_selectedImage!.path).readAsBytes();
        }

        final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonimo';
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final storagePath =
            'chats/$userId/${timestamp}_${_selectedImage!.name}';

        final ref = FirebaseStorage.instance.ref(storagePath);
        final uploadTask = await ref.putData(
          imageBytesToIA,
          SettableMetadata(
              contentType: _contentTypeFromName(_selectedImage!.name)),
        );
        uploadedImageUrl = await uploadTask.ref.getDownloadURL();

        await FirebaseFirestore.instance.collection('chats').add({
          'text': text,
          'imageUrl': uploadedImageUrl,
          'storagePath': storagePath,
          'senderId': userId,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Erro Firebase Storage: ${e.code} — ${e.message}'),
                backgroundColor: Colors.red),
          );
        }
        setState(() => _isUploading = false);
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Erro ao processar imagem: $e'),
                backgroundColor: Colors.red),
          );
        }
        setState(() => _isUploading = false);
        return;
      }
    }

    final msgUsuarioPersistir = ChatMessage(
      sender: 'Você',
      text: text,
      imageUrl: uploadedImageUrl ?? msgUsuario.imageUrl,
    );
    await _persistirMensagem(msgUsuarioPersistir);

    setState(() {
      _selectedImage = null;
      _isUploading = false;
      _chatController.clear();
    });

    if (imageBytesToIA != null) {
      setState(() {
        _messages.add(
            ChatMessage(sender: 'TOT', text: 'Analisando imagem com IA...'));
      });

      try {
        final snapshot =
            await FirebaseFirestore.instance.collection('banco_imagens').get();

        if (snapshot.docs.isEmpty) {
          if (mounted) {
            final msg = ChatMessage(
              sender: 'TOT',
              text:
                  'O banco de imagens está vazio. Adicione imagens de referência primeiro.',
            );
            setState(() {
              _messages.removeLast();
              _messages.add(msg);
            });
            await _persistirMensagem(msg);
          }
          return;
        }

        final List<Map<String, dynamic>> imagensBanco = [];
        for (var doc in snapshot.docs) {
          final dados = doc.data();
          if (!dados.containsKey('imageUrl')) continue;
          try {
            Uint8List? bytes;

            if (dados.containsKey('storagePath') &&
                (dados['storagePath'] as String).isNotEmpty) {
              bytes = await FirebaseStorage.instance
                  .ref(dados['storagePath'] as String)
                  .getData()
                  .timeout(const Duration(seconds: 20));
            }

            if (bytes != null) {
              imagensBanco.add({
                'imageUrl': dados['imageUrl'],
                'bytes': bytes,
              });
            } else {
              print(
                  '[banco_imagens] doc ${doc.id} sem storagePath ou bytes vazios — pulando.');
            }
          } catch (e) {
            print('[banco_imagens] Erro ao baixar imagem do banco: $e');
          }
        }

        if (imagensBanco.isEmpty) {
          if (mounted) {
            final msg = ChatMessage(
              sender: 'TOT',
              text:
                  'Não consegui acessar as imagens do banco. Verifique a conexão.',
            );
            setState(() {
              _messages.removeLast();
              _messages.add(msg);
            });
            await _persistirMensagem(msg);
          }
          return;
        }

        final resultado = await IaService.analisarComContexto(
          imagemUsuario: imageBytesToIA,
          imagensBanco: imagensBanco,
          textoUsuario: text.isNotEmpty ? text : 'análise de imagem',
        );

        if (mounted) {
          ChatMessage respostaIA;
          if (resultado == null) {
            respostaIA = ChatMessage(
              sender: 'TOT',
              text: 'Não consegui processar a imagem. Tente novamente.',
            );
          } else if (resultado.containsKey('erro')) {
            respostaIA = ChatMessage(
              sender: 'TOT',
              text: '⚠️ ${resultado['erro']}',
            );
          } else {
            respostaIA = ChatMessage(
              sender: 'TOT',
              text: resultado['mensagem'] as String,
              imageUrl: resultado['imageUrl'] as String?,
            );
          }
          setState(() {
            _messages.removeLast();
            _messages.add(respostaIA);
          });
          await _persistirMensagem(respostaIA);
        }
      } catch (e) {
        if (mounted) {
          final msg = ChatMessage(
            sender: 'TOT',
            text: 'Erro ao analisar imagem: $e',
          );
          setState(() {
            _messages.removeLast();
            _messages.add(msg);
          });
          await _persistirMensagem(msg);
        }
      }
    } else if (text.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 600), () async {
        if (mounted) {
          final msg = ChatMessage(
            sender: 'TOT',
            text:
                'Para ativar a busca preditiva, anexe uma imagem usando o ícone de clipe.',
          );
          setState(() {
            _messages.add(msg);
          });
          await _persistirMensagem(msg);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isDark ? AppColors.surface : const Color(0xFFF7F3F5);
    final textColor = _isDark ? AppColors.textPrimary : const Color(0xFF1C0F18);

    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: bgColor),
      child: Scaffold(
        appBar: buildGradientAppBar(title: 'CHAT'),
        drawer: _buildDrawer(),
        body: Column(
          children: [
            Expanded(
              child: _isCarregandoConversa
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isUser = msg.sender == 'Você';

                        final bubbleColor = isUser
                            ? (_isDark
                                ? AppColors.primaryLight.withOpacity(0.2)
                                : AppColors.primary.withOpacity(0.12))
                            : (_isDark
                                ? AppColors.cardDark
                                : const Color(0xFFEDE0E5));

                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            padding: const EdgeInsets.all(12),
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75),
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
                                      child: (kIsWeb ||
                                              msg.imageUrl!.startsWith('http'))
                                          ? Image.network(
                                              msg.imageUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error,
                                                      stackTrace) =>
                                                  const Text(
                                                      '[Erro ao carregar imagem]',
                                                      style: TextStyle(
                                                          color: Colors.red)),
                                            )
                                          : Image.file(
                                              File(msg.imageUrl!),
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error,
                                                      stackTrace) =>
                                                  const Text(
                                                      '[Erro ao carregar imagem]',
                                                      style: TextStyle(
                                                          color: Colors.red)),
                                            ),
                                    ),
                                  ),
                                if (msg.text.isNotEmpty)
                                  Text(
                                    '${msg.sender}: ${msg.text}',
                                    style: TextStyle(color: textColor),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
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

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.cardDark,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              decoration: const BoxDecoration(color: AppColors.primaryDark),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TOT Menu',
                      style: TextStyle(color: Colors.white, fontSize: 24)),
                  SizedBox(height: 4),
                  Text('Seu assistente preditivo',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_comment_outlined,
                  color: AppColors.accent),
              title: const Text('Novo chat',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
              onTap: () {
                _iniciarNovoChat();
                Navigator.pop(context);
              },
            ),
            const Divider(color: Colors.white12, height: 1),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Conversas salvas',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ChatStorage.usuarioLogado
                  ? _buildListaConversas()
                  : _buildAvisoSemLogin(),
            ),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading:
                  const Icon(Icons.help_outline, color: AppColors.textPrimary),
              title: const Text('FAQ',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pushNamed(context, '/faq'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.textPrimary),
              title: const Text('Banco de Imagens',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pushNamed(context, '/admin_banco'),
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
    );
  }

  Widget _buildAvisoSemLogin() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Text(
        'Faça login para salvar suas conversas e acessá-las depois.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }

  Widget _buildListaConversas() {
    return StreamBuilder<List<ConversaSalva>>(
      stream: ChatStorage.streamConversas(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Erro ao carregar conversas: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          );
        }

        final conversas = snapshot.data ?? [];
        if (conversas.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text(
              'Nenhuma conversa salva ainda. Comece a conversar e ela aparecerá aqui.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: conversas.length,
          itemBuilder: (context, i) => _buildItemConversa(conversas[i]),
        );
      },
    );
  }

  Widget _buildItemConversa(ConversaSalva c) {
    final selecionado = c.id == _currentChatId;
    return Container(
      color: selecionado
          ? AppColors.primary.withOpacity(0.15)
          : Colors.transparent,
      child: ListTile(
        dense: true,
        leading: Icon(
          c.fixado ? Icons.push_pin : Icons.chat_bubble_outline,
          color: c.fixado ? AppColors.accent : AppColors.textPrimary,
          size: 20,
        ),
        title: Text(
          c.titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        subtitle: c.previa.isEmpty
            ? null
            : Text(
                c.previa,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
        onTap: () => _abrirConversa(c),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert,
              color: AppColors.textSecondary, size: 20),
          color: AppColors.cardDark,
          onSelected: (v) {
            switch (v) {
              case 'fixar':
                _alternarFixar(c);
                break;
              case 'renomear':
                _renomearConversa(c);
                break;
              case 'excluir':
                _confirmarExclusao(c);
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'fixar',
              child: Row(
                children: [
                  Icon(c.fixado ? Icons.push_pin_outlined : Icons.push_pin,
                      color: AppColors.textPrimary, size: 18),
                  const SizedBox(width: 8),
                  Text(c.fixado ? 'Desafixar' : 'Fixar',
                      style: const TextStyle(color: AppColors.textPrimary)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'renomear',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined,
                      color: AppColors.textPrimary, size: 18),
                  SizedBox(width: 8),
                  Text('Renomear',
                      style: TextStyle(color: AppColors.textPrimary)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'excluir',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                  SizedBox(width: 8),
                  Text('Excluir', style: TextStyle(color: Colors.redAccent)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }
}
