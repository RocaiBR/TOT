import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Representa uma mensagem dentro de um chat (usado tanto na UI quanto na persistência).
class ChatMessage {
  final String sender;
  final String text;
  final String? imageUrl;
  final DateTime? timestamp;

  ChatMessage({
    required this.sender,
    required this.text,
    this.imageUrl,
    this.timestamp,
  });
}

/// Representa o resumo de uma conversa salva, como aparece na lista do menu lateral.
class ConversaSalva {
  final String id;
  final String titulo;
  final DateTime? atualizadoEm;
  final bool fixado;
  final String previa;

  ConversaSalva({
    required this.id,
    required this.titulo,
    required this.atualizadoEm,
    required this.fixado,
    required this.previa,
  });

  factory ConversaSalva.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final dados = doc.data() ?? {};
    return ConversaSalva(
      id: doc.id,
      titulo: (dados['titulo'] as String?)?.trim().isNotEmpty == true
          ? dados['titulo'] as String
          : 'Nova conversa',
      atualizadoEm: (dados['atualizadoEm'] as Timestamp?)?.toDate(),
      fixado: (dados['fixado'] as bool?) ?? false,
      previa: (dados['previa'] as String?) ?? '',
    );
  }
}

class ChatStorage {
  static String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  /// `true` se há usuário autenticado e portanto há persistência ativa.
  static bool get usuarioLogado => _userId != null;

  static CollectionReference<Map<String, dynamic>>? _conversasRef() {
    final id = _userId;
    if (id == null) return null;
    return FirebaseFirestore.instance
        .collection('usuarios')
        .doc(id)
        .collection('conversas');
  }

  /// Stream de todas as conversas do usuário, com fixadas no topo e mais
  /// recentes em primeiro lugar dentro de cada grupo.
  static Stream<List<ConversaSalva>> streamConversas() {
    final ref = _conversasRef();
    if (ref == null) return Stream.value(<ConversaSalva>[]);

    return ref.snapshots().map((snap) {
      final lista = snap.docs.map(ConversaSalva.fromDoc).toList();
      lista.sort((a, b) {
        // Fixadas primeiro
        if (a.fixado != b.fixado) return a.fixado ? -1 : 1;
        // Dentro de cada grupo: atualizadas mais recentemente em cima
        final aT = a.atualizadoEm?.millisecondsSinceEpoch ?? 0;
        final bT = b.atualizadoEm?.millisecondsSinceEpoch ?? 0;
        return bT.compareTo(aT);
      });
      return lista;
    });
  }

  /// Cria nova conversa em branco e devolve o id gerado. Retorna `null` se o
  /// usuário não estiver autenticado.
  static Future<String?> criarConversa(
      {String titulo = 'Nova conversa'}) async {
    final ref = _conversasRef();
    if (ref == null) return null;
    final doc = await ref.add({
      'titulo': titulo,
      'criadoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
      'fixado': false,
      'previa': '',
    });
    return doc.id;
  }

  /// Lê todas as mensagens de uma conversa, em ordem cronológica.
  static Future<List<ChatMessage>> carregarMensagens(String chatId) async {
    final ref = _conversasRef();
    if (ref == null) return [];
    final snap = await ref
        .doc(chatId)
        .collection('mensagens')
        .orderBy('timestamp')
        .get();
    return snap.docs.map((d) {
      final dados = d.data();
      return ChatMessage(
        sender: (dados['sender'] as String?) ?? 'TOT',
        text: (dados['text'] as String?) ?? '',
        imageUrl: dados['imageUrl'] as String?,
        timestamp: (dados['timestamp'] as Timestamp?)?.toDate(),
      );
    }).toList();
  }

  /// Adiciona uma mensagem à conversa e atualiza preview/título conforme o caso.
  /// Se [tituloSeNovo] for fornecido, o título da conversa será atualizado
  /// (útil para definir o título a partir da primeira mensagem do usuário).
  static Future<void> adicionarMensagem(
    String chatId,
    ChatMessage msg, {
    String? tituloSeNovo,
  }) async {
    final ref = _conversasRef();
    if (ref == null) return;

    final docRef = ref.doc(chatId);
    final batch = FirebaseFirestore.instance.batch();

    final novaMsg = docRef.collection('mensagens').doc();
    batch.set(novaMsg, {
      'sender': msg.sender,
      'text': msg.text,
      'imageUrl': msg.imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
    });

    final atualizacoes = <String, dynamic>{
      'atualizadoEm': FieldValue.serverTimestamp(),
      'previa': _gerarPrevia(msg),
    };
    if (tituloSeNovo != null && tituloSeNovo.trim().isNotEmpty) {
      atualizacoes['titulo'] = _truncar(tituloSeNovo.trim(), 60);
    }

    batch.set(docRef, atualizacoes, SetOptions(merge: true));
    await batch.commit();
  }

  /// Alterna o estado de "fixado" da conversa.
  static Future<void> alternarFixar(String chatId, bool fixar) async {
    final ref = _conversasRef();
    if (ref == null) return;
    await ref.doc(chatId).update({'fixado': fixar});
  }

  /// Renomeia o título de uma conversa salva.
  static Future<void> renomearConversa(String chatId, String novoTitulo) async {
    final ref = _conversasRef();
    if (ref == null) return;
    final t = novoTitulo.trim();
    if (t.isEmpty) return;
    await ref.doc(chatId).update({'titulo': _truncar(t, 60)});
  }

  /// Exclui a conversa e todas as suas mensagens.
  static Future<void> excluirConversa(String chatId) async {
    final ref = _conversasRef();
    if (ref == null) return;
    final docRef = ref.doc(chatId);

    // Remove mensagens em lotes de 400 (limite do batch do Firestore é 500).
    QuerySnapshot<Map<String, dynamic>> snap;
    do {
      snap = await docRef.collection('mensagens').limit(400).get();
      if (snap.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } while (snap.docs.length == 400);

    await docRef.delete();
  }

  //  Helpers internos

  static String _gerarPrevia(ChatMessage msg) {
    final base = msg.text.trim();
    if (base.isEmpty && msg.imageUrl != null) return '[Imagem]';
    return _truncar(base, 80);
  }

  static String _truncar(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}...';
}
