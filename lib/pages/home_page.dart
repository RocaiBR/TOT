import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../app_theme.dart';
import '../utils/ia_service.dart';
import '../utils/pdf_service.dart';
import '../utils/chat_storage.dart';
import '../utils/calculo_capacidade_moega.dart';
import '../theme_notifier.dart';

class _Particle {
  double x, y, vx, vy, radius, alpha, pulse, pulseSpeed;
  Color color;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.alpha,
    required this.pulse,
    required this.pulseSpeed,
    required this.color,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;

  _ParticlePainter(this.particles, Listenable repaint)
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()..strokeWidth = 0.4;
    final dotPaint = Paint();

    for (int i = 0; i < particles.length; i++) {
      final p = particles[i];

      // linhas de conexão
      for (int j = i + 1; j < particles.length; j++) {
        final q = particles[j];
        final dx = p.x - q.x;
        final dy = p.y - q.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 90) {
          linePaint.color =
              AppColors.wine.withValues(alpha: 0.12 * (1 - dist / 90));
          canvas.drawLine(
            Offset(p.x, p.y),
            Offset(q.x, q.y),
            linePaint,
          );
        }
      }

      // ponto
      final a = (p.alpha + math.sin(p.pulse) * 0.15).clamp(0.0, 1.0);
      dotPaint.color = p.color.withValues(alpha: a);
      canvas.drawCircle(Offset(p.x, p.y), p.radius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

//calculadora
enum _CalcEstado { idle, escolhendoFormula, coletandoValor }

class _CalcVariavel {
  final String nome;
  final String descricao;

  /// Quando definido, restringe a entrada a estes valores exatos
  /// (ex.: multiplicador 480/620, divisor 40/60).
  final List<double>? opcoes;

  /// Quando definido, o valor digitado precisa ser ESTRITAMENTE maior
  /// que este limite (ex.: A e B precisam ser > 0,6 por causa da
  /// correção A − 0,6 / B − 0,6).
  final double? minExclusivo;

  const _CalcVariavel(this.nome, this.descricao,
      {this.opcoes, this.minExclusivo});
}

class _CalcFormula {
  final String id;
  final String nome;
  final String descricao;
  final List<_CalcVariavel> variaveis;
  final double Function(Map<String, double> valores) calcular;
  final String Function(Map<String, double> valores, double resultado)
      memoriaCalculo;

  const _CalcFormula({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.variaveis,
    required this.calcular,
    required this.memoriaCalculo,
  });
}

/// Fórmulas disponíveis para cálculo. Conforme as imagens de referência.
final List<_CalcFormula> _formulasDisponiveis = [
  _CalcFormula(
    id: 'moega_padrao',
    nome: 'Moega Padrão',
    descricao: 'Volume de pirâmide simples\n(A × B × C) / 3',
    variaveis: const [
      _CalcVariavel('A', 'medida A'),
      _CalcVariavel('B', 'medida B'),
      _CalcVariavel('C', 'medida C'),
    ],
    calcular: (v) => (v['A']! * v['B']! * v['C']!) / 3,
    memoriaCalculo: (v, r) =>
        '(${v['A']} × ${v['B']} × ${v['C']}) / 3 = ${r.toStringAsFixed(3)}',
  ),
  _CalcFormula(
    id: 'moega_complexa',
    nome: 'Moega Complexa',
    descricao: 'Volume composto: XAC + ABC + (2 × XYZ) + XBAH\n'
        '• ABC = A × B × C\n'
        '• XYZ = X × Y × Z / 2\n'
        '• XBAH = (X + B) × A × H / 3\n'
        '• XAC = X × A × C',
    variaveis: const [
      _CalcVariavel('A', 'medida A'),
      _CalcVariavel('B', 'medida B'),
      _CalcVariavel('C', 'medida C'),
      _CalcVariavel('X', 'medida X'),
      _CalcVariavel('Y', 'medida Y'),
      _CalcVariavel('Z', 'medida Z'),
      _CalcVariavel('H', 'medida H (altura)'),
    ],
    calcular: (v) {
      final A = v['A']!;
      final B = v['B']!;
      final C = v['C']!;
      final X = v['X']!;
      final Y = v['Y']!;
      final Z = v['Z']!;
      final H = v['H']!;
      final ABC = A * B * C;
      final XYZ = X * Y * Z / 2;
      final XBAH = (X + B) * A * H / 3;
      final XAC = X * A * C;
      return XAC + ABC + (2 * XYZ) + XBAH;
    },
    memoriaCalculo: (v, r) {
      final A = v['A']!;
      final B = v['B']!;
      final C = v['C']!;
      final X = v['X']!;
      final Y = v['Y']!;
      final Z = v['Z']!;
      final H = v['H']!;
      final ABC = A * B * C;
      final XYZ = X * Y * Z / 2;
      final XBAH = (X + B) * A * H / 3;
      final XAC = X * A * C;
      return 'ABC  = $A × $B × $C = ${ABC.toStringAsFixed(3)}\n'
          'XYZ  = $X × $Y × $Z / 2 = ${XYZ.toStringAsFixed(3)}\n'
          'XBAH = ($X + $B) × $A × $H / 3 = ${XBAH.toStringAsFixed(3)}\n'
          'XAC  = $X × $A × $C = ${XAC.toStringAsFixed(3)}\n'
          '\nTOTAL = XAC + ABC + (2 × XYZ) + XBAH\n'
          '      = ${XAC.toStringAsFixed(3)} + ${ABC.toStringAsFixed(3)} '
          '+ ${(2 * XYZ).toStringAsFixed(3)} + ${XBAH.toStringAsFixed(3)}\n'
          '      = ${r.toStringAsFixed(3)}';
    },
  ),
  _CalcFormula(
    id: 'capacidade_moega',
    nome: 'Capacidade de Moega',
    descricao: 'Capacidade com desconto de borda de 0,6\n'
        '((A − 0,6) × (B − 0,6) × (C + D)) × M ÷ K\n'
        '• M = multiplicador (480 ou 620)\n'
        '• K = divisor (40 ou 60)',
    variaveis: const [
      _CalcVariavel('A', 'medida A — precisa ser maior que 0,6',
          minExclusivo: kDescontoBorda),
      _CalcVariavel('B', 'medida B — precisa ser maior que 0,6',
          minExclusivo: kDescontoBorda),
      _CalcVariavel('C', 'medida C'),
      _CalcVariavel('D', 'medida D'),
      _CalcVariavel('M', 'multiplicador — digite 480 ou 620',
          opcoes: kMultiplicadoresValidos),
      _CalcVariavel('K', 'divisor — digite 40 ou 60',
          opcoes: kDivisoresValidos),
    ],
    calcular: (v) => calcularCapacidadeMoega(
      a: v['A']!,
      b: v['B']!,
      c: v['C']!,
      d: v['D']!,
      multiplicador: v['M']!,
      divisor: v['K']!,
    ).resultadoFinal,
    memoriaCalculo: (v, r) {
      final det = calcularCapacidadeMoega(
        a: v['A']!,
        b: v['B']!,
        c: v['C']!,
        d: v['D']!,
        multiplicador: v['M']!,
        divisor: v['K']!,
      );
      final m = formatarNumero(v['M']!);
      final k = formatarNumero(v['K']!);
      return 'A\u2032 = ${v['A']} − 0,6 = ${det.aCorrigido.toStringAsFixed(3)}\n'
          'B\u2032 = ${v['B']} − 0,6 = ${det.bCorrigido.toStringAsFixed(3)}\n'
          'R1 = A\u2032 × B\u2032 × C = ${det.resultado1.toStringAsFixed(3)}\n'
          'R2 = A\u2032 × B\u2032 × D = ${det.resultado2.toStringAsFixed(3)}\n'
          'Soma = R1 + R2 = ${det.somaTotal.toStringAsFixed(3)}\n'
          '× $m = ${det.valorMultiplicado.toStringAsFixed(3)}\n'
          '÷ $k = ${r.toStringAsFixed(3)}';
    },
  ),
];

// ─────────────────────────────────────────────
// HomePage
// ─────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Mensagem inicial
  static ChatMessage _mensagemBoasVindas() => ChatMessage(
        sender: 'TOT',
        text:
            'Olá! Sou o TOT, o seu assistente preditivo de alta precisão. Estou pronto para analisar imagens e oferecer insights exclusivos. Como posso ajudá-lo hoje?',
      );

  final List<ChatMessage> _messages = [_mensagemBoasVindas()];

  // Estado (preservado do TOT 16)
  String? _currentChatId;
  bool get _isDark => themeNotifier.value == ThemeMode.dark;
  // Anexos selecionados (imagens e/ou 1ª página de PDFs já renderizada como
  // PNG). Agora é possível enviar VÁRIOS arquivos de uma só vez.
  final List<_Anexo> _anexos = [];
  // O modelo de visão aceita no máx. 5 imagens por requisição; reservamos
  // pelo menos 1 vaga para as imagens do banco de referência.
  static const int _maxAnexos = 4;
  bool _isProcessingPdf = false;
  bool _isUploading = false;
  bool _isCarregandoConversa = false;
  bool _isTyping = false;
  final ImagePicker _picker = ImagePicker();

  // Partículas (Premium)
  late List<_Particle> _particles;
  late AnimationController _particleController;
  late AnimationController _drawerController;
  late AnimationController _overlayController;
  bool _drawerOpen = false;

  // Sugestões (Premium)
  final List<String> _suggestions = [
    'Comparar com banco',
  ];

  static const _particleColors = [
    AppColors.wine,
    AppColors.crimson,
    AppColors.accent,
    AppColors.primary,
  ];

  // Stream cacheada das conversas — criada UMA vez no initState para que o
  // StreamBuilder não seja resetado a cada reconstrução do widget.
  Stream<List<ConversaSalva>>? _conversasStream;

  // Estado da calculadora de fórmulas
  _CalcEstado _calcEstado = _CalcEstado.idle;
  _CalcFormula? _formulaAtual;
  final Map<String, double> _valoresColetados = {};
  int _indiceVariavelAtual = 0;

  @override
  void initState() {
    super.initState();

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )
      ..addListener(_updateParticles)
      ..repeat();

    _drawerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _initParticles();

    // Inscrição única na stream do Firestore .
    if (ChatStorage.usuarioLogado) {
      _conversasStream = ChatStorage.streamConversas();
    }
  }

