import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../app_theme.dart';

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

      // Salva no Firestore. storagePath é importante porque permite
      // baixar via SDK do Firebase (sem problemas de CORS no web).
      await FirebaseFirestore.instance.collection('banco_imagens').add({
        'imageUrl': imageUrl,
        'storagePath': storagePath,
        'nome': image.name,
        'adicionadoEm': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Imagem adicionada ao banco com sucesso!'),
            backgroundColor: Colors.green,
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
        print('[banco_imagens] aviso ao remover do Storage: $e');
      }
    }

    await FirebaseFirestore.instance
        .collection('banco_imagens')
        .doc(docId)
        .delete();
    await _carregarBanco();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: buildGradientAppBar(title: 'BANCO DE IMAGENS'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : _adicionarImagem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_photo_alternate,
                        color: Colors.white),
                label: Text(
                  _isUploading
                      ? 'Enviando...'
                      : 'Adicionar Imagem de Referência',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${_imagensBanco.length} imagem(ns) no banco',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _imagensBanco.isEmpty
                ? Center(
                    child: Text(
                      'Nenhuma imagem no banco.\nAdicione imagens de referência.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _imagensBanco.length,
                    itemBuilder: (context, index) {
                      final img = _imagensBanco[index];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              img['imageUrl'],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.cardDark,
                                child: const Icon(Icons.broken_image,
                                    color: Colors.grey),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removerImagem(img),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 14),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
