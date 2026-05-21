import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class IaService {
  static const String _groqKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );

  static const String _apiUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  // Modelo multimodal do Groq (visão + texto)
  static const String _model = 'meta-llama/llama-4-scout-17b-16e-instruct';

  static Future<Map<String, dynamic>?> analisarComContexto({
    required Uint8List imagemUsuario,
    required List<Map<String, dynamic>> imagensBanco,
    required String textoUsuario,
  }) async {
    if (_groqKey.isEmpty) {
      print('[IaService] GROQ_API_KEY não configurada!');
      return {
        'erro':
            'Chave da API não configurada. Rode com --dart-define=GROQ_API_KEY=sua_chave'
      };
    }

    if (imagensBanco.isEmpty) {
      return {
        'erro':
            'Banco de imagens vazio. Adicione imagens de referência primeiro.'
      };
    }

    try {
      // 1)Limita a 3 imagens do banco
      final bancoParcial =
          imagensBanco.length > 3 ? imagensBanco.sublist(0, 3) : imagensBanco;

      final content = <Map<String, dynamic>>[];

      content.add({
        'type': 'text',
        'text': '''
O usuário enviou uma imagem com o seguinte contexto: "$textoUsuario".

A PRIMEIRA imagem abaixo é a do usuário.
As imagens seguintes são do banco, numeradas de 1 a ${bancoParcial.length}.
Compare visualmente a imagem do usuário com cada imagem do banco e decida qual é a mais similar.

Responda APENAS com um JSON neste formato exato:
{
  "indice": <número da imagem do banco mais similar, 1 a ${bancoParcial.length}>,
  "mensagem": "<frase curta confirmando a sugestão>"
}

Se nenhuma imagem for suficientemente similar, retorne:
{
  "indice": 0,
  "mensagem": "Não encontrei correspondência no banco para este pedido."
}
'''
      });

      // 2) Imagem do usuário (Uint8List → data URL base64)
      final usuarioBase64 = base64Encode(imagemUsuario);
      content.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:image/jpeg;base64,$usuarioBase64',
        }
      });

      // 3) Imagens do banco — manda direto a URL do Firebase Storage
      for (int i = 0; i < bancoParcial.length; i++) {
        final url = bancoParcial[i]['imageUrl'] as String?;
        if (url == null) continue;

        content.add({
          'type': 'text',
          'text': 'Imagem do banco ${i + 1}:',
        });
        content.add({
          'type': 'image_url',
          'image_url': {'url': url},
        });
      }

      final requestBody = jsonEncode({
        'model': _model,
        'messages': [
          {
            'role': 'user',
            'content': content,
          }
        ],
        'temperature': 0.2,
        'max_completion_tokens': 300,
        'response_format': {'type': 'json_object'},
      });

      print(
          '[IaService] Enviando para o Groq com ${bancoParcial.length} imagem(ns)...');
      print(
          '[IaService] Payload: ${(requestBody.length / 1024).toStringAsFixed(1)} KB');
      print(
          '[IaService] Chave usada: ${_groqKey.substring(0, 8)}...${_groqKey.substring(_groqKey.length - 4)} (total: ${_groqKey.length} chars)');

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

      print('[IaService] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        final choices = decoded['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          return {'erro': 'Groq não retornou choices: ${response.body}'};
        }

        final textoBruto = choices[0]['message']['content'] as String;

        print('[IaService] Resposta: $textoBruto');

        final json = jsonDecode(textoBruto);
        final indice = (json['indice'] as num).toInt();
        final mensagem = json['mensagem'] as String;

        if (indice >= 1 && indice <= bancoParcial.length) {
          return {
            'imageUrl': bancoParcial[indice - 1]['imageUrl'] as String,
            'mensagem': mensagem,
          };
        } else {
          return {'imageUrl': null, 'mensagem': mensagem};
        }
      } else {
        String mensagemErro;
        try {
          final erroJson = jsonDecode(response.body);
          mensagemErro = erroJson['error']?['message'] ?? 'Erro desconhecido';
        } catch (_) {
          mensagemErro = 'HTTP ${response.statusCode}: ${response.body}';
        }
        print('[IaService] Erro: $mensagemErro');
        return {'erro': 'Erro Groq: $mensagemErro'};
      }
    } catch (e) {
      print('[IaService] Exceção: $e');
      return {'erro': 'Exceção: $e'};
    }
  }
}