  void _initParticles() {
    final rng = math.Random();
    _particles = List.generate(55, (_) {
      return _Particle(
        x: rng.nextDouble() * 400,
        y: rng.nextDouble() * 700,
        vx: (rng.nextDouble() - 0.5) * 0.3,
        vy: (rng.nextDouble() - 0.5) * 0.3,
        radius: rng.nextDouble() * 1.8 + 0.3,
        alpha: rng.nextDouble() * 0.5 + 0.1,
        pulse: rng.nextDouble() * math.pi * 2,
        pulseSpeed: rng.nextDouble() * 0.015 + 0.005,
        color: _particleColors[rng.nextInt(_particleColors.length)],
      );
    });
  }

  Size _lastSize = Size.zero;

  void _updateParticles() {
    if (!mounted) return;
    // Sem setState: mutamos as partículas em memória; o CustomPaint escuta
    // diretamente o _particleController via super.repaint e se redesenha
    // sozinho, sem reconstruir o resto da árvore.
    final w = _lastSize.width == 0 ? 400.0 : _lastSize.width;
    final h = _lastSize.height == 0 ? 700.0 : _lastSize.height;
    for (final p in _particles) {
      p.x += p.vx;
      p.y += p.vy;
      p.pulse += p.pulseSpeed;
      if (p.x < -10) p.x = w + 10;
      if (p.x > w + 10) p.x = -10;
      if (p.y < -10) p.y = h + 10;
      if (p.y > h + 10) p.y = -10;
    }
  }

