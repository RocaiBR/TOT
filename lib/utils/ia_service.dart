import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class IaService {
  static const String _groqKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );

  static const String _apiUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  // Modelo multimodal do Groq (visão + texto). ATENÇÃO: é um modelo de
  // raciocínio — por padrão ele "pensa" antes de responder e o pensamento vem
  // dentro de <think>...</think> no meio do conteúdo, o que quebra o JSON mode.
  // Por isso mandamos reasoning_effort: none (ver _montarBody).
  static const String _model = 'qwen/qwen3.6-27b';

  // TETO DE IMAGENS POR REQUISIÇÃO.
  // A doc do Groq fala em 5, mas o modelo em preview recusa acima de 3.
  // O valor se ajusta sozinho se a API reclamar (ver _extrairLimiteDoErro).
  static int _limiteImagens = 3;

  // Desligados em tempo de execução caso a API rejeite os parâmetros.
  static bool _usarParametrosDeRaciocinio = true;
  static bool _usarJsonMode = true;

  // Nota mínima (0-10) para aceitar uma correspondência como válida.
  static const int _notaMinima = 5;

  // Nota a partir da qual paramos de procurar (achou bom o bastante).
  static const int _notaExcelente = 9;

  static int get limiteImagens => _limiteImagens;

  /// Compara a(s) imagem(ns) do usuário com TODAS as imagens do banco.
  ///
  /// Como o modelo aceita poucas imagens por requisição, o banco é dividido em
  /// lotes: cada requisição leva as imagens do usuário + algumas do banco, e no
  /// fim ficamos com a de maior nota entre todos os lotes.
  ///
  /// [onProgresso] é opcional e serve para a UI mostrar "Comparando 2 de 7...".
  static Future<Map<String, dynamic>?> analisarComContexto({
    required List<Uint8List> imagensUsuario,
    required List<Map<String, dynamic>> imagensBanco,
    required String textoUsuario,
    void Function(int loteAtual, int totalLotes)? onProgresso,
  }) async {
    if (_groqKey.isEmpty) {
      print('[IaService] GROQ_API_KEY não configurada!');
      return {
        'erro':
            'Chave da API não configurada. Rode com --dart-define=GROQ_API_KEY=sua_chave'
      };
    }

    if (imagensUsuario.isEmpty) {
      return {'erro': 'Nenhuma imagem do usuário para analisar.'};
    }

    final banco = imagensBanco
        .where((e) => ((e['imageUrl'] as String?) ?? '').isNotEmpty)
        .toList();

    if (banco.isEmpty) {
      return {
        'erro':
            'Banco de imagens vazio. Adicione imagens de referência primeiro.'
      };
    }

    for (int replanejamentos = 0; replanejamentos < 3; replanejamentos++) {
      final maxUsuario = max(1, _limiteImagens - 1);
      final usuario = imagensUsuario.length > maxUsuario
          ? imagensUsuario.sublist(0, maxUsuario)
          : imagensUsuario;

      final vagasBanco = max(1, _limiteImagens - usuario.length);

      final lotes = <List<Map<String, dynamic>>>[];
      for (int i = 0; i < banco.length; i += vagasBanco) {
        lotes.add(banco.sublist(i, min(i + vagasBanco, banco.length)));
      }

      print(
          '[IaService] ${usuario.length} imagem(ns) do usuário + ${banco.length} do banco '
          '→ ${lotes.length} requisição(ões) de $vagasBanco imagem(ns) cada '
          '(teto atual: $_limiteImagens).');

      Map<String, dynamic>? melhorItem;
      int melhorNota = -1;
      String melhorMensagem = '';
      String? ultimoErro;
      int falhas = 0;
      bool replanejar = false;

      for (int l = 0; l < lotes.length; l++) {
        onProgresso?.call(l + 1, lotes.length);

        final r = await _compararLote(
          usuario: usuario,
          lote: lotes[l],
          textoUsuario: textoUsuario,
          loteAtual: l + 1,
          totalLotes: lotes.length,
        );

        if (r.replanejar) {
          replanejar = true;
          break;
        }

        if (r.erro != null) {
          falhas++;
          ultimoErro = r.erro;
          continue; // um lote com problema não derruba a busca inteira
        }

        if (r.indice >= 1 && r.indice <= lotes[l].length) {
          if (r.nota > melhorNota) {
            melhorNota = r.nota;
            melhorItem = lotes[l][r.indice - 1];
            melhorMensagem = r.mensagem;
          }
        }

        if (melhorNota >= _notaExcelente) {
          print('[IaService] Correspondência forte encontrada — parando aqui.');
          break;
        }
      }

      if (replanejar) continue;

      if (melhorItem == null && falhas == lotes.length) {
        return {'erro': ultimoErro ?? 'Não foi possível consultar o Groq.'};
      }

      if (melhorItem != null && melhorNota >= _notaMinima) {
        return {
          'imageUrl': melhorItem['imageUrl'] as String,
          'nome': melhorItem['nome'],
          'mensagem': melhorMensagem.isNotEmpty
              ? melhorMensagem
              : 'Encontrei uma correspondência no banco.',
        };
      }

      return {
        'imageUrl': null,
        'nome': null,
        'mensagem': 'Não encontrei correspondência no banco para este pedido.',
      };
    }

    return {
      'erro':
          'Não consegui ajustar a quantidade de imagens aceita pelo modelo. Tente com menos anexos.'
    };
  }

  /// Faz UMA requisição: imagens do usuário + um lote do banco.
  /// Tenta até 3 vezes, degradando os parâmetros conforme a API reclama.
  static Future<_ResultadoLote> _compararLote({
    required List<Uint8List> usuario,
    required List<Map<String, dynamic>> lote,
    required String textoUsuario,
    required int loteAtual,
    required int totalLotes,
  }) async {
    final content = _montarConteudo(
      usuario: usuario,
      lote: lote,
      textoUsuario: textoUsuario,
    );

    for (int tentativa = 1; tentativa <= 3; tentativa++) {
      try {
        final requestBody = _montarBody(content);

        print(
            '[IaService] Lote $loteAtual/$totalLotes (tentativa $tentativa) — '
            '${usuario.length + lote.length} imagens, '
            '${(requestBody.length / 1024).toStringAsFixed(1)} KB, '
            'jsonMode: $_usarJsonMode');

        final response = await http
            .post(
              Uri.parse(_apiUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_groqKey',
              },
              body: requestBody,
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          final choices = decoded['choices'] as List?;
          if (choices == null || choices.isEmpty) {
            return _ResultadoLote.falha('Groq não retornou choices.');
          }

          final motivo = choices[0]['finish_reason'] as String?;
          final bruto = (choices[0]['message']['content'] as String?) ?? '';
          final json = _extrairJson(bruto);

          if (json != null) return _ResultadoLote.deJson(json);

          if (motivo == 'length') {
            return _ResultadoLote.falha(
                'A resposta foi cortada pelo limite de tokens.');
          }

          print('[IaService] Resposta sem JSON válido: $bruto');
          return _ResultadoLote.falha('O modelo não devolveu um JSON válido.');
        }

        // ---- Erro HTTP -------------------------------------------------
        Map<String, dynamic>? corpoErro;
        try {
          corpoErro = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}

        final erro = corpoErro?['error'] as Map<String, dynamic>?;
        final codigo = (erro?['code'] ?? '').toString();
        final mensagemErro =
            (erro?['message'] ?? 'HTTP ${response.statusCode}').toString();

        // 1) Estourou o número de imagens → replaneja os lotes lá em cima.
        final novoLimite = _extrairLimiteDoErro(mensagemErro);
        if (novoLimite != null && novoLimite != _limiteImagens) {
          print(
              '[IaService] A API aceita no máx. $novoLimite imagens — ajustando o teto.');
          _limiteImagens = novoLimite;
          return _ResultadoLote.replanejamento();
        }

        final textoErro = mensagemErro.toLowerCase();

        // 2) Parâmetro de raciocínio não aceito → desliga e tenta de novo.
        if (_usarParametrosDeRaciocinio &&
            (textoErro.contains('reasoning_effort') ||
                textoErro.contains('reasoning_format'))) {
          print(
              '[IaService] Parâmetros de raciocínio rejeitados — repetindo sem eles.');
          _usarParametrosDeRaciocinio = false;
          continue;
        }

        // 3) json_validate_failed: o modelo respondeu, mas o Groq não validou.
        //    A resposta crua vem em failed_generation — dá para aproveitar.
        if (codigo == 'json_validate_failed' ||
            textoErro.contains('failed to validate json')) {
          final cru = _textoDoFailedGeneration(erro?['failed_generation']);
          final salvo = cru == null ? null : _extrairJson(cru);
          if (salvo != null) {
            print('[IaService] JSON recuperado do failed_generation.');
            return _ResultadoLote.deJson(salvo);
          }

          if (_usarJsonMode) {
            print(
                '[IaService] JSON mode falhou — repetindo em texto puro e extraindo o JSON aqui.');
            _usarJsonMode = false;
            continue;
          }
        }

        print('[IaService] Erro: $mensagemErro');
        return _ResultadoLote.falha('Erro Groq: $mensagemErro');
      } catch (e) {
        print('[IaService] Exceção: $e');
        return _ResultadoLote.falha('Exceção: $e');
      }
    }

    return _ResultadoLote.falha(
        'Não consegui uma resposta em formato utilizável do modelo.');
  }

  static List<Map<String, dynamic>> _montarConteudo({
    required List<Uint8List> usuario,
    required List<Map<String, dynamic>> lote,
    required String textoUsuario,
  }) {
    final content = <Map<String, dynamic>>[];

    content.add({
      'type': 'text',
      'text': '''
O usuário enviou ${usuario.length} imagem(ns) com o seguinte contexto: "$textoUsuario".

As PRIMEIRAS ${usuario.length} imagens abaixo são do usuário.
As imagens seguintes são do banco de referência, numeradas de 1 a ${lote.length}.
Compare visualmente a(s) imagem(ns) do usuário com cada imagem do banco e diga qual delas é a mais parecida, dando uma nota de similaridade.

Responda SOMENTE com um objeto JSON, sem explicação antes ou depois, sem blocos de código e sem raciocínio visível. Formato exato:
{"indice": <1 a ${lote.length}, ou 0 se nenhuma servir>, "nota": <0 a 10>, "mensagem": "<frase curta confirmando a sugestão>"}

Seja rigoroso com a nota: 0 a 4 quando a semelhança for genérica ou duvidosa, 8 a 10 apenas quando for claramente o mesmo equipamento/desenho.
A chave "mensagem" deve ter no máximo 20 palavras e nenhuma quebra de linha.
'''
    });

    for (int i = 0; i < usuario.length; i++) {
      content.add({'type': 'text', 'text': 'Imagem do usuário ${i + 1}:'});
      content.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:image/jpeg;base64,${base64Encode(usuario[i])}',
        }
      });
    }

    for (int i = 0; i < lote.length; i++) {
      content.add({'type': 'text', 'text': 'Imagem do banco ${i + 1}:'});
      content.add({
        'type': 'image_url',
        'image_url': {'url': lote[i]['imageUrl'] as String},
      });
    }

    return content;
  }

  static String _montarBody(List<Map<String, dynamic>> content) {
    final body = <String, dynamic>{
      'model': _model,
      'messages': [
        {'role': 'user', 'content': content}
      ],
      // A doc do Qwen 3.6 recomenda 0.5-0.7; valores muito baixos aumentam a
      // chance de saída repetida/incoerente (e portanto de JSON quebrado).
      'temperature': 0.5,
      'max_completion_tokens': 512,
    };

    if (_usarParametrosDeRaciocinio) {
      // CAUSA RAIZ do "Failed to validate JSON": sem isso o modelo gasta o
      // orçamento de tokens pensando e mistura <think>...</think> com o JSON.
      body['reasoning_effort'] = 'none';
      body['reasoning_format'] = 'hidden';
    }

    if (_usarJsonMode) {
      body['response_format'] = {'type': 'json_object'};
    }

    return jsonEncode(body);
  }

  /// Extrai o JSON de uma resposta que pode vir com <think>, cercas de código
  /// ou texto solto em volta.
  static Map<String, dynamic>? _extrairJson(String bruto) {
    var texto = bruto.trim();
    if (texto.isEmpty) return null;

    // Remove blocos de raciocínio fechados e tudo que vier antes do último
    // fechamento de </think>.
    texto = texto.replaceAll(
        RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '');
    final fimThink = texto.toLowerCase().lastIndexOf('</think>');
    if (fimThink >= 0) texto = texto.substring(fimThink + 8);

    // Remove cercas de código.
    texto = texto.replaceAll(RegExp(r'```(json)?', caseSensitive: false), '');

    final recorte = _recortarObjeto(texto.trim());
    if (recorte == null) return null;

    try {
      final decodificado = jsonDecode(recorte);
      return decodificado is Map<String, dynamic> ? decodificado : null;
    } catch (_) {
      return null;
    }
  }

  /// Pega o primeiro objeto `{...}` balanceado do texto.
  static String? _recortarObjeto(String texto) {
    final inicio = texto.indexOf('{');
    if (inicio < 0) return null;

    int profundidade = 0;
    bool dentroDeString = false;
    bool escapado = false;

    for (int i = inicio; i < texto.length; i++) {
      final c = texto[i];

      if (dentroDeString) {
        if (escapado) {
          escapado = false;
        } else if (c == '\\') {
          escapado = true;
        } else if (c == '"') {
          dentroDeString = false;
        }
        continue;
      }

      if (c == '"') {
        dentroDeString = true;
      } else if (c == '{') {
        profundidade++;
      } else if (c == '}') {
        profundidade--;
        if (profundidade == 0) return texto.substring(inicio, i + 1);
      }
    }

    return null; // JSON truncado
  }

  /// failed_generation pode vir como String ou como objeto já decodificado.
  static String? _textoDoFailedGeneration(dynamic valor) {
    if (valor == null) return null;
    if (valor is String) return valor;
    try {
      return jsonEncode(valor);
    } catch (_) {
      return valor.toString();
    }
  }

  /// Lê "This model supports up to 3 images" e devolve 3.
  static int? _extrairLimiteDoErro(String mensagem) {
    final texto = mensagem.toLowerCase();
    if (!texto.contains('image')) return null;
    final m = RegExp(r'up to (\d+)\s*image').firstMatch(texto);
    if (m != null) return int.tryParse(m.group(1)!);
    if (texto.contains('too many images')) {
      return max(2, _limiteImagens - 1);
    }
    return null;
  }
}

class _ResultadoLote {
  final int indice;
  final int nota;
  final String mensagem;
  final String? erro;
  final bool replanejar;

  const _ResultadoLote({
    required this.indice,
    required this.nota,
    required this.mensagem,
    this.erro,
    this.replanejar = false,
  });

  factory _ResultadoLote.deJson(Map<String, dynamic> json) => _ResultadoLote(
        indice: (json['indice'] as num?)?.toInt() ?? 0,
        nota: (json['nota'] as num?)?.toInt() ?? 0,
        mensagem: (json['mensagem'] as String?) ?? '',
      );

  factory _ResultadoLote.falha(String erro) =>
      _ResultadoLote(indice: 0, nota: 0, mensagem: '', erro: erro);

  factory _ResultadoLote.replanejamento() =>
      const _ResultadoLote(indice: 0, nota: 0, mensagem: '', replanejar: true);
}