  @override
  void dispose() {
    _particleController.dispose();
    _drawerController.dispose();
    _overlayController.dispose();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _openDrawer() {
    setState(() => _drawerOpen = true);
    _drawerController.forward();
    _overlayController.forward();
  }

  void _closeDrawer() {
    _drawerController.reverse().then((_) {
      if (mounted) setState(() => _drawerOpen = false);
    });
    _overlayController.reverse();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      var limiteAtingido = false;
      final novos = <_Anexo>[];

      if (source == ImageSource.gallery) {
        // Usamos o FilePicker (o mesmo dos PDFs) porque o allowMultiple dele
        // é confiável na Web; o image_picker fica reservado para a câmera.
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData:
              true, // garante os bytes em todas as plataformas (inclusive Web)
        );
        if (result == null || result.files.isEmpty) return;

        for (final arquivo in result.files) {
          if (_anexos.length + novos.length >= _maxAnexos) {
            limiteAtingido = true;
            break;
          }
          Uint8List? bytes = arquivo.bytes;
          if (bytes == null && !kIsWeb && arquivo.path != null) {
            bytes = await File(arquivo.path!).readAsBytes();
          }
          if (bytes == null) continue;
          novos.add(_Anexo(
            nome: arquivo.name,
            bytes: bytes,
            contentType: _contentTypeFromName(arquivo.name),
          ));
        }
      } else {
        // Câmera continua no image_picker (uma foto por vez).
        final unica = await _picker.pickImage(source: source);
        if (unica == null) return;
        if (_anexos.length >= _maxAnexos) {
          limiteAtingido = true;
        } else {
          final bytes = await unica.readAsBytes();
          novos.add(_Anexo(
            nome: unica.name,
            bytes: bytes,
            contentType: _contentTypeFromName(unica.name),
          ));
        }
      }

      if (novos.isNotEmpty) {
        setState(() => _anexos.addAll(novos));
      }
      if (mounted) Navigator.pop(context);
      if (limiteAtingido && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Máximo de $_maxAnexos arquivos por mensagem.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao escolher imagem: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true, // permite escolher vários PDFs de uma vez
        withData:
            true, // garante os bytes em todas as plataformas (inclusive Web)
      );
      if (result == null || result.files.isEmpty) return;

      // Fecha o modal de anexo e mostra estado de processamento.
      if (mounted) Navigator.pop(context);
      setState(() => _isProcessingPdf = true);

      var limiteAtingido = false;
      var algumFalhou = false;
      final novos = <_Anexo>[];

      for (final arquivo in result.files) {
        if (_anexos.length + novos.length >= _maxAnexos) {
          limiteAtingido = true;
          break;
        }

        // Bytes do PDF: em geral vêm em `bytes` (withData). Em mobile/desktop,
        // caímos para o caminho do arquivo se necessário.
        Uint8List? bytes = arquivo.bytes;
        if (bytes == null && !kIsWeb && arquivo.path != null) {
          bytes = await File(arquivo.path!).readAsBytes();
        }
        if (bytes == null) {
          algumFalhou = true;
          continue;
        }

        // Converte a 1ª página do PDF em imagem para a IA conseguir "ler".
        final imagemPagina = await PdfService.primeiraPaginaComoImagem(bytes);
        if (imagemPagina == null) {
          algumFalhou = true;
          continue;
        }

        final base = arquivo.name
            .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
        novos.add(_Anexo(
          nome: '$base.png',
          nomeOriginal: arquivo.name,
          bytes: imagemPagina,
          contentType: 'image/png',
          ehPdf: true,
        ));
      }

      if (!mounted) return;
      setState(() {
        _anexos.addAll(novos);
        _isProcessingPdf = false;
      });

      if (algumFalhou || limiteAtingido) {
        final avisos = <String>[
          if (algumFalhou) 'Não consegui converter um ou mais PDFs.',
          if (limiteAtingido) 'Máximo de $_maxAnexos arquivos por mensagem.',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(avisos.join(' ')),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao escolher PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showAttachmentModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: AppColors.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ANEXAR ARQUIVO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildAttachmentOption(
                        icon: Icons.image_outlined,
                        titulo: 'Imagem',
                        formatos: 'PNG, JPG (vários)',
                        onTap: () => _pickImage(ImageSource.gallery),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildAttachmentOption(
                        icon: Icons.picture_as_pdf_outlined,
                        titulo: 'PDF',
                        formatos: '.pdf (vários)',
                        onTap: _pickPdf,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'CANCELAR',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String titulo,
    required String formatos,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.cardMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder, width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: AppColors.accent),
            const SizedBox(height: 14),
            Text(
              titulo,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              formatos,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
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

  /// Remove a extensão do nome do arquivo do banco para exibição.
  /// Ex.: "Conjugada.png" -> "Conjugada". Retorna null se vazio.
  String? _nomeLimpo(String? nome) {
    if (nome == null) return null;
    final limpo = nome.trim();
    if (limpo.isEmpty) return null;
    final pontoIdx = limpo.lastIndexOf('.');
    // Só corta se houver extensão "real" (ponto não no início).
    if (pontoIdx > 0) {
      return limpo.substring(0, pontoIdx);
    }
    return limpo;
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
      _anexos.clear();
      _chatController.clear();
    });
  }

  Future<void> _abrirConversa(ConversaSalva conv) async {
    _closeDrawer();
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
      _scrollToBottom();
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
          backgroundColor: Colors.red,
        ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: const Text(
          'Renomear conversa',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'Georgia',
            fontSize: 16,
            letterSpacing: 1.5,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          cursorColor: AppColors.crimson,
          decoration: InputDecoration(
            hintText: 'Novo título',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.crimson),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'CANCELAR',
              style:
                  TextStyle(color: AppColors.textSecondary, letterSpacing: 1),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'SALVAR',
              style: TextStyle(
                color: AppColors.accent,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: const Text(
          'Excluir conversa',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'Georgia',
            fontSize: 16,
            letterSpacing: 1.5,
          ),
        ),
        content: Text(
          'Tem certeza que deseja excluir "${conv.titulo}"? '
          'Esta ação não pode ser desfeita.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'CANCELAR',
              style:
                  TextStyle(color: AppColors.textSecondary, letterSpacing: 1),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'EXCLUIR',
              style: TextStyle(
                color: Colors.redAccent,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
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
    final temAnexos = _anexos.isNotEmpty;
    final temPdf = _anexos.any((a) => a.ehPdf);
    if (text.isEmpty && !temAnexos) return;

    // ── Interceptar fluxo da calculadora de fórmulas ──────────────
    if (_calcEstado == _CalcEstado.coletandoValor && text.isNotEmpty) {
      await _processarValorCalculadora(text);
      return;
    }
    if (_calcEstado == _CalcEstado.escolhendoFormula && text.isNotEmpty) {
      await _avisoEscolhaFormula(text);
      return;
    }

    // Bytes de TODOS os anexos que irão para a IA, na ordem de seleção.
    final List<Uint8List> bytesParaIA = [];

    final ehPrimeiraMensagemDoUsuario =
        !_messages.any((m) => m.sender == 'Você');
    final tituloInicial = ehPrimeiraMensagemDoUsuario
        ? (text.isNotEmpty
            ? text
            : (_anexos.length > 1
                ? 'Arquivos enviados'
                : (temPdf ? 'PDF enviado' : 'Imagem enviada')))
        : null;

    await _garantirConversa(tituloInicial: tituloInicial);

    // Bolha de texto do usuário (se houver texto). Cada anexo aparece em
    // uma bolha própria assim que o respectivo upload termina (vira URL).
    if (text.isNotEmpty) {
      final msgTexto = ChatMessage(sender: 'Você', text: text);
      setState(() => _messages.add(msgTexto));
      _scrollToBottom();
      await _persistirMensagem(msgTexto);
    }

    setState(() => _isUploading = true);

    if (temAnexos) {
      try {
        final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonimo';
        final anexosParaEnviar = List<_Anexo>.from(_anexos);

        for (final anexo in anexosParaEnviar) {
          bytesParaIA.add(anexo.bytes);

          // Upload de cada anexo para o Firebase Storage.
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final storagePath = 'chats/$userId/${timestamp}_${anexo.nome}';

          final ref = FirebaseStorage.instance.ref(storagePath);
          final uploadTask = await ref.putData(
            anexo.bytes,
            SettableMetadata(contentType: anexo.contentType),
          );
          final url = await uploadTask.ref.getDownloadURL();

          await FirebaseFirestore.instance.collection('chats').add({
            'text': text,
            'imageUrl': url,
            'storagePath': storagePath,
            'tipo': anexo.ehPdf ? 'pdf' : 'imagem',
            'senderId': userId,
            'timestamp': FieldValue.serverTimestamp(),
          });

          // Mostra o anexo na conversa assim que o upload termina.
          final msgAnexo = ChatMessage(sender: 'Você', text: '', imageUrl: url);
          if (mounted) setState(() => _messages.add(msgAnexo));
          _scrollToBottom();
          await _persistirMensagem(msgAnexo);
        }
      } on FirebaseException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro Firebase Storage: ${e.code} — ${e.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isUploading = false);
        return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao processar anexo: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isUploading = false);
        return;
      }
    }

    setState(() {
      _anexos.clear();
      _isUploading = false;
      _isTyping = true;
      _chatController.clear();
    });
    _scrollToBottom();

    if (bytesParaIA.isNotEmpty) {
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
              _isTyping = false;
              _messages.add(msg);
            });
            _scrollToBottom();
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
                'nome': dados['nome'],
                'bytes': bytes,
              });
            } else {
              debugPrint(
                  '[banco_imagens] doc ${doc.id} sem storagePath ou bytes vazios — pulando.');
            }
          } catch (e) {
            debugPrint('[banco_imagens] Erro ao baixar imagem do banco: $e');
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
              _isTyping = false;
              _messages.add(msg);
            });
            _scrollToBottom();
            await _persistirMensagem(msg);
          }
          return;
        }

        final resultado = await IaService.analisarComContexto(
          imagensUsuario: bytesParaIA,
          imagensBanco: imagensBanco,
          textoUsuario: text.isNotEmpty
              ? text
              : (temPdf ? 'análise de documento PDF' : 'análise de imagem'),
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
            final nomeArquivo = _nomeLimpo(resultado['nome']?.toString());
            final mensagemIA = resultado['mensagem'] as String;
            final textoResposta = nomeArquivo != null
                ? '$mensagemIA\n\n📄 Arquivo correspondente: $nomeArquivo'
                : mensagemIA;
            respostaIA = ChatMessage(
              sender: 'TOT',
              text: textoResposta,
              imageUrl: resultado['imageUrl'] as String?,
            );
          }
          setState(() {
            _isTyping = false;
            _messages.add(respostaIA);
          });
          _scrollToBottom();
          await _persistirMensagem(respostaIA);
        }
      } catch (e) {
        if (mounted) {
          final msg = ChatMessage(
            sender: 'TOT',
            text: 'Erro ao analisar imagem: $e',
          );
          setState(() {
            _isTyping = false;
            _messages.add(msg);
          });
          _scrollToBottom();
          await _persistirMensagem(msg);
        }
      }
    } else if (text.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) {
        final msg = ChatMessage(
          sender: 'TOT',
          text:
              'Para ativar a busca preditiva, anexe uma imagem usando o ícone de clipe.',
        );
        setState(() {
          _isTyping = false;
          _messages.add(msg);
        });
        _scrollToBottom();
        await _persistirMensagem(msg);
      }
    } else {
      // sem texto e sem imagem — não deveria acontecer
      setState(() => _isTyping = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _fillInput(String text) {
    _chatController.text = text;
    _chatController.selection = TextSelection.fromPosition(
      TextPosition(offset: text.length),
    );
  }

  Future<void> _iniciarCalculadora() async {
    final eraPrimeiraMsg = !_messages.any((m) => m.sender == 'Você');
    if (eraPrimeiraMsg) {
      await _garantirConversa(tituloInicial: 'Cálculo de fórmula');
    }

    final msg = ChatMessage(
      sender: 'TOT',
      text:
          ' Modo Calculadora ativado.\n\nEscolha qual fórmula você quer usar tocando em uma das opções abaixo:',
    );
    setState(() {
      _calcEstado = _CalcEstado.escolhendoFormula;
      _formulaAtual = null;
      _valoresColetados.clear();
      _indiceVariavelAtual = 0;
      _messages.add(msg);
    });
    _scrollToBottom();
    await _persistirMensagem(msg);
  }

  Future<void> _cancelarCalculadora({bool comMensagem = true}) async {
    setState(() {
      _calcEstado = _CalcEstado.idle;
      _formulaAtual = null;
      _valoresColetados.clear();
      _indiceVariavelAtual = 0;
    });
    if (comMensagem) {
      final msg = ChatMessage(
        sender: 'TOT',
        text: 'Cálculo cancelado. Como posso ajudar?',
      );
      setState(() => _messages.add(msg));
      _scrollToBottom();
      await _persistirMensagem(msg);
    }
  }

  Future<void> _selecionarFormula(_CalcFormula formula) async {
    final msgUsuario = ChatMessage(
      sender: 'Você',
      text: 'Escolhi: ${formula.nome}',
    );

    final primeira = formula.variaveis.first;
    final qtd = formula.variaveis.length;
    final msgBot = ChatMessage(
      sender: 'TOT',
      text: 'Perfeito! Vou pedir $qtd ${qtd > 1 ? "valores" : "valor"}.\n\n'
          'Informe o valor de ${primeira.nome} (${primeira.descricao}).\n\n'
          'Dica: você pode digitar "cancelar" a qualquer momento para sair.',
    );

    setState(() {
      _formulaAtual = formula;
      _calcEstado = _CalcEstado.coletandoValor;
      _indiceVariavelAtual = 0;
      _valoresColetados.clear();
      _messages.add(msgUsuario);
      _messages.add(msgBot);
    });
    _scrollToBottom();
    await _persistirMensagem(msgUsuario);
    await _persistirMensagem(msgBot);
  }

  Future<void> _processarValorCalculadora(String texto) async {
    final lower = texto.toLowerCase().trim();
    final formula = _formulaAtual!;
    final variavelAtual = formula.variaveis[_indiceVariavelAtual];

    // Adicionar a mensagem do usuário primeiro
    final msgUsuario = ChatMessage(sender: 'Você', text: texto);
    setState(() {
      _messages.add(msgUsuario);
      _chatController.clear();
    });
    await _persistirMensagem(msgUsuario);

    // Cancelamento
    if (lower == 'cancelar' || lower == 'sair') {
      await _cancelarCalculadora();
      return;
    }

    // Aceita vírgula como separador decimal
    final valor = double.tryParse(texto.replaceAll(',', '.').trim());

    if (valor == null) {
      final msgErro = ChatMessage(
        sender: 'TOT',
        text: '"$texto" não é um número válido. '
            'Por favor, informe um número para ${variavelAtual.nome} '
            '(ex.: 3,5 ou 3.5). Digite "cancelar" para sair.',
      );
      setState(() => _messages.add(msgErro));
      _scrollToBottom();
      await _persistirMensagem(msgErro);
      return;
    }

    // Validação de opções restritas (ex.: M = 480/620, K = 40/60)
    final opcoesPermitidas = variavelAtual.opcoes;
    if (opcoesPermitidas != null && !opcoesPermitidas.contains(valor)) {
      final permitidos = opcoesPermitidas.map(formatarNumero).join(' ou ');
      final msgErro = ChatMessage(
        sender: 'TOT',
        text: 'Para ${variavelAtual.nome} os valores aceitos são apenas '
            '$permitidos. Por favor, digite um deles. '
            'Digite "cancelar" para sair.',
      );
      setState(() => _messages.add(msgErro));
      _scrollToBottom();
      await _persistirMensagem(msgErro);
      return;
    }

    // Validação de mínimo exclusivo (ex.: A e B precisam ser > 0,6,
    // senão a correção A − 0,6 geraria valor zero ou negativo)
    final minExclusivo = variavelAtual.minExclusivo;
    if (minExclusivo != null && valor <= minExclusivo) {
      final msgErro = ChatMessage(
        sender: 'TOT',
        text: '${variavelAtual.nome} precisa ser maior que '
            '${formatarNumero(minExclusivo)}, pois a fórmula subtrai '
            '${formatarNumero(kDescontoBorda)} desse valor. '
            'Informe um número maior ou digite "cancelar" para sair.',
      );
      setState(() => _messages.add(msgErro));
      _scrollToBottom();
      await _persistirMensagem(msgErro);
      return;
    }

    // Valor válido
    _valoresColetados[variavelAtual.nome] = valor;
    _indiceVariavelAtual++;

    if (_indiceVariavelAtual >= formula.variaveis.length) {
      await _finalizarCalculo();
    } else {
      final proxima = formula.variaveis[_indiceVariavelAtual];
      final restantes = formula.variaveis.length - _indiceVariavelAtual;
      final msgBot = ChatMessage(
        sender: 'TOT',
        text: '✓ ${variavelAtual.nome} = $valor anotado.\n\n'
            'Agora informe o valor de ${proxima.nome} '
            '(${proxima.descricao}).\n'
            'Faltam $restantes ${restantes > 1 ? "valores" : "valor"}._',
      );
      setState(() => _messages.add(msgBot));
      _scrollToBottom();
      await _persistirMensagem(msgBot);
    }
  }

  Future<void> _finalizarCalculo() async {
    final formula = _formulaAtual!;

    // Rede de segurança: as validações já acontecem na coleta, mas se a
    // fórmula lançar ArgumentError (ex.: chamada futura sem validação de
    // UI), avisamos o usuário em vez de quebrar o app.
    final double resultado;
    final String memoria;
    try {
      resultado = formula.calcular(_valoresColetados);
      memoria = formula.memoriaCalculo(_valoresColetados, resultado);
    } on ArgumentError catch (e) {
      final msgErro = ChatMessage(
        sender: 'TOT',
        text: 'Não foi possível concluir o cálculo: ${e.message}\n'
            'O modo calculadora foi encerrado — ative-o novamente para '
            'tentar com outros valores.',
      );
      setState(() {
        _calcEstado = _CalcEstado.idle;
        _formulaAtual = null;
        _valoresColetados.clear();
        _indiceVariavelAtual = 0;
        _messages.add(msgErro);
      });
      _scrollToBottom();
      await _persistirMensagem(msgErro);
      return;
    }

    final msgResultado = ChatMessage(
      sender: 'TOT',
      text: ' Cálculo concluído — ${formula.nome}\n\n'
          ' Memória de cálculo:\n$memoria\n\n'
          ' Resultado final: ${resultado.toStringAsFixed(3)}',
    );

    setState(() {
      _calcEstado = _CalcEstado.idle;
      _formulaAtual = null;
      _valoresColetados.clear();
      _indiceVariavelAtual = 0;
      _messages.add(msgResultado);
    });
    _scrollToBottom();
    await _persistirMensagem(msgResultado);
  }

  Future<void> _avisoEscolhaFormula(String texto) async {
    final msgUsuario = ChatMessage(sender: 'Você', text: texto);
    setState(() {
      _messages.add(msgUsuario);
      _chatController.clear();
    });
    await _persistirMensagem(msgUsuario);

    final lower = texto.toLowerCase().trim();
    if (lower == 'cancelar' || lower == 'sair') {
      await _cancelarCalculadora();
      return;
    }

    final msgBot = ChatMessage(
      sender: 'TOT',
      text: 'Por favor, toque em uma das fórmulas mostradas acima para '
          'escolher, ou digite "cancelar" para sair do modo calculadora.',
    );
    setState(() => _messages.add(msgBot));
    _scrollToBottom();
    await _persistirMensagem(msgBot);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _lastSize = Size(constraints.maxWidth, constraints.maxHeight);
      return _buildScaffold(context);
    });
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // Fundo com partículas
          _buildParticleBackground(),

          // Conteúdo principal
          Column(
            children: [
              _buildAppBar(),
              Expanded(child: _buildMessages()),
              if (_calcEstado == _CalcEstado.escolhendoFormula)
                _buildFormulaSelector()
              else if (_calcEstado == _CalcEstado.coletandoValor)
                _buildCalcStatusBar()
              else
                _buildSuggestions(),
              if (_isProcessingPdf)
                _buildPdfProcessing()
              else if (_anexos.isNotEmpty)
                _buildAnexosPreview(),
              _buildInputArea(),
            ],
          ),

          // Overlay do drawer
          if (_drawerOpen)
            FadeTransition(
              opacity: _overlayController,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _closeDrawer,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),

          // Drawer
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: _drawerController,
              curve: Curves.easeOutCubic,
            )),
            child: _buildDrawer(),
          ),
        ],
      ),
    );
  }

  //  Partículas
  Widget _buildParticleBackground() {
    return Positioned.fill(
      child: CustomPaint(
        painter: _ParticlePainter(_particles, _particleController),
      ),
    );
  }

  // AppBar
  Widget _buildAppBar() {
    return Container(
      height: 64 + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.surface],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Stack(
        children: [
          // linha de luz inferior
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    AppColors.glow.withValues(alpha: 0.6),
                    AppColors.crimson.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _AppBarButton(
                  onTap: _openDrawer,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                          width: 16, height: 1.5, color: AppColors.textPrimary),
                      const SizedBox(height: 5),
                      Container(
                          width: 12, height: 1.5, color: AppColors.textPrimary),
                      const SizedBox(height: 5),
                      Container(
                          width: 16, height: 1.5, color: AppColors.textPrimary),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 5,
                        color: AppColors.textPrimary,
                      ),
                      children: [
                        TextSpan(text: 'T'),
                        TextSpan(
                          text: 'O',
                          style: TextStyle(color: AppColors.accent),
                        ),
                        TextSpan(text: 'T  ·  CHAT'),
                      ],
                    ),
                  ),
                ),
                // dot online
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _AppBarAvatar(
                  onTap: () => Navigator.pushNamed(context, '/profile'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Mensagens
  Widget _buildMessages() {
    if (_isCarregandoConversa) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.accent,
          strokeWidth: 1.6,
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isTyping && index == _messages.length) {
          return const _TypingBubble(key: ValueKey('typing'));
        }
        final msg = _messages[index];
        final isUser = msg.sender == 'Você';
        return _MessageRow(
          key: ValueKey('msg_$index'),
          message: msg,
          isUser: isUser,
        );
      },
    );
  }

  // Sugestões
  Widget _buildSuggestions() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          return _SuggestionChip(
            label: _suggestions[i],
            onTap: () => _fillInput(_suggestions[i]),
          );
        },
      ),
    );
  }

  // Seletor de fórmula (cards)
  Widget _buildFormulaSelector() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 12,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.accent, AppColors.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'ESCOLHA A FÓRMULA',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _cancelarCalculadora(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Text(
                        'CANCELAR',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppColors.textSecondary.withValues(alpha: 0.8),
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ..._formulasDisponiveis
              .map((f) => _FormulaCard(
                    formula: f,
                    onTap: () => _selecionarFormula(f),
                  ))
              .toList(),
        ],
      ),
    );
  }

  // Barra de status durante coleta de valores
  Widget _buildCalcStatusBar() {
    final formula = _formulaAtual;
    if (formula == null) return const SizedBox.shrink();
    final atual = formula.variaveis[_indiceVariavelAtual];
    final total = formula.variaveis.length;
    final progress = (_indiceVariavelAtual + 1) / total;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.calculate_outlined,
              size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${formula.nome.toUpperCase()}  ·  ${_indiceVariavelAtual + 1}/$total  ·  AGUARDANDO ${atual.nome}',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: AppColors.cardMid,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.crimson),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _cancelarCalculadora(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Text(
                  'CANCELAR',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Preview dos anexos (suporta vários) ───
  Widget _buildAnexosPreview() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardDark.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _anexos.length == 1
                ? '1 arquivo pronto para enviar'
                : '${_anexos.length} arquivos prontos para enviar',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _anexos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _buildAnexoChip(i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnexoChip(int indice) {
    final anexo = _anexos[indice];
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.crimson],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(anexo.bytes, fit: BoxFit.cover),
                ),
              ),
              if (anexo.ehPdf)
                const Positioned(
                  left: 3,
                  bottom: 3,
                  child: Icon(Icons.picture_as_pdf,
                      size: 14, color: AppColors.accent),
                ),
              // Botão para remover este anexo individualmente.
              Positioned(
                top: 2,
                right: 2,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _anexos.removeAt(indice)),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.cardDark.withValues(alpha: 0.85),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: const Icon(Icons.close,
                          size: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            anexo.nomeOriginal,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ── Indicador: convertendo PDF ────────────
  Widget _buildPdfProcessing() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardDark.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: const [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Convertendo PDF...',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input ─────────────────────────────────
  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardDark.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                // linha de luz topo
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.crimson.withValues(alpha: 0.3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w300,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Digite sua dúvida ou anexe uma imagem...',
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.5),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                          cursorColor: AppColors.crimson,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // botão clipe — abre o modal de anexo (preservado do TOT 16)
                      _InputActionButton(
                        onTap: _isUploading ? null : _showAttachmentModal,
                        child: _isUploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppColors.accent,
                                ),
                              )
                            : const Icon(
                                Icons.attach_file,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                      ),
                      const SizedBox(width: 6),
                      // botão enviar
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _sendMessage,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.primaryLight,
                                  AppColors.crimson,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.crimson.withValues(alpha: 0.4),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.send_rounded,
                                size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'TOT  ·  Assistente Preditivo Premium',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Drawer ───────────────────────────────
  Widget _buildDrawer() {
    return SizedBox(
      width: 300,
      height: double.infinity,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.cardDark,
                  AppColors.surface.withValues(alpha: 0.97),
                  AppColors.bg,
                ],
              ),
              border: const Border(
                right: BorderSide(color: AppColors.cardBorder, width: 1),
              ),
            ),
          ),
          // linha de luz direita
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: Container(
              width: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.crimson.withValues(alpha: 0.4),
                    AppColors.accent.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 24),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _DrawerAvatar(),
                    const SizedBox(height: 12),
                    Text(
                      FirebaseAuth.instance.currentUser?.displayName ??
                          'Usuário',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    Text(
                      FirebaseAuth.instance.currentUser?.email ?? '',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 6,
                          color: AppColors.textPrimary,
                        ),
                        children: [
                          TextSpan(text: 'T'),
                          TextSpan(
                            text: 'O',
                            style: TextStyle(color: AppColors.accent),
                          ),
                          TextSpan(text: 'T'),
                        ],
                      ),
                    ),
                    Text(
                      'ASSISTENTE PREDITIVO',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(
                color: AppColors.cardBorder,
                height: 1,
                indent: 24,
                endIndent: 24,
              ),
              const SizedBox(height: 8),
              // Novo chat
              _DrawerItem(
                icon: Icons.add_comment_outlined,
                label: 'Novo Chat',
                isActive: _currentChatId == null,
                onTap: () {
                  _iniciarNovoChat();
                  _closeDrawer();
                },
              ),
              const Divider(
                color: AppColors.cardBorder,
                height: 16,
                indent: 24,
                endIndent: 24,
              ),
              // Cabeçalho "Conversas salvas"
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.accent, AppColors.primaryDark],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Text(
                      'CONVERSAS SALVAS',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary.withValues(alpha: 0.7),
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              // Lista de conversas (preserva ChatStorage do TOT 16)
              Expanded(
                child: ChatStorage.usuarioLogado
                    ? _buildListaConversas()
                    : _buildAvisoSemLogin(),
              ),
              const Divider(
                color: AppColors.cardBorder,
                height: 1,
                indent: 24,
                endIndent: 24,
              ),
              // Itens de navegação inferiores
              _DrawerItem(
                icon: Icons.calculate_outlined,
                label: 'Calcular Fórmula',
                onTap: () {
                  _closeDrawer();
                  _iniciarCalculadora();
                },
              ),
              _DrawerItem(
                icon: Icons.photo_library_outlined,
                label: 'Banco de Imagens',
                onTap: () {
                  _closeDrawer();
                  Navigator.pushNamed(context, '/admin_banco');
                },
              ),
              _DrawerItem(
                icon: Icons.help_outline_rounded,
                label: 'FAQ',
                onTap: () {
                  _closeDrawer();
                  Navigator.pushNamed(context, '/faq');
                },
              ),
              const Divider(
                color: AppColors.cardBorder,
                height: 1,
                indent: 24,
                endIndent: 24,
              ),
              // Toggle modo escuro
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Row(
                  children: [
                    Text(
                      'MODO ESCURO',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    _ToggleSwitch(
                      value: _isDark,
                      onChanged: (val) {
                        themeNotifier.value =
                            val ? ThemeMode.dark : ThemeMode.light;
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvisoSemLogin() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Text(
        'Faça login para salvar suas conversas e acessá-las depois.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }

  Widget _buildListaConversas() {
    return StreamBuilder<List<ConversaSalva>>(
      stream: _conversasStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                color: AppColors.accent,
                strokeWidth: 1.4,
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Erro ao carregar conversas: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          );
        }

        final conversas = snapshot.data ?? [];
        if (conversas.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              'Nenhuma conversa salva ainda. Comece a conversar e ela aparecerá aqui.',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: conversas.length,
          itemBuilder: (context, i) => _buildItemConversa(conversas[i]),
        );
      },
    );
  }

  Widget _buildItemConversa(ConversaSalva c) {
    final selecionado = c.id == _currentChatId;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: selecionado
            ? AppColors.crimson.withValues(alpha: 0.12)
            : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: selecionado ? AppColors.crimson : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(
          c.fixado ? Icons.push_pin : Icons.chat_bubble_outline_rounded,
          color: c.fixado ? AppColors.accent : AppColors.textSecondary,
          size: 18,
        ),
        title: Text(
          c.titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                selecionado ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: selecionado ? FontWeight.w500 : FontWeight.w300,
            fontSize: 13,
          ),
        ),
        subtitle: c.previa.isEmpty
            ? null
            : Text(
                c.previa,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
        onTap: () => _abrirConversa(c),
        trailing: PopupMenuButton<String>(
          icon: const Icon(
            Icons.more_vert,
            color: AppColors.textSecondary,
            size: 18,
          ),
          color: AppColors.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.cardBorder),
          ),
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
                      color: AppColors.textPrimary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    c.fixado ? 'Desafixar' : 'Fixar',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'renomear',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined,
                      color: AppColors.textPrimary, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Renomear',
                    style:
                        TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'excluir',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Excluir',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13),
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

class _MessageRow extends StatelessWidget {
  final ChatMessage message;
  final bool isUser;

  const _MessageRow({
    super.key,
    required this.message,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: isUser
              ? [_bubble(context), const SizedBox(width: 8), _avatar()]
              : [_avatar(), const SizedBox(width: 8), _bubble(context)],
        ),
      ),
    );
  }

  Widget _avatar() {
    final user = FirebaseAuth.instance.currentUser;
    final photoURL = user?.photoURL;
    final displayName = user?.displayName;
    final initial = (displayName != null && displayName.isNotEmpty)
        ? displayName.substring(0, 1).toUpperCase()
        : 'U';
    final hasPhoto = isUser && photoURL != null && photoURL.isNotEmpty;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto
            ? null
            : LinearGradient(
                colors: isUser
                    ? [const Color(0xFF1E3A5F), const Color(0xFF2563EB)]
                    : [AppColors.primaryDark, AppColors.crimson],
              ),
        border: Border.all(
          color: isUser
              ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
              : AppColors.accent.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isUser ? const Color(0xFF3B82F6) : AppColors.crimson)
                .withValues(alpha: 0.25),
            blurRadius: 10,
          ),
        ],
      ),
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                photoURL,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF93C5FD),
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  isUser ? initial : 'T',
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isUser
                        ? const Color(0xFF93C5FD)
                        : AppColors.accent.withValues(alpha: 0.9),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.crimson.withValues(alpha: 0.18)
            : AppColors.cardDark.withValues(alpha: 0.88),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        border: Border.all(
          color: isUser
              ? AppColors.crimson.withValues(alpha: 0.35)
              : AppColors.cardBorder.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: (isUser ? AppColors.crimson : Colors.black)
                .withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.sender.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: isUser
                  ? AppColors.glow.withValues(alpha: 0.8)
                  : AppColors.accent.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          if (message.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: (kIsWeb || (message.imageUrl?.startsWith('http') ?? false))
                  ? Image.network(
                      message.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Text(
                          '[Erro ao carregar imagem]',
                          style: TextStyle(color: Colors.red)),
                    )
                  : Image.file(
                      File(message.imageUrl!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Text(
                          '[Erro ao carregar imagem]',
                          style: TextStyle(color: Colors.red)),
                    ),
            ),
            const SizedBox(height: 8),
          ],
          if (message.text.isNotEmpty)
            SelectableText(
              message.text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w300,
                height: 1.6,
              ),
            ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble({super.key});

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.primaryDark, AppColors.crimson],
              ),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: const Center(
              child: Text(
                'T',
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.cardDark.withValues(alpha: 0.88),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(
                  color: AppColors.cardBorder.withValues(alpha: 0.7)),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i * 0.15;
                    final t = (_ctrl.value - delay).clamp(0.0, 1.0);
                    final y = -6.0 * math.sin(t * math.pi).clamp(0.0, 1.0);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      child: Transform.translate(
                        offset: Offset(0, y),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.crimson
                                .withValues(alpha: 0.6 + 0.4 * (1 - t)),
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  State<_SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<_SuggestionChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _hovered
                    ? AppColors.crimson.withValues(alpha: 0.6)
                    : AppColors.cardBorder,
              ),
              color: _hovered
                  ? AppColors.crimson.withValues(alpha: 0.08)
                  : AppColors.cardDark.withValues(alpha: 0.6),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                color: _hovered ? AppColors.accent : AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormulaCard extends StatefulWidget {
  final _CalcFormula formula;
  final VoidCallback onTap;

  const _FormulaCard({required this.formula, required this.onTap});

  @override
  State<_FormulaCard> createState() => _FormulaCardState();
}

class _FormulaCardState extends State<_FormulaCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: _pressed
                  ? [
                      AppColors.crimson.withValues(alpha: 0.20),
                      AppColors.cardDark.withValues(alpha: 0.9),
                    ]
                  : [
                      AppColors.cardDark.withValues(alpha: 0.9),
                      AppColors.cardMid.withValues(alpha: 0.6),
                    ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _pressed
                  ? AppColors.crimson.withValues(alpha: 0.6)
                  : AppColors.cardBorder,
              width: 1.2,
            ),
            boxShadow: _pressed
                ? [
                    BoxShadow(
                      color: AppColors.crimson.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.crimson],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: const Icon(
                  Icons.functions_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.formula.nome.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Georgia',
                        color: AppColors.accentGlow,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.formula.descricao,
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w300,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.formula.variaveis.length} ${widget.formula.variaveis.length > 1 ? "variáveis" : "variável"}: '
                      '${widget.formula.variaveis.map((v) => v.nome).join(", ")}',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary.withValues(alpha: 0.6),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Avatar da AppBar (carrega foto do Firestore) ──────────────────────────────
class _AppBarAvatar extends StatefulWidget {
  final VoidCallback onTap;
  const _AppBarAvatar({required this.onTap});

  @override
  State<_AppBarAvatar> createState() => _AppBarAvatarState();
}

class _AppBarAvatarState extends State<_AppBarAvatar> {
  String? _photoURL;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      final url = doc.data()?['photoURL'] as String?;
      if (mounted) setState(() => _photoURL = url ?? user.photoURL);
    } catch (_) {
      if (mounted) setState(() => _photoURL = user.photoURL);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? '';
    final initial = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : 'U';
    final hasPhoto = _photoURL != null && _photoURL!.isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: hasPhoto
                ? null
                : const LinearGradient(
                    colors: [AppColors.wine, AppColors.crimson],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            border: Border.all(color: AppColors.cardBorder),
            color: hasPhoto ? null : null,
          ),
          child: ClipOval(
            child: hasPhoto
                ? Image.network(
                    _photoURL!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontFamily: 'Georgia',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _AppBarButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _AppBarButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
            color: AppColors.crimson.withValues(alpha: 0.08),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _InputActionButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _InputActionButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  State<_DrawerItem> createState() => _DrawerItemState();
}

class _DrawerItemState extends State<_DrawerItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: widget.isActive || _pressed
                ? AppColors.crimson.withValues(alpha: 0.1)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: widget.isActive ? AppColors.crimson : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.isActive
                    ? AppColors.accent
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 14),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.isActive
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight:
                      widget.isActive ? FontWeight.w400 : FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerAvatar extends StatefulWidget {
  const _DrawerAvatar();

  @override
  State<_DrawerAvatar> createState() => _DrawerAvatarState();
}

class _DrawerAvatarState extends State<_DrawerAvatar> {
  String? _photoURL;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      final url = doc.data()?['photoURL'] as String?;
      if (mounted) setState(() => _photoURL = url ?? user.photoURL);
    } catch (_) {
      if (mounted) setState(() => _photoURL = user.photoURL);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName;
    final initials = (displayName != null && displayName.isNotEmpty)
        ? displayName.substring(0, 1).toUpperCase()
        : 'U';

    final hasPhoto = _photoURL != null && _photoURL!.isNotEmpty;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasPhoto
            ? null
            : const LinearGradient(
                colors: [AppColors.wine, AppColors.crimson],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.crimson.withValues(alpha: 0.3),
            blurRadius: 16,
          ),
        ],
      ),
      child: ClipOval(
        child: hasPhoto
            ? Image.network(
                _photoURL!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
      ),
    );
  }
}

class _ToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 44,
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: value
                ? const LinearGradient(
                    colors: [AppColors.wine, AppColors.crimson],
                  )
                : null,
            color: value ? null : AppColors.cardMid,
            border: Border.all(
              color: value
                  ? AppColors.crimson.withValues(alpha: 0.6)
                  : AppColors.cardBorder,
            ),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: value ? 22 : 3,
                top: 3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? AppColors.accent : AppColors.textMuted,
                    boxShadow: value
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Representa um anexo pronto para envio: uma imagem escolhida pelo usuário
/// ou a 1ª página de um PDF já renderizada como PNG.
class _Anexo {
  /// Nome do arquivo usado no upload para o Storage (PDF vira "nome.png").
  final String nome;

  /// Nome original mostrado ao usuário (ex.: "manual.pdf").
  final String nomeOriginal;

  /// Bytes que vão para a IA e para o Firebase Storage.
  final Uint8List bytes;

  final String contentType;
  final bool ehPdf;

  _Anexo({
    required this.nome,
    required this.bytes,
    required this.contentType,
    this.ehPdf = false,
    String? nomeOriginal,
  }) : nomeOriginal = nomeOriginal ?? nome;
}
